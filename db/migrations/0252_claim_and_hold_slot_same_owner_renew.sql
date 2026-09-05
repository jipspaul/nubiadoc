-- 0252_claim_and_hold_slot_same_owner_renew.sql
-- #6509 : re-poser un hold sur SON PROPRE créneau renvoie 409 slot_taken.
--
-- claim_and_hold_slot (0120/.../0232) ne compare jamais p_user_id au
-- propriétaire du hold actif : si le créneau est déjà 'held' (et le hold pas
-- expiré, cf. purge #3606 en 0141), la fonction renvoie current_status='held'
-- inconditionnellement -> handler mappe tout retour <> 'claimed' sur 409
-- (marketplace.rs:1349). Un patient qui pose un hold puis quitte le flux
-- (BACK navigateur, cf. #6236 sur l'URL qui ne suit pas l'étape) sans jamais
-- réserver ni relâcher explicitement se retrouve donc verrouillé hors de SON
-- PROPRE créneau jusqu'à expiration du hold (10 min), sans pouvoir le
-- reprendre par re-clic ni par recherche (le slot disparaît de /search/slots
-- tant qu'il est 'held').
--
-- Fix : si le hold actif sur le créneau appartient déjà à p_user_id, on le
-- renouvelle (nouveau hold_token, expires_at repoussé) au lieu de rejeter --
-- poser un hold est ainsi idempotent pour son propre détenteur. Le 409
-- slot_taken reste inchangé quand le hold appartient à un AUTRE patient.
-- Issue : #6509

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

  -- #6509 : hold actif (non expiré) déjà détenu par CE patient -> renouvellement
  -- au lieu d'un rejet 409, pour rester idempotent sur son propre créneau.
  IF current_status = 'held' THEN
    UPDATE slot_holds
      SET hold_token = p_hold_token, expires_at = now() + interval '10 minutes'
      WHERE slot_id = p_slot_id AND user_id = p_user_id
      RETURNING expires_at INTO exp;
    IF FOUND THEN
      RETURN QUERY SELECT 'claimed'::text, exp;              -- 200 (renouvelé)
      RETURN;
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
