-- 0108_appointment_cancel_reason.sql
-- Colonne cancel_reason pour POST /v1/appointments/:id/cancel (issue #2437).

ALTER TABLE appointment
  ADD COLUMN cancel_reason text;
