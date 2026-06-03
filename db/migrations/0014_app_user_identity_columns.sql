-- 0014_app_user_identity_columns.sql
-- Étend app_user avec les colonnes d'identité/auth : kind, TOTP, reset de mot de passe.
-- Rend password_hash NOT NULL (auth locale obligatoire).
-- Issue : #177

-- kind : type de compte (patient|pro). Ajout en deux étapes pour compatibilité
-- avec les éventuelles lignes existantes (backfill 'pro', puis NOT NULL).
ALTER TABLE app_user ADD COLUMN kind TEXT CHECK (kind IN ('patient', 'pro'));
UPDATE app_user SET kind = 'pro' WHERE kind IS NULL;
ALTER TABLE app_user ALTER COLUMN kind SET NOT NULL;

-- Champs TOTP (Time-based One-Time Password, 2FA)
ALTER TABLE app_user
  ADD COLUMN totp_secret              TEXT,
  ADD COLUMN totp_enabled             BOOL NOT NULL DEFAULT false;

-- Reset de mot de passe (token à usage unique + expiration)
ALTER TABLE app_user
  ADD COLUMN password_reset_token      TEXT,
  ADD COLUMN password_reset_expires_at TIMESTAMPTZ;

-- password_hash devient obligatoire. Backfill des lignes NULL existantes
-- (dev/seed pre-migration) avec un placeholder avant d'ajouter la contrainte.
UPDATE app_user SET password_hash = 'MIGRATION_PLACEHOLDER' WHERE password_hash IS NULL;
ALTER TABLE app_user ALTER COLUMN password_hash SET NOT NULL;

COMMENT ON COLUMN app_user.kind IS 'Type de compte : patient (portail patient) ou pro (cabinet dentaire).';
