-- 0131_appointment_checkin_method_qr_app.sql
-- Étend le CHECK de appointment.checkin_method pour accepter 'qr_app' (valeur
-- écrite par POST /v1/appointments/:id/checkin quand qr_code est fourni).

ALTER TABLE appointment
  DROP CONSTRAINT IF EXISTS appointment_checkin_method_check;

ALTER TABLE appointment
  ADD CONSTRAINT appointment_checkin_method_check
    CHECK (checkin_method IN ('qr', 'qr_app', 'geo', 'manual'));
