-- 0027_consent_record_unique_purpose.sql
-- Ajoute une contrainte UNIQUE (app_user_id, purpose) sur consent_record.
-- Requise pour l'upsert INSERT ON CONFLICT de PUT /v1/account/consents/{purpose}.
-- Un seul enregistrement par (utilisateur, finalité) — idempotence RGPD garantie.

ALTER TABLE consent_record
  ADD CONSTRAINT consent_record_user_purpose_unique UNIQUE (app_user_id, purpose);
