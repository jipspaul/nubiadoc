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
SELECT has_table('assistant_query');

-- ----- Clés primaires -----
SELECT has_pk('cabinet');
SELECT has_pk('patient');
SELECT has_pk('appointment');
SELECT has_pk('quote');
SELECT has_pk('audit_log');     -- PK composite (id, occurred_at)

-- ----- Colonnes & types : tenant + horodatage (échantillon représentatif) -----
SELECT col_type_is('patient', 'id', 'uuid', 'patient.id uuid');
SELECT col_has_default('patient', 'id', 'patient.id a un défaut (gen_random_uuid)');
SELECT col_type_is('patient', 'cabinet_id', 'uuid', 'patient.cabinet_id uuid');
SELECT col_not_null('patient', 'cabinet_id', 'patient.cabinet_id NOT NULL (tenant)');
SELECT col_type_is('patient', 'created_at', 'timestamp with time zone', 'patient.created_at timestamptz');
SELECT col_type_is('patient', 'deleted_at', 'timestamp with time zone', 'patient.deleted_at timestamptz (soft-delete)');

-- email citext + unique (app_user)
SELECT col_type_is('app_user', 'email', 'citext', 'app_user.email citext');
-- colonnes d'identité/auth (0014, issue #177)
SELECT col_is_unique('app_user', 'email', 'app_user.email UNIQUE');
SELECT col_not_null('app_user', 'password_hash', 'app_user.password_hash NOT NULL');
SELECT col_not_null('app_user', 'kind', 'app_user.kind NOT NULL');
SELECT has_column('app_user', 'totp_secret', 'app_user.totp_secret présent');
SELECT col_not_null('app_user', 'totp_enabled', 'app_user.totp_enabled NOT NULL');
SELECT has_column('app_user', 'password_reset_token', 'app_user.password_reset_token présent');
SELECT has_column('app_user', 'password_reset_expires_at', 'app_user.password_reset_expires_at présent');

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
SELECT fk_ok('quote_item', 'phase_id', 'treatment_phase', 'id');         -- plan de traitement (0010)

-- ----- Lien clinique <-> compte plateforme & couverture (0010) -----
SELECT has_column('patient_account', 'regime_obligatoire', 'patient_account.regime_obligatoire (couverture)');
SELECT has_column('patient_account', 'tiers_payant', 'patient_account.tiers_payant');
SELECT has_column('clinical_note', 'note_kind', 'clinical_note.note_kind (journal clinique)');

-- ----- app_metadata (0013) -----
SELECT has_table('app_metadata');
SELECT is(
  (SELECT value FROM app_metadata WHERE key = 'version'),
  '0.1.0', 'app_metadata version = 0.1.0');

SELECT * FROM finish();
ROLLBACK;
