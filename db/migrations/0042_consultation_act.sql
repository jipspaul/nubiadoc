-- 0042_consultation_act.sql
-- Actes CCAM réalisés pendant une séance au fauteuil (table consultation_act) +
-- horodatages de séance sur appointment (started_at, completed_at).
-- RLS : tenant_isolation fail-closed sur consultation_act ;
--       policy appointment_completion (complétion de séance) sur appointment.
-- Issue : #651

-- ---- appointment : horodatages de séance ----
ALTER TABLE appointment
  ADD COLUMN started_at   timestamptz,
  ADD COLUMN completed_at timestamptz;

-- ---- consultation_act : actes CCAM par séance ----
CREATE TABLE consultation_act (
  id               uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  cabinet_id       uuid        NOT NULL REFERENCES cabinet(id),
  appointment_id   uuid        NOT NULL REFERENCES appointment(id),
  patient_id       uuid        NOT NULL REFERENCES patient(id),
  practitioner_id  uuid        NOT NULL REFERENCES practitioner(id),
  ccam_code        text        NOT NULL,
  label            text        NOT NULL,
  tooth            text,
  amount_cents     integer     NOT NULL CHECK (amount_cents >= 0),
  created_at       timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_consultation_act_cabinet_appointment
  ON consultation_act (cabinet_id, appointment_id);

-- ---- RLS consultation_act ----
ALTER TABLE consultation_act ENABLE ROW LEVEL SECURITY;
ALTER TABLE consultation_act FORCE ROW LEVEL SECURITY;

CREATE POLICY consultation_act_tenant_isolation ON consultation_act
  FOR ALL
  USING  (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid)
  WITH CHECK (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid);

-- ---- RLS appointment : policy nommée pour le workflow de complétion ----
-- Complète la policy tenant_isolation posée en 0011 ; même condition, nom distinct
-- pour les handlers POST .../start et POST .../complete.
CREATE POLICY appointment_completion ON appointment
  FOR ALL
  USING  (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid)
  WITH CHECK (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid);

-- Grants
GRANT SELECT, INSERT, UPDATE, DELETE ON consultation_act TO nubia_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON consultation_act TO nubia_seed;
