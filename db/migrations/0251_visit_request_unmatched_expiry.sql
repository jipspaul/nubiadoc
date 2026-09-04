-- 0251_visit_request_unmatched_expiry.sql
-- Corrige #6450 : une demande de visite créée alors qu'AUCUNE infirmière
-- n'est en ligne (fan-out de `POST /v1/account/visit-requests`,
-- `api/src/nurse/requests.rs`, vide de candidats) reste bloquée en
-- `status = 'requested'` / `nurse_id = NULL` indéfiniment — 0236 (#5730) a
-- résolu ce trou pour la branche `offered` (dernière offre déclinée/expirée)
-- mais rien ne reprenait jamais une demande qui n'avait même pas eu de
-- première offre.
--
-- Même remède que 0236, décliné pour `requested` : `settle_unmatched_visit_request`
-- retente un fan-out vers les infirmières proches désormais en ligne, sinon
-- passe la demande à `expired` (déjà permis par le CHECK de 0234) une fois
-- `p_max_wait` dépassé depuis `requested_at` — pas immédiatement, pour laisser
-- une chance à une infirmière de repasser en ligne dans l'intervalle (cf.
-- repro #6450 : l'infirmière revient en ligne quelques secondes après la
-- demande). `expire_stale_visit_requests` découvre les candidats ; les deux
-- sont appelés depuis le même worker périodique que 0236
-- (`api/src/visit_offer_expiry.rs`, tick 30s), réutilisant tel quel
-- `apply_settlement` : les outcomes `reoffered`/`expired` qu'il retourne sont
-- déjà gérés (notifie les infirmières sollicitées / notifie le patient).

CREATE INDEX idx_visit_request_requested
    ON visit_request (id)
    WHERE status = 'requested';

-- Retente un fan-out pour une demande `requested` sans offre ; expire si
-- aucune infirmière n'est disponible ET que `p_max_wait` est dépassé depuis
-- `requested_at`. Retour : 'reoffered' (fan-out réussi) | 'expired' | 'requested'
-- (encore dans la fenêtre d'attente, rien à faire) | 'noop' (déjà résolue par
-- un appel concurrent) | 'not_found'.
CREATE FUNCTION settle_unmatched_visit_request(
    p_request_id uuid,
    p_ttl        interval DEFAULT interval '5 minutes',
    p_max_nurses integer  DEFAULT 10,
    p_max_wait   interval DEFAULT interval '5 minutes'
) RETURNS TABLE(outcome text, new_nurse_ids uuid[], patient_account_id uuid)
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET row_security = off
  SET search_path = public
AS $$
DECLARE
  cur_status        text;
  req_geo           geography;
  req_patient       uuid;
  req_requested_at  timestamptz;
  found_nurses      uuid[];
BEGIN
  SELECT vr.status, vr.visit_geo, vr.patient_account_id, vr.requested_at
    INTO cur_status, req_geo, req_patient, req_requested_at
    FROM visit_request vr WHERE vr.id = p_request_id FOR UPDATE;

  IF NOT FOUND THEN
    RETURN QUERY SELECT 'not_found'::text, NULL::uuid[], NULL::uuid;
    RETURN;
  END IF;

  IF cur_status <> 'requested' THEN
    RETURN QUERY SELECT 'noop'::text, NULL::uuid[], req_patient;
    RETURN;
  END IF;

  SELECT array_agg(eligible.id) INTO found_nurses
    FROM (
      SELECT id FROM nurse n
      WHERE n.is_online AND n.is_listed AND n.deleted_at IS NULL AND n.geo IS NOT NULL
        AND ST_DWithin(n.geo, req_geo, n.service_radius_m)
      ORDER BY ST_Distance(n.geo, req_geo) ASC
      LIMIT p_max_nurses
    ) eligible;

  IF found_nurses IS NOT NULL THEN
    INSERT INTO visit_offer (visit_request_id, nurse_id, expires_at)
      SELECT p_request_id, n, now() + p_ttl FROM unnest(found_nurses) AS n
      ON CONFLICT (visit_request_id, nurse_id) DO NOTHING;

    UPDATE visit_request SET status = 'offered', offered_at = now(), updated_at = now()
      WHERE id = p_request_id;
    RETURN QUERY SELECT 'reoffered'::text, found_nurses, req_patient;
    RETURN;
  END IF;

  IF now() - req_requested_at >= p_max_wait THEN
    UPDATE visit_request SET status = 'expired', updated_at = now()
      WHERE id = p_request_id;
    RETURN QUERY SELECT 'expired'::text, NULL::uuid[], req_patient;
    RETURN;
  END IF;

  RETURN QUERY SELECT 'requested'::text, NULL::uuid[], req_patient;
END;
$$;

-- Découvre les demandes `requested` et les résout une à une (même pattern que
-- `expire_stale_visit_offers`, 0236). Ne retourne que celles dont l'issue a
-- changé (reoffered/expired) — le worker périodique n'a rien à logger sinon.
CREATE FUNCTION expire_stale_visit_requests(
    p_ttl        interval DEFAULT interval '5 minutes',
    p_max_nurses integer  DEFAULT 10,
    p_max_wait   interval DEFAULT interval '5 minutes'
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
  SELECT array_agg(vr.id) INTO candidate_ids
    FROM visit_request vr WHERE vr.status = 'requested';

  IF candidate_ids IS NULL THEN RETURN; END IF;

  FOREACH rid IN ARRAY candidate_ids LOOP
    SELECT * INTO res FROM settle_unmatched_visit_request(rid, p_ttl, p_max_nurses, p_max_wait);
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

ALTER FUNCTION settle_unmatched_visit_request(uuid, interval, integer, interval) OWNER TO nubia_owner;
ALTER FUNCTION expire_stale_visit_requests(interval, integer, interval) OWNER TO nubia_owner;
REVOKE ALL ON FUNCTION settle_unmatched_visit_request(uuid, interval, integer, interval) FROM PUBLIC;
REVOKE ALL ON FUNCTION expire_stale_visit_requests(interval, integer, interval) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION settle_unmatched_visit_request(uuid, interval, integer, interval) TO nubia_app;
GRANT EXECUTE ON FUNCTION expire_stale_visit_requests(interval, integer, interval) TO nubia_app;
