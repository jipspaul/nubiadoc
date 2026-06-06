-- 0064_app_user_login_select.sql
-- Policy RLS LOGIN : app_user SELECT accessible par email au moment de l'authentification.
-- Résout le deadlock circulaire du flow login : on ne peut pas poser app.current_user_id
-- avant d'avoir retrouvé le user par email.
-- Modèle : handler pose app.current_login_email avant SELECT FROM app_user WHERE email = $1.
-- Limité à SELECT uniquement, couvrant un seul email à la fois.
-- Issue : #795

CREATE POLICY user_login_select ON app_user
  FOR SELECT
  TO nubia_app
  USING (
    email = nullif(current_setting('app.current_login_email', true), '')
  );
