-- 0058_patient_account_guardian_read.sql
-- Permet au tuteur de lire les données patient_account de ses proches actifs.
-- Contexte : GET /v1/account/dependents et GET /v1/account/dependents/{id} joignent
-- patient_account depuis account_guardianship, mais patient_account a FORCE RLS
-- et seule la policy account_self_select existait (id = app.current_account_id).
-- Cette policy permissive ajoute le cas tuteur → proche actif. Issue #828.

CREATE POLICY account_guardian_read ON patient_account
  FOR SELECT
  TO nubia_app
  USING (
    id IN (
      SELECT dependent_account_id
      FROM account_guardianship
      WHERE guardian_account_id = nullif(current_setting('app.current_account_id', true), '')::uuid
        AND active = true
    )
  );
