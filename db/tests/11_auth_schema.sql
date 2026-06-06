-- 11_auth_schema.sql — auth/account : colonnes, types, NOT NULL et défauts non encore couverts.
-- Complète 00_schema.sql sur les tables auth platform (app_user, patient_account,
-- consent_record, refresh_token, notification_preference, mfa_enrollment).
-- Aucune fixture requise : introspection catalogue seule.
-- pgTAP, exécuté par pg_prove sous nubia_app.
BEGIN;
SELECT * FROM no_plan();

-- ===========================================================================
-- app_user
-- ===========================================================================

-- kind : type text (NOT NULL déjà dans 00_schema)
SELECT col_type_is('app_user', 'kind', 'text', 'app_user.kind text');
SELECT ok(
  EXISTS(SELECT 1 FROM pg_constraint
         WHERE conname = 'app_user_kind_check' AND conrelid = 'app_user'::regclass),
  'app_user : CHECK kind IN (patient, pro) présent (0014)');

-- status : NOT NULL, défaut ''active'', CHECK (active|suspended|disabled)
SELECT has_column('app_user', 'status', 'app_user.status présent');
SELECT col_not_null('app_user', 'status', 'app_user.status NOT NULL');
SELECT is(
  (SELECT pg_get_expr(d.adbin, d.adrelid)
   FROM pg_attrdef d JOIN pg_attribute a ON a.attrelid=d.adrelid AND a.attnum=d.adnum
   WHERE d.adrelid='app_user'::regclass AND a.attname='status'),
  '''active''::text', 'app_user.status défaut ''active''');
SELECT ok(
  EXISTS(SELECT 1 FROM pg_constraint
         WHERE conname = 'app_user_status_check' AND conrelid = 'app_user'::regclass),
  'app_user : CHECK status IN (active, suspended, disabled) présent');

-- totp_enabled : défaut false (présence/NOT NULL dans 00_schema)
SELECT is(
  (SELECT pg_get_expr(d.adbin, d.adrelid)
   FROM pg_attrdef d JOIN pg_attribute a ON a.attrelid=d.adrelid AND a.attnum=d.adnum
   WHERE d.adrelid='app_user'::regclass AND a.attname='totp_enabled'),
  'false', 'app_user.totp_enabled défaut false (0014)');

-- password_reset_token : nullable text
SELECT col_type_is('app_user', 'password_reset_token', 'text',
  'app_user.password_reset_token text');
SELECT col_is_null('app_user', 'password_reset_token',
  'app_user.password_reset_token nullable (usage unique, effacé après reset)');

-- password_reset_expires_at : nullable timestamptz
SELECT col_type_is('app_user', 'password_reset_expires_at', 'timestamp with time zone',
  'app_user.password_reset_expires_at timestamptz');
SELECT col_is_null('app_user', 'password_reset_expires_at',
  'app_user.password_reset_expires_at nullable');

-- password_hash : nullable depuis 0021 (comptes invités sans auth locale)
SELECT col_is_null('app_user', 'password_hash',
  'app_user.password_hash nullable (0021 — comptes invités)');

-- ===========================================================================
-- patient_account
-- ===========================================================================

-- updated_at : NOT NULL, défaut now()
SELECT has_column('patient_account', 'updated_at', 'patient_account.updated_at présent (0015)');
SELECT col_type_is('patient_account', 'updated_at', 'timestamp with time zone',
  'patient_account.updated_at timestamptz');
SELECT col_not_null('patient_account', 'updated_at', 'patient_account.updated_at NOT NULL');
SELECT col_has_default('patient_account', 'updated_at', 'patient_account.updated_at défaut now()');

-- phone : nullable text (ajouté 0015)
SELECT has_column('patient_account', 'phone', 'patient_account.phone présent (0015)');
SELECT col_type_is('patient_account', 'phone', 'text', 'patient_account.phone text');
SELECT col_is_null('patient_account', 'phone', 'patient_account.phone nullable');

-- tiers_payant : NOT NULL boolean, défaut false
SELECT col_type_is('patient_account', 'tiers_payant', 'boolean',
  'patient_account.tiers_payant boolean');
SELECT col_not_null('patient_account', 'tiers_payant', 'patient_account.tiers_payant NOT NULL');
SELECT is(
  (SELECT pg_get_expr(d.adbin, d.adrelid)
   FROM pg_attrdef d JOIN pg_attribute a ON a.attrelid=d.adrelid AND a.attnum=d.adnum
   WHERE d.adrelid='patient_account'::regclass AND a.attname='tiers_payant'),
  'false', 'patient_account.tiers_payant défaut false');

-- contact : JSONB NOT NULL
SELECT has_column('patient_account', 'contact', 'patient_account.contact présent (coordonnées)');
SELECT col_type_is('patient_account', 'contact', 'jsonb', 'patient_account.contact jsonb');
SELECT col_not_null('patient_account', 'contact', 'patient_account.contact NOT NULL');

-- Contraintes de paire crypto (0044) : ciphertext ↔ key_ref obligatoirement ensemble
SELECT ok(
  EXISTS(SELECT 1 FROM pg_constraint WHERE conname = 'patient_account_fn_crypto_pair'),
  'patient_account : contrainte fn_crypto_pair présente (0044 — first_name)');
SELECT ok(
  EXISTS(SELECT 1 FROM pg_constraint WHERE conname = 'patient_account_ln_crypto_pair'),
  'patient_account : contrainte ln_crypto_pair présente (0044 — last_name)');
SELECT ok(
  EXISTS(SELECT 1 FROM pg_constraint WHERE conname = 'patient_account_nss_crypto_pair'),
  'patient_account : contrainte nss_crypto_pair présente (NSS)');

-- ===========================================================================
-- consent_record
-- ===========================================================================

-- granted_at : nullable timestamptz avec défaut now() (refactorisé en nullable en 0017)
SELECT col_type_is('consent_record', 'granted_at', 'timestamp with time zone',
  'consent_record.granted_at timestamptz');
SELECT col_is_null('consent_record', 'granted_at',
  'consent_record.granted_at nullable (0017 — date optionnelle à l''INSERT)');

-- revoked_at : nullable timestamptz (NOT NULL = révoqué)
SELECT has_column('consent_record', 'revoked_at', 'consent_record.revoked_at présent');
SELECT col_type_is('consent_record', 'revoked_at', 'timestamp with time zone',
  'consent_record.revoked_at timestamptz');
SELECT col_is_null('consent_record', 'revoked_at',
  'consent_record.revoked_at nullable (NULL=actif, NOT NULL=révoqué)');

-- cgu_version : nullable text (version des CGU acceptées)
SELECT has_column('consent_record', 'cgu_version', 'consent_record.cgu_version présent (0017)');
SELECT col_type_is('consent_record', 'cgu_version', 'text', 'consent_record.cgu_version text');
SELECT col_is_null('consent_record', 'cgu_version', 'consent_record.cgu_version nullable');

-- app_user_id : nullable depuis 0050 (consentements RGPD patient n''ont pas forcément d''app_user_id direct)
SELECT col_is_null('consent_record', 'app_user_id',
  'consent_record.app_user_id nullable (0050 — consentements RGPD via patient_account uniquement)');

-- created_at : NOT NULL, défaut now()
SELECT col_type_is('consent_record', 'created_at', 'timestamp with time zone',
  'consent_record.created_at timestamptz');
SELECT col_not_null('consent_record', 'created_at', 'consent_record.created_at NOT NULL');
SELECT col_has_default('consent_record', 'created_at', 'consent_record.created_at défaut now()');

-- evidence : JSONB NOT NULL (historique de preuve RGPD, défaut '{}')
SELECT col_type_is('consent_record', 'evidence', 'jsonb', 'consent_record.evidence jsonb');
SELECT col_not_null('consent_record', 'evidence', 'consent_record.evidence NOT NULL (RGPD)');

-- ===========================================================================
-- refresh_token
-- ===========================================================================

-- revoked_at : nullable (soft-revoke : NULL=valide, NOT NULL=révoqué)
SELECT has_column('refresh_token', 'revoked_at', 'refresh_token.revoked_at présent (soft-revoke)');
SELECT col_type_is('refresh_token', 'revoked_at', 'timestamp with time zone',
  'refresh_token.revoked_at timestamptz');
SELECT col_is_null('refresh_token', 'revoked_at',
  'refresh_token.revoked_at nullable (NULL=valide, NOT NULL=révoqué)');

-- created_at : NOT NULL, défaut now()
SELECT has_column('refresh_token', 'created_at', 'refresh_token.created_at présent');
SELECT col_type_is('refresh_token', 'created_at', 'timestamp with time zone',
  'refresh_token.created_at timestamptz');
SELECT col_not_null('refresh_token', 'created_at', 'refresh_token.created_at NOT NULL');
SELECT col_has_default('refresh_token', 'created_at', 'refresh_token.created_at défaut now()');

-- ===========================================================================
-- notification_preference
-- ===========================================================================

-- enabled : NOT NULL boolean (colonne EAV 0049)
SELECT col_not_null('notification_preference', 'enabled',
  'notification_preference.enabled NOT NULL (EAV 0049)');
SELECT col_type_is('notification_preference', 'enabled', 'boolean',
  'notification_preference.enabled boolean');

-- channel et type : text (nullable — lignes legacy schéma plat peuvent avoir NULL)
SELECT col_type_is('notification_preference', 'channel', 'text',
  'notification_preference.channel text');
SELECT col_type_is('notification_preference', 'type', 'text',
  'notification_preference.type text');

-- ===========================================================================
-- mfa_enrollment
-- ===========================================================================

-- verified : NOT NULL, défaut false
SELECT is(
  (SELECT pg_get_expr(d.adbin, d.adrelid)
   FROM pg_attrdef d JOIN pg_attribute a ON a.attrelid=d.adrelid AND a.attnum=d.adnum
   WHERE d.adrelid='mfa_enrollment'::regclass AND a.attname='verified'),
  'false', 'mfa_enrollment.verified défaut false (0046)');

-- method : NOT NULL text, défaut ''totp''
SELECT col_type_is('mfa_enrollment', 'method', 'text', 'mfa_enrollment.method text');
SELECT is(
  (SELECT pg_get_expr(d.adbin, d.adrelid)
   FROM pg_attrdef d JOIN pg_attribute a ON a.attrelid=d.adrelid AND a.attnum=d.adnum
   WHERE d.adrelid='mfa_enrollment'::regclass AND a.attname='method'),
  '''totp''::text', 'mfa_enrollment.method défaut ''totp'' (seule méthode v1)');

-- enrolled_at : NOT NULL, timestamptz
SELECT col_type_is('mfa_enrollment', 'enrolled_at', 'timestamp with time zone',
  'mfa_enrollment.enrolled_at timestamptz');
SELECT col_not_null('mfa_enrollment', 'enrolled_at', 'mfa_enrollment.enrolled_at NOT NULL');

-- CHECK method = totp (seule méthode autorisée en v1)
SELECT ok(
  EXISTS(SELECT 1 FROM pg_constraint
         WHERE conname = 'mfa_enrollment_method_check' AND conrelid = 'mfa_enrollment'::regclass),
  'mfa_enrollment : CHECK method = totp présent (0046)');

SELECT * FROM finish();
ROLLBACK;
