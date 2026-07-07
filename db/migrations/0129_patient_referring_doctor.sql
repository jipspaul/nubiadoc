-- 0129_patient_referring_doctor.sql
-- Médecin traitant déclaré par le patient (JEL-15) : soit une référence vers un
-- praticien listé dans l'annuaire (`provider`), soit une saisie libre (nom +
-- coordonnées) quand le médecin est hors base Nubia. Entité PLATEFORME (comme
-- patient_coverage, 0023) : RLS patient-scoped par `app.patient_account_id`.
-- Issue : #3451

CREATE TABLE patient_referring_doctor (
  id                 uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_account_id uuid        NOT NULL UNIQUE REFERENCES patient_account(id),
  provider_id        uuid        REFERENCES provider(id),
  free_name          text,
  free_phone         text,
  free_address       text,
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now(),
  -- Soit une référence praticien existant, soit une saisie libre (nom obligatoire) — jamais les deux.
  CONSTRAINT patient_referring_doctor_ref_xor_free CHECK (
    (provider_id IS NOT NULL) <> (free_name IS NOT NULL)
  )
);

-- RLS patient-scoped : fail-closed (GUC absent → 0 ligne), même pattern que patient_coverage.
ALTER TABLE patient_referring_doctor ENABLE ROW LEVEL SECURITY;
ALTER TABLE patient_referring_doctor FORCE ROW LEVEL SECURITY;
CREATE POLICY patient_referring_doctor_owner
  ON patient_referring_doctor
  FOR ALL
  TO nubia_app
  USING      (patient_account_id = nullif(current_setting('app.patient_account_id', true), '')::uuid)
  WITH CHECK (patient_account_id = nullif(current_setting('app.patient_account_id', true), '')::uuid);

GRANT SELECT, INSERT, UPDATE, DELETE ON patient_referring_doctor TO nubia_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON patient_referring_doctor TO nubia_seed;
