-- 0020_provider_verification_resolved_at.sql
-- Ajoute resolved_at à provider_verification : horodatage positionné par le job
-- apalis après interrogation de l'annuaire ANS (RPPS/ADELI). Issue : #209.

ALTER TABLE provider_verification
    ADD COLUMN IF NOT EXISTS resolved_at timestamptz;
