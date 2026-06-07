-- 0080_provider_tiers_payant.sql
-- Ajoute tiers_payant au profil public provider (marketplace §12.2).
-- Indique si le praticien accepte le tiers payant côté patient.
-- Nullable (non renseigné = information non disponible).
-- Issue : #560

ALTER TABLE provider
    ADD COLUMN IF NOT EXISTS tiers_payant boolean;
