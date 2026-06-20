-- 0105_appointments_provider_start_at_idx.sql
-- Index composite sur appointment(practitioner_id, starts_at) pour les requêtes
-- d'agenda secrétariat + praticien (range query sur fenêtre temporelle).
-- Partiel WHERE deleted_at IS NULL : exclut les rendez-vous supprimés (soft-delete).
-- Issue : #2234

CREATE INDEX IF NOT EXISTS idx_appointment_practitioner_starts_at
    ON appointment (practitioner_id, starts_at)
    WHERE deleted_at IS NULL;

COMMENT ON INDEX idx_appointment_practitioner_starts_at IS 'agenda range query : practitioner + window starts_at';
