-- 0077_implant_passport_patient_read_policy.sql
-- Policy de lecture patient sur implant_passport via app.patient_account_id GUC.
-- Symétrique avec treatment_plan_patient_read (0038) et document_patient_read (0034).
-- Permissive (ajout) : le cabinet conserve son accès via tenant_isolation (0073).
-- Issue : #704

CREATE POLICY implant_passport_patient_read ON implant_passport
  FOR SELECT
  TO nubia_app
  USING (
    patient_id IN (
      SELECT id FROM patient
      WHERE patient_account_id = nullif(current_setting('app.patient_account_id', true), '')::uuid
    )
  );
