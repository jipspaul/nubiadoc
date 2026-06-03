-- 0015_patient_account_constraints.sql
-- Renforce patient_account (déjà créée en 0009) :
--   - app_user_id NOT NULL + ON DELETE CASCADE (1 compte patient → 1 dossier plateforme)
--   - ajout phone TEXT
--   - ajout updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
-- Issue : #178

-- Recréer la FK avec ON DELETE CASCADE (la FK sans cascade a été posée en 0009).
ALTER TABLE patient_account DROP CONSTRAINT IF EXISTS patient_account_app_user_id_fkey;
ALTER TABLE patient_account
  ADD CONSTRAINT patient_account_app_user_id_fkey
  FOREIGN KEY (app_user_id) REFERENCES app_user(id) ON DELETE CASCADE;

ALTER TABLE patient_account ALTER COLUMN app_user_id SET NOT NULL;

ALTER TABLE patient_account
  ADD COLUMN IF NOT EXISTS phone      TEXT,
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now();
