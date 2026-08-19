-- 0236_visit_request_offer_settlement.sql
-- Corrige #5730 : après le déclin de la DERNIÈRE offre pending d'une demande
-- (ou l'expiration TTL de toutes ses offres sans réponse), `visit_request.status`
-- restait bloqué à 'offered' indéfiniment — aucun re-fanout, aucune transition
-- vers 'expired' (déjà permis par le CHECK de 0234 mais jamais atteint), aucun
-- signal au patient.
--
-- `settle_visit_request_offers` porte TOUTE la résolution d'une demande
-- 'offered' sans offre pending encore valide (TTL dépassé et/ou plus aucune
-- pending) : re-fanout vers d'autres infirmières proches en ligne pas déjà
-- sollicitées pour cette demande, sinon passage à 'expired' (signal explicite
-- au patient via GET /v1/account/visit-requests/:id). Deux appelants :
--   1. `decline_visit_offer` (redéfinie ci-dessous) l'appelle dans LA MÊME
--      transaction/instruction juste après avoir décliné — atomique avec le
--      déclin lui-même (pas un second aller-retour Rust séparé : un déclin
--      qui commite garantit que la résolution a déjà eu lieu, la
--      notification applicative peut échouer sans laisser la demande bloquée
--      à nouveau).
--   2. `expire_stale_visit_offers` (worker périodique côté API, cf.
--      `api/src/visit_offer_expiry.rs`) découvre les demandes 'offered' dont
--      au moins une offre pending a dépassé son TTL, OU qui n'ont déjà plus
--      aucune offre pending (filet de rattrapage générique — couvre aussi le
--      cas résiduel où la notification post-déclin aurait échoué avant que
--      son propre appel de résolution n'ait pu s'exécuter), puis appelle
--      `settle_visit_request_offers` pour chacune.
--
-- Le flip TTL→'expired' d'une offre pending se fait DANS
-- `settle_visit_request_offers`, scopé à `p_request_id`, sous le même verrou
-- `FOR UPDATE` que `claim_visit` (0234) prend sur `visit_request` avant de
-- toucher `visit_offer` — un `UPDATE visit_offer` global non scopé par
-- demande (première version de ce fix) pouvait courir en concurrence avec un
-- `claim_visit` en cours sur la même offre (son UPDATE d'acceptation n'a pas
-- de garde `WHERE status = 'pending'`, cf. 0234) ; le scoper par demande sous
-- le verrou de `visit_request` élimine cette fenêtre.

-- Index de support : `settle_visit_request_offers` (UPDATE TTL scopé +
-- vérif pending restant) et `expire_stale_visit_offers` (découverte des
-- candidats) filtrent tous deux `visit_offer` par (visit_request_id,
-- status='pending'[, expires_at]).
CREATE INDEX idx_visit_offer_request_pending
    ON visit_offer (visit_request_id, expires_at)
    WHERE status = 'pending';

-- `expire_stale_visit_offers` scanne `visit_request WHERE status='offered'`
-- (nombre de demandes actuellement en recherche — sous-ensemble restreint,
-- contrairement à `visit_offer` qui accumule tout l'historique).
CREATE INDEX idx_visit_request_offered
    ON visit_request (id)
    WHERE status = 'offered';

-- Retourne `outcome` + de quoi notifier côté API SANS que l'appelant (rôle
-- `nubia_app`, RLS FORCE active) n'ait besoin de relire `visit_offer`/
-- `visit_request` directement — ces deux tables n'exposent leurs lignes que
-- sous le GUC du tenant concerné (patient/infirmière), qu'un worker
-- périodique hors contexte de requête HTTP n'a aucune raison de connaître.
--
-- `outcome` vaut 'reoffered'/'expired' pour une résolution qui vient de se
-- produire, 'offered' si une offre pending valide subsiste encore (rien à
-- faire), 'not_found' si `p_request_id` n'existe pas, ou 'noop' si la
-- demande n'est déjà plus 'offered' (déjà résolue par un appel concurrent,
-- acceptée, annulée...) — DISTINCT du nom du statut courant : un appelant
-- qui boucle sur plusieurs demandes (`expire_stale_visit_offers`) ne doit
-- JAMAIS confondre "je viens de la faire passer à expired" avec "elle l'était
-- déjà avant mon appel" (sinon double notification patient).
CREATE FUNCTION settle_visit_request_offers(
    p_request_id  uuid,
    p_ttl         interval DEFAULT interval '5 minutes',
    p_max_nurses  integer  DEFAULT 10
) RETURNS TABLE(outcome text, new_nurse_ids uuid[], patient_account_id uuid)
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET row_security = off
  SET search_path = public
AS $$
DECLARE
  cur_status   text;
  req_geo      geography;
  req_patient  uuid;
  pending_left boolean;
  found_nurses uuid[];
BEGIN
  SELECT vr.status, vr.visit_geo, vr.patient_account_id
    INTO cur_status, req_geo, req_patient
    FROM visit_request vr WHERE vr.id = p_request_id FOR UPDATE;

  IF NOT FOUND THEN
    RETURN QUERY SELECT 'not_found'::text, NULL::uuid[], NULL::uuid;
    RETURN;
  END IF;

  IF cur_status <> 'offered' THEN
    RETURN QUERY SELECT 'noop'::text, NULL::uuid[], req_patient;
    RETURN;
  END IF;

  -- Flip TTL→'expired' scopé à CETTE demande, sous le verrou FOR UPDATE
  -- pris ci-dessus (cf. doc de module : élimine la course avec claim_visit).
  UPDATE visit_offer SET status = 'expired', responded_at = now()
    WHERE visit_request_id = p_request_id AND status = 'pending' AND expires_at < now();

  SELECT EXISTS (
    SELECT 1 FROM visit_offer WHERE visit_request_id = p_request_id AND status = 'pending'
  ) INTO pending_left;
  IF pending_left THEN
    RETURN QUERY SELECT 'offered'::text, NULL::uuid[], req_patient;
    RETURN;
  END IF;

  -- Plus aucune offre en attente : tente un re-fanout vers d'autres
  -- infirmières proches en ligne n'ayant pas déjà été sollicitées pour CETTE
  -- demande (UNIQUE(visit_request_id, nurse_id) exclut de toute façon les
  -- doublons, le NOT EXISTS évite juste de re-tenter une infirmière qui a
  -- déjà décliné/expiré sur cette même demande).
  SELECT array_agg(eligible.id) INTO found_nurses
    FROM (
      SELECT id FROM nurse n
      WHERE n.is_online AND n.is_listed AND n.deleted_at IS NULL AND n.geo IS NOT NULL
        AND ST_DWithin(n.geo, req_geo, n.service_radius_m)
        AND NOT EXISTS (
          SELECT 1 FROM visit_offer vo
          WHERE vo.visit_request_id = p_request_id AND vo.nurse_id = n.id
        )
      ORDER BY ST_Distance(n.geo, req_geo) ASC
      LIMIT p_max_nurses
    ) eligible;

  IF found_nurses IS NULL THEN
    UPDATE visit_request SET status = 'expired', updated_at = now()
      WHERE id = p_request_id;
    RETURN QUERY SELECT 'expired'::text, NULL::uuid[], req_patient;
    RETURN;
  END IF;

  INSERT INTO visit_offer (visit_request_id, nurse_id, expires_at)
    SELECT p_request_id, n, now() + p_ttl FROM unnest(found_nurses) AS n
    ON CONFLICT (visit_request_id, nurse_id) DO NOTHING;

  UPDATE visit_request SET offered_at = now(), updated_at = now()
    WHERE id = p_request_id;
  RETURN QUERY SELECT 'reoffered'::text, found_nurses, req_patient;
END;
$$;

-- Redéfinition de `decline_visit_offer` (0234) : le déclin ET sa résolution
-- (`settle_visit_request_offers`) s'exécutent désormais dans le même appel —
-- le type de retour change (`text` → table), donc DROP+CREATE plutôt qu'un
-- simple CREATE OR REPLACE. `result` distingue 'not_found' (rien décliné) de
-- 'declined' (offre déclinée ; `outcome`/`new_nurse_ids`/`patient_account_id`
-- portent alors la résolution, à utiliser côté API pour notifier — cf.
-- `api/src/visit_offer_expiry.rs`).
DROP FUNCTION IF EXISTS decline_visit_offer(uuid, uuid);

CREATE FUNCTION decline_visit_offer(
    p_request_id uuid,
    p_nurse_id   uuid
) RETURNS TABLE(result text, outcome text, new_nurse_ids uuid[], patient_account_id uuid)
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET row_security = off
  SET search_path = public
AS $$
DECLARE
  n   integer;
  res record;
BEGIN
  UPDATE visit_offer SET status = 'declined', responded_at = now()
    WHERE visit_request_id = p_request_id AND nurse_id = p_nurse_id AND status = 'pending';
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n = 0 THEN
    RETURN QUERY SELECT 'not_found'::text, NULL::text, NULL::uuid[], NULL::uuid;
    RETURN;
  END IF;

  SELECT * INTO res FROM settle_visit_request_offers(p_request_id);
  RETURN QUERY SELECT 'declined'::text, res.outcome, res.new_nurse_ids, res.patient_account_id;
END;
$$;

-- Marque expirées les offres pending dont le TTL est dépassé (infirmière
-- n'ayant jamais répondu), puis résout chaque demande concernée. Retourne les
-- demandes dont l'issue a changé (pour les logs du worker périodique côté
-- API). Candidats = toute demande 'offered' avec une offre pending expirée,
-- OU n'ayant déjà plus aucune offre pending (filet générique, cf. doc de
-- module en tête de fichier). Le flip TTL réel a lieu DANS
-- `settle_visit_request_offers`, pas ici — cette fonction ne fait que
-- découvrir les candidats et itérer.
CREATE FUNCTION expire_stale_visit_offers(
    p_ttl        interval DEFAULT interval '5 minutes',
    p_max_nurses integer  DEFAULT 10
) RETURNS TABLE(visit_request_id uuid, outcome text, new_nurse_ids uuid[], patient_account_id uuid)
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET row_security = off
  SET search_path = public
AS $$
DECLARE
  candidate_ids uuid[];
  rid           uuid;
  res           record;
BEGIN
  SELECT array_agg(DISTINCT vr.id) INTO candidate_ids
    FROM visit_request vr
    WHERE vr.status = 'offered'
      AND (
        EXISTS (
          SELECT 1 FROM visit_offer vo
          WHERE vo.visit_request_id = vr.id AND vo.status = 'pending' AND vo.expires_at < now()
        )
        OR NOT EXISTS (
          SELECT 1 FROM visit_offer vo
          WHERE vo.visit_request_id = vr.id AND vo.status = 'pending'
        )
      );

  IF candidate_ids IS NULL THEN RETURN; END IF;

  FOREACH rid IN ARRAY candidate_ids LOOP
    SELECT * INTO res FROM settle_visit_request_offers(rid, p_ttl, p_max_nurses);
    IF res.outcome IN ('reoffered', 'expired') THEN
      visit_request_id := rid;
      outcome := res.outcome;
      new_nurse_ids := res.new_nurse_ids;
      patient_account_id := res.patient_account_id;
      RETURN NEXT;
    END IF;
  END LOOP;
END;
$$;

ALTER FUNCTION settle_visit_request_offers(uuid, interval, integer) OWNER TO nubia_owner;
ALTER FUNCTION decline_visit_offer(uuid, uuid) OWNER TO nubia_owner;
ALTER FUNCTION expire_stale_visit_offers(interval, integer) OWNER TO nubia_owner;
REVOKE ALL ON FUNCTION settle_visit_request_offers(uuid, interval, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION decline_visit_offer(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION expire_stale_visit_offers(interval, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION settle_visit_request_offers(uuid, interval, integer) TO nubia_app;
GRANT EXECUTE ON FUNCTION decline_visit_offer(uuid, uuid) TO nubia_app;
GRANT EXECUTE ON FUNCTION expire_stale_visit_offers(interval, integer) TO nubia_app;

-- La description de 0234 omettait `expired` de la machine à états (déjà
-- permis par le CHECK, mais jamais atteint avant ce fix, cf. #5730).
COMMENT ON TABLE visit_request IS
    'Demande de visite infirmière à domicile + machine à états (requested→offered→accepted→en_route→arrived→done), + cancelled (patient) et expired (dernière offre déclinée/expirée sans infirmière disponible, cf. settle_visit_request_offers). RLS 2 ancres patient/infirmière. Clone de pharmacy_order (0124). Épic app infirmières.';
