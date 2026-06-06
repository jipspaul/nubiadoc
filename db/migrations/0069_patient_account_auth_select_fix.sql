-- 0065_patient_account_auth_select_fix.sql
-- Corrige la policy account_auth_select (migration 0062) qui réutilisait
-- app.current_user_id — le même GUC que la policy d'isolation app_user.
-- Ce croisement faisait que tout contexte portant app.current_user_id
-- (y compris hors login) pouvait lire n'importe quel patient_account lié
-- au user, rompant le fail-closed attendu par les tests 03_rls et 12_auth_rls.
--
-- Correctif : GUC dédié app.current_login_user_id, positionné UNIQUEMENT
-- dans la transaction de login (durée de vie = transaction), puis jamais
-- autrement. Le handler login.rs est mis à jour en conséquence.
-- Issue : #795

DROP POLICY IF EXISTS account_auth_select ON patient_account;

CREATE POLICY account_auth_select ON patient_account
  FOR SELECT
  TO nubia_app
  USING (
    app_user_id = nullif(current_setting('app.current_login_user_id', true), '')::uuid
  );
