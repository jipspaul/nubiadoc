-- 0034_document_patient_read_policy.sql
-- Policy de lecture patient sur document (coffre-fort) via app.patient_account_id GUC.
-- Symétrique avec les policies de 0029 (appointment_patient_read, quote_patient_read…).
-- Permissive (ajout) : le cabinet conserve son accès via tenant_isolation (0011).
-- Issue : #445

CREATE POLICY document_patient_read ON document
  FOR SELECT
  TO nubia_app
  USING (
    patient_id IN (
      SELECT id FROM patient
      WHERE patient_account_id = nullif(current_setting('app.patient_account_id', true), '')::uuid
    )
  );
