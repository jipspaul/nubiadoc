-- 0046_create_mfa_enrollment.sql
-- Table d'enrôlement MFA TOTP par utilisateur (pros et patients).
-- Entité plateforme (liée à app_user, pas à cabinet_id) — RLS user-scoped ajoutée en 0047.
-- Le secret TOTP est chiffré : secret_ciphertext (bytea) + secret_key_ref (référence clé KMS).
-- Issue : #719

CREATE TABLE mfa_enrollment (
    id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    app_user_id       UUID        NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
    secret_ciphertext BYTEA       NOT NULL,
    secret_key_ref    TEXT        NOT NULL,
    method            TEXT        NOT NULL DEFAULT 'totp'
                                  CHECK (method IN ('totp')),
    verified          BOOL        NOT NULL DEFAULT false,
    enrolled_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Accélère les lookups par utilisateur (MFA actif ? quel enrôlement ?)
CREATE INDEX idx_mfa_enrollment_app_user_id
    ON mfa_enrollment (app_user_id);

GRANT SELECT, INSERT, UPDATE, DELETE ON mfa_enrollment TO nubia_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON mfa_enrollment TO nubia_seed;

COMMENT ON TABLE mfa_enrollment IS 'Enrôlement MFA TOTP par utilisateur. secret_ciphertext = secret TOTP chiffré (core/crypto KMS).';
