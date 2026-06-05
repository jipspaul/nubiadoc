-- 0038_treatment_plan_patient_read_policy.sql
-- Policy de lecture patient sur treatment_plan via app.patient_account_id GUC.
-- Symétrique avec document_patient_read (0034) et appointment_patient_read (0029).
-- Permissive (ajout) : le cabinet conserve son accès via tenant_isolation (0011).
-- Issue : #515

CREATE POLICY treatment_plan_patient_read ON treatment_plan
  FOR SELECT
  TO nubia_app
  USING (
    patient_id IN (
      SELECT id FROM patient
      WHERE patient_account_id = nullif(current_setting('app.patient_account_id', true), '')::uuid
    )
  );
