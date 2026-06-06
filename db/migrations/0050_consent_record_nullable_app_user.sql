-- 0050_consent_record_nullable_app_user.sql
-- Rend app_user_id nullable dans consent_record.
-- La table sert désormais deux cas : CGU plateforme (app_user_id) et RGPD patient portal
-- (patient_account_id, ajouté en 0048). Les lignes RGPD n'ont pas forcément d'app_user_id.
-- La contrainte UNIQUE(app_user_id, purpose) de 0027 reste valide : les NULLs sont distincts
-- en SQL → plusieurs lignes patient (app_user_id=NULL) ne conflictent pas.
-- Issue : #720

ALTER TABLE consent_record ALTER COLUMN app_user_id DROP NOT NULL;
