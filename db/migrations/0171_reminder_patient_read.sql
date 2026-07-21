-- 0171_reminder_patient_read.sql
-- Lecture patient des rappels réels (#4077) : `reminder` n'avait qu'une
-- policy tenant_isolation (cabinet_id, migration 0085) — un token patient
-- (`GET /v1/reminders`, GUC app.patient_account_id, jamais
-- app.current_cabinet_id) ne pouvait lire AUCUNE ligne (fail-closed),
-- empêchant list_reminders de brancher ce endpoint sur la vraie table.
-- Même pattern que appointment_patient_read (migration 0029) : lecture
-- cross-cabinet via le lien patient.patient_account_id, policy permissive
-- (OR avec tenant_isolation) donc n'affaiblit rien côté cabinet.

CREATE POLICY reminder_patient_read ON reminder
  FOR SELECT
  TO nubia_app
  USING (
    patient_id IN (
      SELECT id FROM patient
      WHERE patient_account_id = nullif(current_setting('app.patient_account_id', true), '')::uuid
    )
  );

COMMENT ON POLICY reminder_patient_read ON reminder IS
    'Lecture patient cross-cabinet via patient.patient_account_id (comme '
    'appointment_patient_read, migration 0029). Issue #4077.';
