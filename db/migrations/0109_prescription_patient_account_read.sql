-- 0109_prescription_patient_account_read.sql
-- Ajoute une policy patient_account_read sur prescription pour que la policy
-- prescription_line_patient_read (0108) puisse traverser le chemin transitif
-- prescription_item → prescription → patient → patient_account_id.
-- Sans cette policy, la table prescription n'est accessible que via
-- tenant_isolation (current_cabinet_id), bloquant l'accès patient sans
-- cabinet GUC.
-- Issue : #2448

CREATE POLICY prescription_patient_read ON prescription
  FOR SELECT
  TO nubia_app
  USING (
    patient_id IN (
      SELECT id FROM patient
      WHERE patient_account_id = nullif(current_setting('app.patient_account_id', true), '')::uuid
    )
  );
