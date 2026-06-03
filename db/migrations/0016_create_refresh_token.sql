-- 0016_create_refresh_token.sql
-- Sessions : refresh tokens rotatifs pour /auth/refresh et /auth/logout.
-- Entité plateforme (liée à app_user, pas à cabinet) — pas de RLS cabinet.
-- Issue : #179

CREATE TABLE refresh_token (
  id           uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  app_user_id  uuid        NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  token_hash   text        UNIQUE NOT NULL,   -- SHA-256 du token brut (jamais le brut)
  expires_at   timestamptz NOT NULL,
  revoked_at   timestamptz,                   -- NOT NULL = token invalide (soft-revoke)
  created_at   timestamptz NOT NULL DEFAULT now()
);

-- Accélère la révocation par utilisateur (logout all devices).
CREATE INDEX idx_refresh_token_app_user_id ON refresh_token (app_user_id);

GRANT SELECT, INSERT, UPDATE ON refresh_token TO nubia_app;

COMMENT ON TABLE refresh_token IS 'Refresh tokens rotatifs (sessions). token_hash = SHA-256 ; revoked_at IS NOT NULL = révoqué.';
