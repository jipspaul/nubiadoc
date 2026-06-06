-- 0057_appointment_callback_requested_at.sql
-- Colonne pour la demande de rappel patient (POST /v1/appointments/:id/callback-request).
-- callback_requested_at : horodatage de la demande de rappel.

ALTER TABLE appointment
  ADD COLUMN callback_requested_at timestamptz;
