-- 0248_fix_claim_visit_replay.sql
-- Fix #6383 : `claim_visit` (0234) renvoyait le statut courant quand la
-- demande n'était plus 'offered', qui vaut littéralement 'accepted' sur un
-- rejeu d'un accept déjà traité — indistinguable du 'accepted' de succès pour
-- le handler (`api/src/nurse/visits.rs`), qui renotifiait donc le patient à
-- chaque rejeu au lieu de renvoyer 409. On renvoie désormais un sentinel
-- dédié ('invalid_status') pour tout statut courant autre que 'offered'.

CREATE OR REPLACE FUNCTION claim_visit(
    p_request_id uuid,
    p_nurse_id   uuid
) RETURNS text
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET row_security = off
  SET search_path = public
AS $$
DECLARE
  cur_status text;
  has_offer  boolean;
BEGIN
  SELECT status INTO cur_status FROM visit_request WHERE id = p_request_id FOR UPDATE;
  IF NOT FOUND THEN RETURN 'not_found'; END IF;
  IF cur_status <> 'offered' THEN RETURN 'invalid_status'; END IF;

  SELECT EXISTS (
    SELECT 1 FROM visit_offer
    WHERE visit_request_id = p_request_id AND nurse_id = p_nurse_id AND status = 'pending'
  ) INTO has_offer;
  IF NOT has_offer THEN RETURN 'no_offer'; END IF;

  UPDATE visit_request
    SET nurse_id = p_nurse_id, status = 'accepted', accepted_at = now(), updated_at = now()
    WHERE id = p_request_id;

  UPDATE visit_offer SET status = 'accepted', responded_at = now()
    WHERE visit_request_id = p_request_id AND nurse_id = p_nurse_id;
  UPDATE visit_offer SET status = 'expired', responded_at = now()
    WHERE visit_request_id = p_request_id AND nurse_id <> p_nurse_id AND status = 'pending';
  RETURN 'accepted';
END;
$$;

COMMENT ON FUNCTION claim_visit(uuid, uuid) IS
    'Accepte une offre (premier-gagne). Retour : ''accepted'' (succès) | ''invalid_status'' (409, plus ''offered'' — dont rejeu d''un accept déjà traité) | ''no_offer'' | ''not_found''.';
