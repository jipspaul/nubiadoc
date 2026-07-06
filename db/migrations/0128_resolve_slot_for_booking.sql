-- 0128_resolve_slot_for_booking.sql
-- Corrige le 404 systématique de POST /v1/bookings après un hold (#3347).
--
-- Cause : toutes les policies SELECT d'availability_slot filtrent
-- `status = 'open'` (slot_public_read 0059, availability_slot_patient_read
-- 0117). Or claim_and_hold_slot (0120) passe le créneau en 'held' AVANT le
-- booking : le SELECT de create_booking ne voyait plus la ligne → 404.
-- (Même cause que les 4 échecs de api/tests/bookings_post.rs.)
--
-- Fix : résolution du créneau via une fonction SECURITY DEFINER dédiée,
-- comme claim_and_hold_slot. La sécurité reste assurée par create_booking :
-- le hold (token + user_id + expiration) est validé immédiatement après,
-- avant toute écriture.
-- Issue : #3347

CREATE FUNCTION resolve_slot_for_booking(p_slot_id uuid)
RETURNS TABLE(
  cabinet_id      uuid,
  practitioner_id uuid,
  starts_at       timestamptz,
  ends_at         timestamptz
)
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET row_security = off
AS $$
  SELECT s.cabinet_id, s.practitioner_id, s.starts_at, s.ends_at
  FROM availability_slot s
  WHERE s.id = p_slot_id AND s.deleted_at IS NULL;
$$;

ALTER FUNCTION resolve_slot_for_booking(uuid) OWNER TO nubia_owner;
REVOKE ALL ON FUNCTION resolve_slot_for_booking(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION resolve_slot_for_booking(uuid) TO nubia_app;
