-- 0023_create_patient_coverage.sql
-- Couverture santé patient : table dédiée (entité plateforme, liée à patient_account).
-- nss_encrypted = BYTEA — chiffrement applicatif AES-256-GCM, jamais de n° sécu en clair.
-- RLS patient-scoped (app.patient_account_id) : seul le titulaire peut lire/écrire sa ligne.
-- Issue : #237

CREATE TABLE patient_coverage (
  id                 uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_account_id uuid        NOT NULL REFERENCES patient_account(id),
  regime_obligatoire text        CHECK (regime_obligatoire IN ('regime_general','ame','css')),
  nss_encrypted      bytea,                        -- n° sécu (PII critique, chiffré applicatif)
  amc                text,                          -- organisme complémentaire (mutuelle)
  numero_adherent    text,
  plateforme         text,
  tiers_payant       boolean     NOT NULL DEFAULT false,
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now()
);

-- RLS patient-scoped : fail-closed (GUC absent → 0 ligne).
ALTER TABLE patient_coverage ENABLE ROW LEVEL SECURITY;
ALTER TABLE patient_coverage FORCE ROW LEVEL SECURITY;
CREATE POLICY patient_coverage_owner
  ON patient_coverage
  FOR ALL
  TO nubia_app
  USING      (patient_account_id = nullif(current_setting('app.patient_account_id', true), '')::uuid)
  WITH CHECK (patient_account_id = nullif(current_setting('app.patient_account_id', true), '')::uuid);

GRANT SELECT, INSERT, UPDATE, DELETE ON patient_coverage TO nubia_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON patient_coverage TO nubia_seed;
