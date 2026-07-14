-- 0146_waiting_list_entry_patient_cancel.sql
-- Policy RLS READ pour permettre au patient de retrouver SA propre entrée de
-- liste d'attente par id (POST /v1/waiting-list/:id/cancel), sans connaître le
-- cabinet_id à l'avance (contrairement à POST /v1/waiting-list qui le résout
-- depuis provider_id). Même pattern que appointment_patient_read (0029).
-- Permissive (OR avec tenant_isolation) : le cabinet conserve son accès.
-- Issue : #3737

CREATE POLICY waiting_list_entry_patient_read ON waiting_list_entry
  FOR SELECT
  TO nubia_app
  USING (
    patient_id IN (
      SELECT id FROM patient
      WHERE patient_account_id = nullif(current_setting('app.patient_account_id', true), '')::uuid
    )
  );
