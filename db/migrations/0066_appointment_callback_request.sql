-- 0066_appointment_callback_request.sql
-- Colonne pour la demande de rappel patient (POST /v1/appointments/:id/callback-request).
-- callback_requested_at : horodatage de la demande (null = pas de demande).

ALTER TABLE appointment
  ADD COLUMN callback_requested_at timestamptz;
