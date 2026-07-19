-- 0152_resolve_slot_for_booking_status.sql
-- Jumeau de #3637 (corrigé sur POST /appointments) : un créneau `blocked`
-- (indisponibilité praticien posée APRÈS le hold patient) redevenait
-- réservable via POST /bookings. resolve_slot_for_booking (0128) ne
-- renvoyait pas `status`, donc create_booking ne pouvait pas re-vérifier
-- que le créneau était toujours dans l'état légitime `held` au moment du
-- booking (au lieu de `blocked`, posé entre-temps par le secrétariat).
-- Issue : #3744

DROP FUNCTION IF EXISTS resolve_slot_for_booking(uuid);

CREATE FUNCTION resolve_slot_for_booking(p_slot_id uuid)
RETURNS TABLE(
  cabinet_id      uuid,
  practitioner_id uuid,
  starts_at       timestamptz,
  ends_at         timestamptz,
  status          text
)
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET row_security = off
AS $$
  SELECT s.cabinet_id, s.practitioner_id, s.starts_at, s.ends_at, s.status
  FROM availability_slot s
  WHERE s.id = p_slot_id AND s.deleted_at IS NULL;
$$;

ALTER FUNCTION resolve_slot_for_booking(uuid) OWNER TO nubia_owner;
REVOKE ALL ON FUNCTION resolve_slot_for_booking(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION resolve_slot_for_booking(uuid) TO nubia_app;
