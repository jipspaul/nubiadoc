-- 0017_consent_record_platform.sql
-- Refactore consent_record : entité plateforme RGPD/CGU liée à app_user.
-- L'ancienne modélisation (0008) était cabinet-scoped (cabinet_id + patient_id) ;
-- le modèle cible est plateforme-level (app_user_id), sans RLS cabinet.
-- La policy RLS tenant_isolation posée en 0011 référence cabinet_id → droppée avant la colonne.
-- Issue : #180

-- 1. Supprimer la policy RLS cabinet (posée en 0011) puis désactiver RLS.
DROP POLICY IF EXISTS tenant_isolation ON consent_record;
ALTER TABLE consent_record DISABLE ROW LEVEL SECURITY;

-- 2. Supprimer les colonnes cabinet/patient (remplacées par app_user_id).
ALTER TABLE consent_record
  DROP COLUMN IF EXISTS cabinet_id,
  DROP COLUMN IF EXISTS patient_id,
  DROP COLUMN IF EXISTS evidence;

-- 3. granted_at → nullable (la date peut être posée à l'INSERT, pas en défaut de colonne).
ALTER TABLE consent_record ALTER COLUMN granted_at DROP NOT NULL;

-- 4. Ajouter les colonnes plateforme.
--    app_user_id NOT NULL : safe car la table est vide à ce stade (jamais de seed pre-0017).
ALTER TABLE consent_record
  ADD COLUMN IF NOT EXISTS app_user_id UUID        NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  ADD COLUMN IF NOT EXISTS cgu_version TEXT,
  ADD COLUMN IF NOT EXISTS created_at  TIMESTAMPTZ NOT NULL DEFAULT now();

COMMENT ON TABLE consent_record IS 'Consentements RGPD/CGU par compte app_user (plateforme). Append-only. Réf. docs/12 §1.8, §3.';
