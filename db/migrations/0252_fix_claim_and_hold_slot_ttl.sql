-- 0252_fix_claim_and_hold_slot_ttl.sql
-- Corrige le TTL du hold de créneau posé par claim_and_hold_slot() (issue #6510).
--
-- La migration 0120 (#3259) a déplacé l'INSERT du hold depuis le handler Rust
-- vers cette fonction SECURITY DEFINER, avec un TTL de 5 minutes. La 0232
-- (#5363) l'a déjà aligné sur les 10 minutes de la maquette design-v2,
-- documentées dans api/src/marketplace.rs:1304-1305 et
-- front/apps/app_patient/lib/features/appointments/appointments_event.dart:129 —
-- ce correctif reprend donc intégralement la logique de 0232 (gardes
-- deleted_at/online_booking/starts_at de 0140/0142/0145, libération du hold
-- expiré de 0141) : la version précédente de cette migration était repartie
-- d'un état antérieur à ces correctifs et les avait régressés.

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
  current_online_booking boolean;
  current_starts_at timestamptz;
  exp timestamptz;
BEGIN
  -- Verrou de ligne : sérialise les claims concurrents sur le même créneau.
  SELECT status, deleted_at, online_booking, starts_at
    INTO current_status, current_deleted_at, current_online_booking, current_starts_at
    FROM availability_slot WHERE id = p_slot_id FOR UPDATE;
  IF NOT FOUND OR current_deleted_at IS NOT NULL OR NOT current_online_booking
     OR current_starts_at <= now() THEN
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
