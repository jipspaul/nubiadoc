-- 0139_availability_slot_status_blocked.sql
-- #3551 : create_cabinet_slot / patch_cabinet_slot (api/src/scheduling.rs)
-- acceptent status="blocked" (cf. 0075 : nubia_app gere SES creneaux, tous
-- statuts) mais le CHECK d'origine (0009) ne listait que
-- ('open','held','booked') -> INSERT/UPDATE violait la contrainte (23514),
-- mappe en 500 internal_error au lieu de 201/200.
-- Issue : #3551

ALTER TABLE availability_slot DROP CONSTRAINT availability_slot_status_check;
ALTER TABLE availability_slot ADD CONSTRAINT availability_slot_status_check
  CHECK (status IN ('open','held','booked','blocked'));
