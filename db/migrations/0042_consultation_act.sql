-- 0042_consultation_act.sql
-- Actes CCAM réalisés pendant une séance au fauteuil + colonnes de completion appointment.
-- Issue : #655

-- 1. Colonnes de completion sur appointment (horodatage début/fin de séance)
ALTER TABLE appointment
  ADD COLUMN started_at   timestamptz,
  ADD COLUMN completed_at timestamptz;

-- 2. Table des actes CCAM (liée à appointment + cabinet pour la RLS)
CREATE TABLE consultation_act (
  id              uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  cabinet_id      uuid        NOT NULL REFERENCES cabinet(id),
  appointment_id  uuid        NOT NULL REFERENCES appointment(id),
  patient_id      uuid        NOT NULL REFERENCES patient(id),
  practitioner_id uuid        NOT NULL REFERENCES practitioner(id),
  ccam_code       text        NOT NULL,
  label           text        NOT NULL,
  tooth           text,                     -- dent concernée, numérotation FDI (optionnel)
  amount_cents    integer     NOT NULL,     -- montant en centimes (non PII)
  created_at      timestamptz NOT NULL DEFAULT now()
);

-- 3. RLS sur consultation_act : tenant + praticien, fail-closed pour le secrétariat
--    La policy combine cabinet_id ET practitioner_id → sans current_practitioner_id, 0 lignes.
ALTER TABLE consultation_act ENABLE ROW LEVEL SECURITY;
ALTER TABLE consultation_act FORCE ROW LEVEL SECURITY;

CREATE POLICY consultation_act_tenant_isolation
  ON consultation_act
  FOR ALL
  TO nubia_app
  USING (
    cabinet_id      = nullif(current_setting('app.current_cabinet_id',      true), '')::uuid
    AND practitioner_id = nullif(current_setting('app.current_practitioner_id', true), '')::uuid
  )
  WITH CHECK (
    cabinet_id      = nullif(current_setting('app.current_cabinet_id',      true), '')::uuid
    AND practitioner_id = nullif(current_setting('app.current_practitioner_id', true), '')::uuid
  );

-- 4. Policy appointment_completion : accès praticien-scoped à l'appointment pour
--    les handlers POST .../start et POST .../complete (permissive, OR avec tenant_isolation)
CREATE POLICY appointment_completion
  ON appointment
  FOR ALL
  TO nubia_app
  USING (
    cabinet_id      = nullif(current_setting('app.current_cabinet_id',      true), '')::uuid
    AND practitioner_id = nullif(current_setting('app.current_practitioner_id', true), '')::uuid
  )
  WITH CHECK (
    cabinet_id      = nullif(current_setting('app.current_cabinet_id',      true), '')::uuid
    AND practitioner_id = nullif(current_setting('app.current_practitioner_id', true), '')::uuid
  );

-- 5. Grants
GRANT SELECT, INSERT, UPDATE, DELETE ON consultation_act TO nubia_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON consultation_act TO nubia_seed;
