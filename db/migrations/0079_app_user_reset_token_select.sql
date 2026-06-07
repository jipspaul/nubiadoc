-- 0079_app_user_reset_token_select.sql
-- Policy RLS SELECT sur app_user pour le flow reset de mot de passe.
-- Permet de retrouver un utilisateur par son password_reset_token hashé
-- sans connaître son id à l'avance (bootstrap identique au flow login).
-- L'application pose app.current_reset_token_hash avant le SELECT.
-- Issue : #766

CREATE POLICY user_reset_token_select ON app_user
  FOR SELECT
  TO nubia_app
  USING (
    password_reset_token = nullif(current_setting('app.current_reset_token_hash', true), '')
  );
