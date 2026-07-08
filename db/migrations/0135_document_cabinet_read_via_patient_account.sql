-- 0135_document_cabinet_read_via_patient_account.sql
-- Symétrique de document_patient_read (migration 0034) mais dans l'autre sens :
-- un document coffre-fort uploadé par le patient (cabinet_id/patient_id NULL,
-- migration 0026 : "documents plateforme n'appartiennent pas à un cabinet")
-- n'était visible par AUCUN cabinet. tenant_isolation (0011) exige
-- cabinet_id = current_cabinet_id, jamais vrai pour ces lignes.
-- Permissive (OR avec tenant_isolation) : autorise le cabinet à lire un
-- document plateforme dès lors que le patient_account_id correspond à un de
-- ses patients.
-- Issue : #3497

CREATE POLICY document_cabinet_read_via_patient_account ON document
  FOR SELECT
  TO nubia_app
  USING (
    cabinet_id IS NULL
    AND patient_account_id IN (
      SELECT patient_account_id FROM patient
      WHERE cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid
        AND patient_account_id IS NOT NULL
        AND deleted_at IS NULL
    )
  );
