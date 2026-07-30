-- 0204_payment_schedule_patient_read.sql
-- payment_schedule (migration 0006) n'a que la policy tenant_isolation
-- générique (scope app.current_cabinet_id, migration 0011) — aucune policy
-- permissive ne permet au patient lui-même de lire ses échéanciers
-- (#4072 : GET /v1/payment-schedules côté patient). Même schéma que
-- prescription_patient_read/implant_passport_patient_read : permissive
-- (ajout), le cabinet conserve son accès via tenant_isolation.

CREATE POLICY payment_schedule_patient_read ON payment_schedule
  FOR SELECT
  TO nubia_app
  USING (
    patient_id IN (
      SELECT id FROM patient
      WHERE patient_account_id = nullif(current_setting('app.patient_account_id', true), '')::uuid
    )
  );
