-- 0130_checkin_event_mode_manual.sql
-- Étend le CHECK de checkin_event.mode pour accepter 'manual' (check-in patient
-- sans QR code, cf. POST /v1/appointments/:id/checkin quand qr_code est absent).

ALTER TABLE checkin_event
  DROP CONSTRAINT IF EXISTS checkin_event_mode_check;

ALTER TABLE checkin_event
  ADD CONSTRAINT checkin_event_mode_check
    CHECK (mode IN ('qr_app', 'qr_web', 'borne', 'sms', 'manual'));
