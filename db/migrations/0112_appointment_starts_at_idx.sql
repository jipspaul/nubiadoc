-- 0112_appointment_starts_at_idx.sql
-- Index partiel sur appointment(starts_at) WHERE status='confirmed'.
-- Accélère les requêtes « liste upcoming » et booking qui filtrent sur
-- les RDV confirmés par date (FR1.2).
-- Issue : #2471

CREATE INDEX IF NOT EXISTS idx_appointment_starts_at_confirmed
    ON appointment (starts_at)
    WHERE status = 'confirmed';

COMMENT ON INDEX idx_appointment_starts_at_confirmed IS 'upcoming confirmed appointments : range query sur starts_at';
