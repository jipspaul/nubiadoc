-- 11_auth_schema.sql — Contrat structurel des tables auth/account (issue #732).
-- Vérifie colonnes, types, contraintes NOT NULL et valeurs par défaut non couvertes par 00_schema.sql.
-- Tourne sous nubia_app (NOSUPERUSER, NOBYPASSRLS). Aucun INSERT n'est requis : tests catalogue.
BEGIN;
SELECT * FROM no_plan();

-- ===========================================================================
-- app_user : types, defaults, nullable (0002 + 0014 + 0021)
-- ===========================================================================
SELECT col_type_is('app_user', 'id', 'uuid',
  'app_user.id uuid');
SELECT col_has_default('app_user', 'id',
  'app_user.id DEFAULT gen_random_uuid()');
SELECT col_type_is('app_user', 'created_at', 'timestamp with time zone',
  'app_user.created_at timestamptz');
SELECT col_not_null('app_user', 'created_at',
  'app_user.created_at NOT NULL');
SELECT col_has_default('app_user', 'created_at',
  'app_user.created_at DEFAULT now()');

-- status : NOT NULL + CHECK + défaut 'active' (0002)
SELECT has_column('app_user', 'status',
  'app_user.status présent');
SELECT col_not_null('app_user', 'status',
  'app_user.status NOT NULL');
SELECT col_has_default('app_user', 'status',
  'app_user.status DEFAULT active');

-- totp_enabled : DEFAULT false (0014)
SELECT col_has_default('app_user', 'totp_enabled',
  'app_user.totp_enabled DEFAULT false');

-- password_hash : nullable depuis 0021 (comptes invités)
SELECT col_is_null('app_user', 'password_hash',
  'app_user.password_hash nullable (comptes invités, 0021)');

-- soft-delete
SELECT has_column('app_user', 'deleted_at',
  'app_user.deleted_at présent (soft-delete)');
SELECT col_is_null('app_user', 'deleted_at',
  'app_user.deleted_at nullable');

-- ===========================================================================
-- patient_account : types, defaults, nullable (0009 + 0015)
-- ===========================================================================
SELECT col_type_is('patient_account', 'id', 'uuid',
  'patient_account.id uuid');
SELECT col_has_default('patient_account', 'id',
  'patient_account.id DEFAULT gen_random_uuid()');

-- updated_at ajouté en 0015
SELECT has_column('patient_account', 'updated_at',
  'patient_account.updated_at présent (0015)');
SELECT col_type_is('patient_account', 'updated_at', 'timestamp with time zone',
  'patient_account.updated_at timestamptz');
SELECT col_not_null('patient_account', 'updated_at',
  'patient_account.updated_at NOT NULL');
SELECT col_has_default('patient_account', 'updated_at',
  'patient_account.updated_at DEFAULT now()');

-- phone ajouté en 0015
SELECT has_column('patient_account', 'phone',
  'patient_account.phone présent (0015)');
SELECT col_is_null('patient_account', 'phone',
  'patient_account.phone nullable');

-- ===========================================================================
-- refresh_token : types, defaults, nullable (0016)
-- ===========================================================================
SELECT col_type_is('refresh_token', 'id', 'uuid',
  'refresh_token.id uuid');
SELECT col_has_default('refresh_token', 'id',
  'refresh_token.id DEFAULT gen_random_uuid()');
SELECT col_type_is('refresh_token', 'app_user_id', 'uuid',
  'refresh_token.app_user_id uuid');
SELECT col_type_is('refresh_token', 'token_hash', 'text',
  'refresh_token.token_hash text');
SELECT col_type_is('refresh_token', 'expires_at', 'timestamp with time zone',
  'refresh_token.expires_at timestamptz');

-- revoked_at : NOT NULL = révoqué (soft-revoke)
SELECT has_column('refresh_token', 'revoked_at',
  'refresh_token.revoked_at présent (soft-revoke)');
SELECT col_is_null('refresh_token', 'revoked_at',
  'refresh_token.revoked_at nullable (token valide si NULL)');

SELECT has_column('refresh_token', 'created_at',
  'refresh_token.created_at présent');
SELECT col_type_is('refresh_token', 'created_at', 'timestamp with time zone',
  'refresh_token.created_at timestamptz');
SELECT col_has_default('refresh_token', 'created_at',
  'refresh_token.created_at DEFAULT now()');

-- ===========================================================================
-- mfa_enrollment : types, defaults (0046)
-- ===========================================================================
SELECT has_column('mfa_enrollment', 'secret_key_ref',
  'mfa_enrollment.secret_key_ref présent (référence clé KMS)');
SELECT col_not_null('mfa_enrollment', 'secret_key_ref',
  'mfa_enrollment.secret_key_ref NOT NULL');

SELECT col_type_is('mfa_enrollment', 'method', 'text',
  'mfa_enrollment.method text');
SELECT col_has_default('mfa_enrollment', 'method',
  'mfa_enrollment.method DEFAULT totp');

SELECT col_type_is('mfa_enrollment', 'verified', 'boolean',
  'mfa_enrollment.verified boolean');
SELECT col_has_default('mfa_enrollment', 'verified',
  'mfa_enrollment.verified DEFAULT false');

SELECT col_type_is('mfa_enrollment', 'enrolled_at', 'timestamp with time zone',
  'mfa_enrollment.enrolled_at timestamptz');
SELECT col_has_default('mfa_enrollment', 'enrolled_at',
  'mfa_enrollment.enrolled_at DEFAULT now()');

-- ===========================================================================
-- consent_record : types, defaults, nullable (0008 + 0017 + 0048 + 0050)
-- ===========================================================================
SELECT col_type_is('consent_record', 'evidence', 'jsonb',
  'consent_record.evidence jsonb');
SELECT col_not_null('consent_record', 'evidence',
  'consent_record.evidence NOT NULL');
SELECT col_has_default('consent_record', 'evidence',
  'consent_record.evidence DEFAULT {}');

-- granted_at : nullable depuis 0017
SELECT has_column('consent_record', 'granted_at',
  'consent_record.granted_at présent');
SELECT col_type_is('consent_record', 'granted_at', 'timestamp with time zone',
  'consent_record.granted_at timestamptz');
SELECT col_is_null('consent_record', 'granted_at',
  'consent_record.granted_at nullable (0017)');

-- revoked_at : nullable (révocable)
SELECT has_column('consent_record', 'revoked_at',
  'consent_record.revoked_at présent (révocable)');
SELECT col_is_null('consent_record', 'revoked_at',
  'consent_record.revoked_at nullable');

-- app_user_id : nullable depuis 0050 (lignes RGPD patient_account sans app_user)
SELECT col_is_null('consent_record', 'app_user_id',
  'consent_record.app_user_id nullable (0050 — RGPD patient portal)');

-- ===========================================================================
-- notification_preference : defaults, nullable (0024 + 0049 — modèle EAV)
-- ===========================================================================
SELECT col_not_null('notification_preference', 'enabled',
  'notification_preference.enabled NOT NULL');
SELECT col_has_default('notification_preference', 'enabled',
  'notification_preference.enabled DEFAULT true');

-- channel et type : nullable (NULLs = lignes globales dans le modèle EAV)
SELECT col_is_null('notification_preference', 'channel',
  'notification_preference.channel nullable');
SELECT col_is_null('notification_preference', 'type',
  'notification_preference.type nullable');

SELECT * FROM finish();
ROLLBACK;
