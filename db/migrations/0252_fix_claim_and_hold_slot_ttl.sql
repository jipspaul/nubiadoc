-- 0252_fix_claim_and_hold_slot_ttl.sql
-- Corrige le TTL du hold de créneau posé par claim_and_hold_slot() (issue #6510).
--
-- La migration 0120 (#3259) a déplacé l'INSERT du hold depuis le handler Rust
-- vers cette fonction SECURITY DEFINER, et a recopié un TTL de 5 minutes au
-- lieu des 10 minutes fixées par la décision produit #5363 (alignée sur la
-- maquette design-v2), documentées dans api/src/marketplace.rs:1304-1305 et
-- front/apps/app_patient/lib/features/appointments/appointments_event.dart:129.
-- On aligne l'implémentation sur cette documentation.

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
      VALUES (p_slot_id, p_user_id, p_hold_token, now() + interval '10 minutes')
      RETURNING expires_at INTO exp;
  EXCEPTION WHEN unique_violation THEN
    RETURN QUERY SELECT 'taken'::text, NULL::timestamptz;   -- 409 (race)
    RETURN;
  END;

  UPDATE availability_slot SET status = 'held' WHERE id = p_slot_id;
  RETURN QUERY SELECT 'claimed'::text, exp;                 -- 200
END;
$$;
