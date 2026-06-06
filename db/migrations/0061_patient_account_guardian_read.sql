-- 0061_patient_account_guardian_read.sql
-- Policy RLS : patient_account lisible par le tuteur légal (guardian).
-- Permet au tuteur (guardian_account_id = app.current_account_id) de voir
-- les comptes de ses dépendants.
-- Issue : #795

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
