-- 0029_dashboard_patient_read_policies.sql
-- Policies RLS READ-ONLY pour GET /v1/dashboard (app.patient_account_id GUC).
-- Permissives (OR avec tenant_isolation cabinet) : le cabinet conserve son accès.
-- Chaîne : message → conversation → patient ; appointment/quote/payment → patient.
-- Issue : #327

-- patient : lecture directe via patient_account_id (aucune jointure).
CREATE POLICY patient_account_read ON patient
  FOR SELECT
  TO nubia_app
  USING (
    patient_account_id = nullif(current_setting('app.patient_account_id', true), '')::uuid
  );

-- appointment : via patient.patient_account_id.
CREATE POLICY appointment_patient_read ON appointment
  FOR SELECT
  TO nubia_app
  USING (
    patient_id IN (
      SELECT id FROM patient
      WHERE patient_account_id = nullif(current_setting('app.patient_account_id', true), '')::uuid
    )
  );

-- quote : via patient.patient_account_id.
CREATE POLICY quote_patient_read ON quote
  FOR SELECT
  TO nubia_app
  USING (
    patient_id IN (
      SELECT id FROM patient
      WHERE patient_account_id = nullif(current_setting('app.patient_account_id', true), '')::uuid
    )
  );

-- payment : via patient.patient_account_id.
CREATE POLICY payment_patient_read ON payment
  FOR SELECT
  TO nubia_app
  USING (
    patient_id IN (
      SELECT id FROM patient
      WHERE patient_account_id = nullif(current_setting('app.patient_account_id', true), '')::uuid
    )
  );

-- conversation : via patient.patient_account_id.
CREATE POLICY conversation_patient_read ON conversation
  FOR SELECT
  TO nubia_app
  USING (
    patient_id IN (
      SELECT id FROM patient
      WHERE patient_account_id = nullif(current_setting('app.patient_account_id', true), '')::uuid
    )
  );

-- message : via conversation → patient.patient_account_id.
CREATE POLICY message_patient_read ON message
  FOR SELECT
  TO nubia_app
  USING (
    conversation_id IN (
      SELECT id FROM conversation
      WHERE patient_id IN (
        SELECT id FROM patient
        WHERE patient_account_id = nullif(current_setting('app.patient_account_id', true), '')::uuid
      )
    )
  );
