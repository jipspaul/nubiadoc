-- 0120_claim_and_hold_slot.sql
-- Corrige le parcours patient de réservation de créneau (issue #3259).
--
-- Depuis la migration 0110, la policy `slot_hold_cabinet_isolation` sur
-- `slot_holds` exige `app.current_cabinet_id` = cabinet du créneau (isolation
-- des holds entre cabinets, côté back-office). Or le flux PATIENT (POST
-- /v1/slots/:id/hold) ne pose jamais ce GUC : l'INSERT dans `slot_holds` est
-- alors rejeté ("new row violates row-level security policy") → 500, et le
-- patient ne peut jamais réserver.
--
-- Le handler `hold_slot` faisait déjà le claim du créneau via la fonction
-- SECURITY DEFINER `try_claim_slot` (qui contourne la RLS), mais l'INSERT du
-- hold restait une requête `nubia_app` soumise à la policy. On regroupe donc le
-- claim ET l'INSERT dans une seule fonction SECURITY DEFINER (owner nubia_owner,
-- BYPASSRLS) : le patient peut poser un hold sans contexte cabinet, tout en
-- préservant l'isolation cabinet en LECTURE (policy 0110 inchangée).
--
-- Sémantique de retour :
--   claim_result = NULL      → créneau inexistant         (handler → 404)
--   claim_result = <status>  → créneau pas 'open'          (handler → 409)
--   claim_result = 'taken'   → hold concurrent (unique)    (handler → 409)
--   claim_result = 'claimed' → succès, hold_expires_at set (handler → 200)
-- Le sentinel de succès est 'claimed' (et non 'held') pour ne pas être ambigu
-- avec le statut réel 'held' renvoyé quand le créneau est déjà réservé.

CREATE FUNCTION claim_and_hold_slot(
  p_slot_id uuid,
  p_user_id uuid,
  p_hold_token text
) RETURNS TABLE(claim_result text, hold_expires_at timestamptz)
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET row_security = off
AS $$
DECLARE
  current_status text;
  exp timestamptz;
BEGIN
  -- Verrou de ligne : sérialise les claims concurrents sur le même créneau.
  SELECT status INTO current_status
    FROM availability_slot WHERE id = p_slot_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN QUERY SELECT NULL::text, NULL::timestamptz;      -- 404
    RETURN;
  END IF;
  IF current_status <> 'open' THEN
    RETURN QUERY SELECT current_status, NULL::timestamptz;  -- 409
    RETURN;
  END IF;

  -- INSERT d'abord : si un hold existe déjà (contrainte UNIQUE slot_id), on
  -- sort sans avoir modifié le statut du créneau (reste 'open').
  BEGIN
    INSERT INTO slot_holds (slot_id, user_id, hold_token, expires_at)
      VALUES (p_slot_id, p_user_id, p_hold_token, now() + interval '5 minutes')
      RETURNING expires_at INTO exp;
  EXCEPTION WHEN unique_violation THEN
    RETURN QUERY SELECT 'taken'::text, NULL::timestamptz;   -- 409 (race)
    RETURN;
  END;

  UPDATE availability_slot SET status = 'held' WHERE id = p_slot_id;
  RETURN QUERY SELECT 'claimed'::text, exp;                 -- 200
END;
$$;

ALTER FUNCTION claim_and_hold_slot(uuid, uuid, text) OWNER TO nubia_owner;
REVOKE ALL ON FUNCTION claim_and_hold_slot(uuid, uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION claim_and_hold_slot(uuid, uuid, text) TO nubia_app;
