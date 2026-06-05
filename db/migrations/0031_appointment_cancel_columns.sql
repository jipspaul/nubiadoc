-- 0031_appointment_cancel_columns.sql
-- Colonnes pour l'annulation patient (POST /v1/appointments/:id/cancel).
-- cancelled_at : horodatage de l'annulation.
-- slot_id      : créneau réservé à libérer si non-null.

ALTER TABLE appointment
  ADD COLUMN cancelled_at timestamptz,
  ADD COLUMN slot_id      uuid REFERENCES availability_slot(id);
