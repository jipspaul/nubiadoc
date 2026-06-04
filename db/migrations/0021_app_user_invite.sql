-- 0021_app_user_invite.sql
-- Prend en charge les comptes collaborateurs invités (sans mot de passe à la création)
-- et les colonnes d'identité first_name / last_name sur app_user. Issue : #224.

-- Les utilisateurs invités (non encore connectés) n'ont pas de mot de passe.
-- On lève la contrainte NOT NULL posée en 0014 pour permettre password_hash = NULL.
ALTER TABLE app_user ALTER COLUMN password_hash DROP NOT NULL;

-- Identité civile (prénom / nom). NULL = non renseigné (comptes existants).
ALTER TABLE app_user
  ADD COLUMN IF NOT EXISTS first_name TEXT,
  ADD COLUMN IF NOT EXISTS last_name  TEXT;
