-- 0063_patient_account_guardian_update.sql
-- Permet au tuteur de modifier les données patient_account de ses proches actifs.
-- Contexte : PATCH /v1/account/dependents/{id} fait UPDATE patient_account WHERE id = $4,
-- mais la policy account_self_update bloque car app.current_account_id = guardian_account_id.
-- Cette policy permissive ajoute le cas tuteur → proche actif. Issue #795.

CREATE POLICY account_guardian_update ON patient_account
  FOR UPDATE
  TO nubia_app
  USING (
    id IN (
      SELECT dependent_account_id
      FROM account_guardianship
      WHERE guardian_account_id = nullif(current_setting('app.current_account_id', true), '')::uuid
        AND active = true
    )
  )
  WITH CHECK (
    id IN (
      SELECT dependent_account_id
      FROM account_guardianship
      WHERE guardian_account_id = nullif(current_setting('app.current_account_id', true), '')::uuid
        AND active = true
    )
  );
