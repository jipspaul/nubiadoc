-- 0140_claim_and_hold_slot_exclude_deleted.sql
-- #3550 : claim_and_hold_slot (0120) ne verifie pas deleted_at -> un slot
-- soft-delete (DELETE /v1/cabinet/slots/:id) mais encore status='open'
-- pouvait etre hold par un patient (200), puis echouait en 404 au booking
-- (resolve_slot_for_booking, 0128, filtre deja deleted_at IS NULL) : hold
-- reussi + booking impossible = cul-de-sac, et le hold repassait en plus le
-- slot supprime en statut 'held' (creneau fantome ressuscite).
-- Fix : un slot deleted_at IS NOT NULL est traite comme inexistant (404),
-- au meme titre qu'un slot introuvable.
-- Issue : #3550

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
