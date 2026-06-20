-- 0105_appointments_provider_start_at_idx.sql
-- Index composite sur appointments(provider_id, start_at) pour les requêtes
-- d'agenda secrétariat + praticien (range query sur fenêtre temporelle).
-- CONCURRENTLY : pas de lock exclusif sur la table en production.
-- Partiel WHERE deleted_at IS NULL : exclut les rendez-vous supprimés (soft-delete).
-- Issue : #2234

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_appointments_provider_start_at
    ON appointments (provider_id, start_at)
    WHERE deleted_at IS NULL;

COMMENT ON INDEX idx_appointments_provider_start_at IS 'agenda range query : provider + window start_at';
