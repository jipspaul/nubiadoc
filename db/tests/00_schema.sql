-- 00_schema.sql — Contrat structurel : tables, colonnes, types, défauts, clés.
-- pgTAP. Exécuté par pg_prove (sous nubia_app). Réf. docs/05.
BEGIN;
SELECT * FROM no_plan();

-- ----- Extensions requises (db/README §9, 0001) -----
SELECT ok( EXISTS(SELECT 1 FROM pg_extension WHERE extname='pgcrypto'),  'extension pgcrypto');
SELECT ok( EXISTS(SELECT 1 FROM pg_extension WHERE extname='citext'),    'extension citext');
SELECT ok( EXISTS(SELECT 1 FROM pg_extension WHERE extname='pg_trgm'),   'extension pg_trgm');
SELECT ok( EXISTS(SELECT 1 FROM pg_extension WHERE extname='postgis'),   'extension postgis');
SELECT ok( EXISTS(SELECT 1 FROM pg_extension WHERE extname='btree_gist'),'extension btree_gist (EXCLUDE appointment)');

-- ----- Existence des tables du modèle (docs/05 §5, §6, §9, §10) -----
SELECT has_table('cabinet');
SELECT has_table('app_user');
SELECT has_table('cabinet_membership');
-- cabinet_membership : colonnes clés (issue #207)
SELECT has_column('cabinet_membership', 'id',         'cabinet_membership.id présent');
SELECT has_column('cabinet_membership', 'cabinet_id', 'cabinet_membership.cabinet_id présent');
SELECT col_not_null('cabinet_membership', 'cabinet_id', 'cabinet_membership.cabinet_id NOT NULL (tenant)');
SELECT has_column('cabinet_membership', 'user_id',    'cabinet_membership.user_id présent');
SELECT col_not_null('cabinet_membership', 'user_id',   'cabinet_membership.user_id NOT NULL');
SELECT has_column('cabinet_membership', 'role',       'cabinet_membership.role présent');
SELECT has_column('cabinet_membership', 'active',     'cabinet_membership.active présent (0018)');
SELECT col_type_is('cabinet_membership', 'active', 'boolean', 'cabinet_membership.active boolean');
SELECT col_not_null('cabinet_membership', 'active',   'cabinet_membership.active NOT NULL');
SELECT col_has_default('cabinet_membership', 'active', 'cabinet_membership.active défaut true');
SELECT has_table('practitioner');
SELECT has_table('patient');
SELECT has_table('medical_record');
SELECT has_table('clinical_note');
SELECT has_table('dental_chart');
SELECT has_table('document');
SELECT has_table('appointment');
SELECT has_table('checkin_event');
SELECT has_table('waiting_list_entry');
SELECT has_table('quote');
SELECT has_table('quote_item');
SELECT has_table('signature');
SELECT has_table('payment_schedule');
SELECT has_table('payment');
SELECT has_table('conversation');
SELECT has_table('message');
SELECT has_table('audit_log');
SELECT has_table('consent_record');
SELECT has_table('patient_account');
SELECT has_table('account_guardianship');
SELECT has_table('profession');
SELECT has_table('specialty');
SELECT has_table('medical_act');
SELECT has_table('establishment');
SELECT has_table('provider');
SELECT has_table('availability_slot');
SELECT has_table('review');
SELECT has_table('treatment_plan');
SELECT has_table('treatment_phase');
SELECT has_table('prescription');
SELECT has_table('prescription_item');
SELECT has_table('provider_verification');
-- provider_verification : colonnes clés (issue #209)
SELECT col_default_is('provider_verification', 'status', 'pending', 'provider_verification.status défaut pending');
SELECT has_column('provider_verification', 'resolved_at', 'provider_verification.resolved_at présent (0020)');
SELECT has_table('assistant_query');

-- ----- Clés primaires -----
SELECT has_pk('cabinet');
SELECT has_pk('patient');
SELECT has_pk('appointment');
SELECT has_pk('quote');
SELECT has_pk('audit_log');     -- PK composite (id, occurred_at)

-- ----- Colonnes & types : tenant + horodatage (échantillon représentatif) -----

-- cabinet : colonnes clés (issue #206)
SELECT has_column('cabinet', 'id',             'cabinet.id présent');
SELECT col_type_is('cabinet', 'id', 'uuid',    'cabinet.id uuid');
SELECT has_column('cabinet', 'raison_sociale', 'cabinet.raison_sociale présent');
SELECT col_not_null('cabinet', 'raison_sociale', 'cabinet.raison_sociale NOT NULL');
SELECT has_column('cabinet', 'siret',          'cabinet.siret présent');
SELECT has_column('cabinet', 'specialite',     'cabinet.specialite présent');
SELECT col_not_null('cabinet', 'specialite',   'cabinet.specialite NOT NULL');
SELECT has_column('cabinet', 'created_at',     'cabinet.created_at présent');
SELECT col_type_is('cabinet', 'created_at', 'timestamp with time zone', 'cabinet.created_at timestamptz');

SELECT col_type_is('patient', 'id', 'uuid', 'patient.id uuid');
SELECT col_has_default('patient', 'id', 'patient.id a un défaut (gen_random_uuid)');
SELECT col_type_is('patient', 'cabinet_id', 'uuid', 'patient.cabinet_id uuid');
SELECT col_not_null('patient', 'cabinet_id', 'patient.cabinet_id NOT NULL (tenant)');
SELECT col_type_is('patient', 'created_at', 'timestamp with time zone', 'patient.created_at timestamptz');
SELECT col_type_is('patient', 'deleted_at', 'timestamp with time zone', 'patient.deleted_at timestamptz (soft-delete)');

-- email citext + unique (app_user)
SELECT col_type_is('app_user', 'email', 'citext', 'app_user.email citext');
-- colonnes d'identité/auth (0014, issue #177 ; 0021, issue #224)
SELECT col_is_unique('app_user', 'email', 'app_user.email UNIQUE');
SELECT has_column('app_user', 'password_hash', 'app_user.password_hash présent (nullable depuis 0021 — comptes invités)');
SELECT col_not_null('app_user', 'kind', 'app_user.kind NOT NULL');
SELECT has_column('app_user', 'totp_secret', 'app_user.totp_secret présent');
SELECT col_not_null('app_user', 'totp_enabled', 'app_user.totp_enabled NOT NULL');
SELECT has_column('app_user', 'password_reset_token', 'app_user.password_reset_token présent');
SELECT has_column('app_user', 'password_reset_expires_at', 'app_user.password_reset_expires_at présent');
SELECT has_column('app_user', 'first_name', 'app_user.first_name présent (0021, identité civile)');
SELECT has_column('app_user', 'last_name', 'app_user.last_name présent (0021, identité civile)');

-- chiffrement colonne : bytea + key_ref (jamais chiffré en SQL)
SELECT col_type_is('clinical_note', 'content_ciphertext', 'bytea', 'clinical_note chiffré en bytea');
SELECT col_not_null('clinical_note', 'content_ciphertext', 'clinical_note.content_ciphertext NOT NULL');
SELECT col_type_is('clinical_note', 'content_key_ref', 'text', 'clinical_note.content_key_ref text');
SELECT col_type_is('message', 'body_ciphertext', 'bytea', 'message body chiffré en bytea');
SELECT col_type_is('medical_record', 'data_ciphertext', 'bytea', 'medical_record chiffré en bytea');
SELECT col_type_is('patient_account', 'nss_ciphertext', 'bytea', 'patient_account n° sécu chiffré (0010)');

-- argent : numeric, pas de float
SELECT col_type_is('quote', 'total_amount', 'numeric(12,2)', 'quote.total_amount numeric(12,2)');
SELECT col_type_is('quote', 'currency', 'character(3)', 'quote.currency char(3)');
SELECT col_type_is('payment', 'amount', 'numeric(12,2)', 'payment.amount numeric(12,2)');

-- provider : colonnes et index (issue #208)
SELECT has_column('provider',  'cabinet_id',  'provider.cabinet_id présent');
SELECT col_not_null('provider', 'cabinet_id', 'provider.cabinet_id NOT NULL (tenant)');
SELECT has_column('provider',  'user_id',     'provider.user_id présent (0019)');
SELECT col_not_null('provider', 'user_id',    'provider.user_id NOT NULL (0019)');
SELECT has_column('provider',  'specialite',  'provider.specialite présent (0019)');
SELECT has_column('provider',  'created_at',  'provider.created_at présent (0019)');
SELECT col_type_is('provider', 'created_at', 'timestamp with time zone', 'provider.created_at timestamptz');
SELECT has_index('provider', 'provider_listed_rpps_verified_idx',
  ARRAY['is_listed', 'rpps_verified'],
  'provider : index (is_listed, rpps_verified) présent (0019)');

-- géo PostGIS
SELECT col_type_is('provider', 'geo', 'geography(Point,4326)', 'provider.geo geography Point 4326');
SELECT col_type_is('establishment', 'geo', 'geography(Point,4326)', 'establishment.geo geography Point 4326');

-- défauts métier (lus directement dans le catalogue : robuste quel que soit le rendu pgTAP)
SELECT is(
  (SELECT pg_get_expr(d.adbin, d.adrelid)
     FROM pg_attrdef d JOIN pg_attribute a ON a.attrelid=d.adrelid AND a.attnum=d.adnum
    WHERE d.adrelid='appointment'::regclass AND a.attname='pre_checkin'),
  '''{}''::jsonb', 'appointment.pre_checkin défaut {}');
SELECT is(
  (SELECT pg_get_expr(d.adbin, d.adrelid)
     FROM pg_attrdef d JOIN pg_attribute a ON a.attrelid=d.adrelid AND a.attnum=d.adnum
    WHERE d.adrelid='message'::regclass AND a.attname='triage_flag'),
  '''normal''::text', 'message.triage_flag défaut normal');
SELECT is(
  (SELECT pg_get_expr(d.adbin, d.adrelid)
     FROM pg_attrdef d JOIN pg_attribute a ON a.attrelid=d.adrelid AND a.attnum=d.adnum
    WHERE d.adrelid='provider'::regclass AND a.attname='is_listed'),
  'false', 'provider.is_listed défaut false');

-- ----- Clés étrangères clés -----
SELECT fk_ok('patient', 'cabinet_id', 'cabinet', 'id');
SELECT fk_ok('appointment', 'practitioner_id', 'practitioner', 'id');
SELECT fk_ok('quote_item', 'quote_id', 'quote', 'id');
SELECT fk_ok('patient', 'patient_account_id', 'patient_account', 'id');  -- lien plateforme (0009)
SELECT fk_ok('patient_account', 'app_user_id', 'app_user', 'id');        -- FK + CASCADE (0015, #178)
SELECT col_not_null('patient_account', 'app_user_id', 'patient_account.app_user_id NOT NULL (0015)');
SELECT fk_ok('quote_item', 'phase_id', 'treatment_phase', 'id');         -- plan de traitement (0010)

-- ----- Lien clinique <-> compte plateforme & couverture (0010) -----
SELECT has_column('patient_account', 'regime_obligatoire', 'patient_account.regime_obligatoire (couverture)');
SELECT has_column('patient_account', 'tiers_payant', 'patient_account.tiers_payant');
SELECT has_column('clinical_note', 'note_kind', 'clinical_note.note_kind (journal clinique)');

-- ----- consent_record (0017, issue #180) -----
SELECT col_not_null('consent_record', 'purpose', 'consent_record.purpose NOT NULL (RGPD)');
SELECT col_not_null('consent_record', 'granted', 'consent_record.granted NOT NULL');

-- ----- refresh_token (0016, issue #179) -----
SELECT has_table('refresh_token');
SELECT col_is_unique('refresh_token', 'token_hash', 'refresh_token.token_hash UNIQUE (hash SHA-256 uniquement)');
SELECT col_not_null('refresh_token', 'expires_at', 'refresh_token.expires_at NOT NULL');
SELECT col_not_null('refresh_token', 'app_user_id', 'refresh_token.app_user_id NOT NULL');

-- ----- app_user : cgu_accepted_at (0043, issue #718) -----
SELECT has_column('app_user', 'cgu_accepted_at', 'app_user.cgu_accepted_at présent (0043)');
SELECT col_type_is('app_user', 'cgu_accepted_at', 'timestamp with time zone',
  'app_user.cgu_accepted_at timestamptz');
SELECT col_is_null('app_user', 'cgu_accepted_at', 'app_user.cgu_accepted_at nullable (CGU non encore acceptées OK)');

-- ----- patient_account : colonnes chiffrées prénom/nom (0044, issue #718) -----
SELECT has_column('patient_account', 'first_name_ciphertext',
  'patient_account.first_name_ciphertext présent (0044)');
SELECT col_type_is('patient_account', 'first_name_ciphertext', 'bytea',
  'patient_account.first_name_ciphertext bytea');
SELECT has_column('patient_account', 'first_name_key_ref',
  'patient_account.first_name_key_ref présent (0044)');
SELECT has_column('patient_account', 'last_name_ciphertext',
  'patient_account.last_name_ciphertext présent (0044)');
SELECT has_column('patient_account', 'last_name_key_ref',
  'patient_account.last_name_key_ref présent (0044)');

-- ----- RLS plateforme : app_user et patient_account (0045, issue #718) -----
SELECT ok( (SELECT relrowsecurity FROM pg_class WHERE relname = 'app_user'),
  'app_user : ROW LEVEL SECURITY activée (0045)');
SELECT ok( (SELECT relforcerowsecurity FROM pg_class WHERE relname = 'app_user'),
  'app_user : FORCE ROW LEVEL SECURITY (0045)');
SELECT ok( EXISTS(SELECT 1 FROM pg_policies WHERE tablename = 'app_user' AND policyname = 'user_self_select'),
  'app_user : policy user_self_select présente (0045)');
SELECT ok( (SELECT relrowsecurity FROM pg_class WHERE relname = 'patient_account'),
  'patient_account : ROW LEVEL SECURITY activée (0045)');
SELECT ok( (SELECT relforcerowsecurity FROM pg_class WHERE relname = 'patient_account'),
  'patient_account : FORCE ROW LEVEL SECURITY (0045)');
SELECT ok( EXISTS(SELECT 1 FROM pg_policies WHERE tablename = 'patient_account' AND policyname = 'account_self_select'),
  'patient_account : policy account_self_select présente (0045)');

-- ----- app_metadata (0013) -----
SELECT has_table('app_metadata');
SELECT is(
  (SELECT value FROM app_metadata WHERE key = 'version'),
  '0.1.0', 'app_metadata version = 0.1.0');

-- ----- patient_coverage (0023, issue #237) -----
SELECT has_table('patient_coverage');
SELECT has_column('patient_coverage', 'nss_encrypted', 'bytea');
SELECT col_is_null('patient_coverage', 'nss_encrypted');

-- ----- notification_preference (0024, issue #238) -----
SELECT has_table('notification_preference');
SELECT col_is_unique('notification_preference', 'patient_account_id',
  'notification_preference.patient_account_id UNIQUE (une ligne par compte)');

-- ----- account_guardianship (0025, issue #239) -----
SELECT has_table('account_guardianship');
SELECT has_column('account_guardianship', 'active',     'account_guardianship.active présent');
SELECT col_type_is('account_guardianship', 'active', 'boolean', 'account_guardianship.active boolean');
SELECT col_not_null('account_guardianship', 'active',   'account_guardianship.active NOT NULL');
SELECT col_has_default('account_guardianship', 'active','account_guardianship.active défaut true');

-- ----- mfa_enrollment (0046, issue #719) -----
SELECT has_table('mfa_enrollment');
SELECT col_not_null('mfa_enrollment', 'app_user_id',       'mfa_enrollment.app_user_id NOT NULL');
SELECT col_not_null('mfa_enrollment', 'secret_ciphertext', 'mfa_enrollment.secret_ciphertext NOT NULL');
SELECT col_not_null('mfa_enrollment', 'method',            'mfa_enrollment.method NOT NULL');
SELECT col_not_null('mfa_enrollment', 'verified',          'mfa_enrollment.verified NOT NULL');
SELECT col_not_null('mfa_enrollment', 'enrolled_at',       'mfa_enrollment.enrolled_at NOT NULL');
SELECT col_type_is('mfa_enrollment', 'secret_ciphertext', 'bytea',
  'mfa_enrollment.secret_ciphertext bytea (chiffré KMS)');
SELECT fk_ok('mfa_enrollment', 'app_user_id', 'app_user', 'id',
  'mfa_enrollment.app_user_id FK → app_user.id');
SELECT ok(
  EXISTS(SELECT 1 FROM pg_indexes WHERE tablename = 'mfa_enrollment'
    AND indexname = 'idx_mfa_enrollment_app_user_id'),
  'mfa_enrollment : index sur app_user_id présent (0046)');

-- ----- RLS : refresh_token + mfa_enrollment (0047, issue #719) -----
SELECT ok( (SELECT relrowsecurity FROM pg_class WHERE relname = 'refresh_token'),
  'refresh_token : ROW LEVEL SECURITY activée (0047)');
SELECT ok( (SELECT relforcerowsecurity FROM pg_class WHERE relname = 'refresh_token'),
  'refresh_token : FORCE ROW LEVEL SECURITY (0047)');
SELECT ok( EXISTS(SELECT 1 FROM pg_policies WHERE tablename = 'refresh_token'
    AND policyname = 'token_user_select'),
  'refresh_token : policy token_user_select présente (0047)');
SELECT ok( (SELECT relrowsecurity FROM pg_class WHERE relname = 'mfa_enrollment'),
  'mfa_enrollment : ROW LEVEL SECURITY activée (0047)');
SELECT ok( (SELECT relforcerowsecurity FROM pg_class WHERE relname = 'mfa_enrollment'),
  'mfa_enrollment : FORCE ROW LEVEL SECURITY (0047)');
SELECT ok( EXISTS(SELECT 1 FROM pg_policies WHERE tablename = 'mfa_enrollment'
    AND policyname = 'mfa_user_select'),
  'mfa_enrollment : policy mfa_user_select présente (0047)');

SELECT * FROM finish();
ROLLBACK;
