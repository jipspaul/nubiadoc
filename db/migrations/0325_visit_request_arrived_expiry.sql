-- 0325_visit_request_arrived_expiry.sql
-- Corrige #8502 : contrairement aux trois autres statuts non terminaux de
-- `visit_request` (`requested`/`offered` balayés par `expire_stale_visit_requests`
-- / `expire_stale_visit_offers`, 0236/0251 ; `accepted`/`en_route` annulables par
-- le patient, 0234), `arrived` n'avait AUCUNE sortie hors
-- `POST /v1/nurse/visits/:id/done`. Une infirmière qui marque « arrivée » puis
-- ne clôture jamais (batterie vide, app fermée, oubli, démission) gèle la
-- demande : `visit_request_patient_cancel` l'exclut déjà volontairement
-- (#7734, cf. `api/src/nurse/requests.rs`) pour ne pas priver l'infirmière de
-- sa propre clôture, et `visit_request_active_patient` (0234) compte `arrived`
-- comme actif, donc le patient ne peut plus jamais redemander non plus.
--
-- `settle_stale_arrived_visit`/`expire_stale_arrived_visits` reprennent le
-- même pattern que 0236/0251 : TTL depuis `arrived_at`, SECURITY DEFINER
-- (bypass RLS, worker périodique hors contexte de requête). Issue choisie :
-- passage direct à `done` plutôt que `cancelled`/`expired` — l'infirmière
-- était physiquement sur place, la visite a vraisemblablement eu lieu ; la
-- geler indéfiniment serait pire que la clôturer tardivement sans preuve
-- explicite de clôture manuelle. Appelée depuis le même worker que 0236/0251
-- (`api/src/visit_offer_expiry.rs`, tick 30s).

CREATE INDEX idx_visit_request_arrived
    ON visit_request (id)
    WHERE status = 'arrived';

-- Retourne 'auto_done' (TTL dépassé, vient d'être clôturée), 'arrived'
-- (encore dans la fenêtre, rien à faire), 'noop' (déjà résolue par
-- `done`/annulation concurrente) ou 'not_found'.
CREATE FUNCTION settle_stale_arrived_visit(
    p_request_id uuid,
    p_max_wait   interval DEFAULT interval '2 hours'
) RETURNS TABLE(outcome text, patient_account_id uuid, nurse_id uuid)
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET row_security = off
  SET search_path = public
AS $$
DECLARE
  cur_status  text;
  req_patient uuid;
  req_nurse   uuid;
  req_arrived timestamptz;
BEGIN
  SELECT vr.status, vr.patient_account_id, vr.nurse_id, vr.arrived_at
    INTO cur_status, req_patient, req_nurse, req_arrived
    FROM visit_request vr WHERE vr.id = p_request_id FOR UPDATE;

  IF NOT FOUND THEN
    RETURN QUERY SELECT 'not_found'::text, NULL::uuid, NULL::uuid;
    RETURN;
  END IF;

  IF cur_status <> 'arrived' THEN
    RETURN QUERY SELECT 'noop'::text, req_patient, req_nurse;
    RETURN;
  END IF;

  IF now() - req_arrived >= p_max_wait THEN
    UPDATE visit_request SET status = 'done', done_at = now(), updated_at = now()
      WHERE id = p_request_id;
    RETURN QUERY SELECT 'auto_done'::text, req_patient, req_nurse;
    RETURN;
  END IF;

  RETURN QUERY SELECT 'arrived'::text, req_patient, req_nurse;
END;
$$;

-- Découvre les visites `arrived` et les résout une à une (même pattern que
-- `expire_stale_visit_requests`, 0251). Ne retourne que celles dont l'issue a
-- changé (`auto_done`).
CREATE FUNCTION expire_stale_arrived_visits(
    p_max_wait interval DEFAULT interval '2 hours'
) RETURNS TABLE(visit_request_id uuid, outcome text, patient_account_id uuid, nurse_id uuid)
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
    FROM visit_request vr WHERE vr.status = 'arrived';

  IF candidate_ids IS NULL THEN RETURN; END IF;

  FOREACH rid IN ARRAY candidate_ids LOOP
    SELECT * INTO res FROM settle_stale_arrived_visit(rid, p_max_wait);
    IF res.outcome = 'auto_done' THEN
      visit_request_id := rid;
      outcome := res.outcome;
      patient_account_id := res.patient_account_id;
      nurse_id := res.nurse_id;
      RETURN NEXT;
    END IF;
  END LOOP;
END;
$$;

ALTER FUNCTION settle_stale_arrived_visit(uuid, interval) OWNER TO nubia_owner;
ALTER FUNCTION expire_stale_arrived_visits(interval) OWNER TO nubia_owner;
REVOKE ALL ON FUNCTION settle_stale_arrived_visit(uuid, interval) FROM PUBLIC;
REVOKE ALL ON FUNCTION expire_stale_arrived_visits(interval) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION settle_stale_arrived_visit(uuid, interval) TO nubia_app;
GRANT EXECUTE ON FUNCTION expire_stale_arrived_visits(interval) TO nubia_app;
