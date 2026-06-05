-- 0030_appointment_checkin_columns.sql
-- Colonnes pour le check-in patient (POST /v1/appointments/:id/checkin).
-- checkin_at : horodatage du check-in. checkin_method : mode de présentation.

ALTER TABLE appointment
  ADD COLUMN checkin_at     timestamptz,
  ADD COLUMN checkin_method text CHECK (checkin_method IN ('qr', 'geo', 'manual'));
