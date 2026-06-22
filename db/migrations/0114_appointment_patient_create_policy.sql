-- 0114_appointment_patient_create_policy.sql
-- Policy RLS appointment_patient_create : un patient peut insérer un RDV pour
-- son propre dossier patient via le GUC app.patient_account_id.
-- Permissive, s'ajoute à tenant_isolation (0011). Utilisée par POST /v1/appointments
-- (handler Rust positionne SET LOCAL app.patient_account_id).
-- Issue : #2497

CREATE POLICY appointment_patient_create ON appointment
  FOR INSERT
  TO nubia_app
  WITH CHECK (
    patient_id IN (
      SELECT id FROM patient
      WHERE patient_account_id = nullif(current_setting('app.patient_account_id', true), '')::uuid
    )
  );
