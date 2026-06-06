-- 0060_patient_account_auth_select.sql
-- Policy RLS LOGIN : patient_account accessible en lecture par app_user_id
-- quand app.current_user_id est positionné (login patient).
-- Permet au handler POST /v1/auth/login de récupérer l'account_id du patient
-- sans connaître app.current_account_id à l'avance.
-- Issue : #795

CREATE POLICY account_auth_select ON patient_account
  FOR SELECT
  TO nubia_app
  USING (
    app_user_id = nullif(current_setting('app.current_user_id', true), '')::uuid
  );
