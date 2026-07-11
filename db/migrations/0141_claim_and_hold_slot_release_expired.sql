-- 0141_claim_and_hold_slot_release_expired.sql
-- #3606 : un hold expiré n'est jamais libéré, le créneau reste 'held' à vie.
--
-- Rien ne purge slot_holds à expires_at (pas de job de reaper, JobDispatcher
-- = StubJobDispatcher no-op) : claim_and_hold_slot (0120/0140) lisait
-- uniquement `status`, jamais `slot_holds.expires_at`. Un hold abandonné
-- (patient qui pose un hold puis ne réserve jamais) stérilise donc le
-- créneau définitivement (re-hold → 409 slot_taken, invisible des
-- disponibilités qui filtrent status='open').
--
-- Fix : si le créneau est 'held', on purge d'abord le hold expiré (le cas
-- échéant) et on repasse le créneau 'open' avant le check de statut, comme
-- le documente la migration 0095 (« expiration automatique ... DELETE à
-- l'expiration »). Le verrou FOR UPDATE déjà posé sérialise cette libération
-- vis-à-vis des claims concurrents.
-- Issue : #3606

CREATE OR REPLACE FUNCTION claim_and_hold_slot(
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
  current_deleted_at timestamptz;
  exp timestamptz;
BEGIN
  -- Verrou de ligne : sérialise les claims concurrents sur le même créneau.
  SELECT status, deleted_at INTO current_status, current_deleted_at
    FROM availability_slot WHERE id = p_slot_id FOR UPDATE;
  IF NOT FOUND OR current_deleted_at IS NOT NULL THEN
    RETURN QUERY SELECT NULL::text, NULL::timestamptz;      -- 404
    RETURN;
  END IF;

  -- Libère un hold expiré non transformé en réservation (#3606) avant le
  -- check de statut : sinon le créneau reste 'held' indéfiniment.
  IF current_status = 'held' THEN
    DELETE FROM slot_holds WHERE slot_id = p_slot_id AND expires_at <= now();
    IF FOUND THEN
      UPDATE availability_slot SET status = 'open' WHERE id = p_slot_id;
      current_status := 'open';
    END IF;
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
