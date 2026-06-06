-- 13_auth_constraints.sql — Contraintes auth/account : CHECK, UNIQUE, FK ON DELETE CASCADE.
-- Teste : kind/status CHECK, mfa method CHECK, email UNIQUE, consent UNIQUE, crypto pair CHECK,
-- FK CASCADE app_user → patient_account + refresh_token + mfa_enrollment,
-- FK NO ACTION consent_record.patient_account_id (empêche la suppression d'un compte référencé).
-- pgTAP, exécuté par pg_prove sous nubia_app.
BEGIN;
SELECT * FROM no_plan();

-- ===========================================================================
-- Fixtures
-- ===========================================================================
INSERT INTO app_user (id, email, password_hash, kind)
  VALUES ('f0000000-0000-0000-0000-0000000000a1', 'constr.a@example.test', '$argon2id$fx', 'patient'),
         ('f0000000-0000-0000-0000-0000000000a2', 'constr.b@example.test', '$argon2id$fx', 'patient');

INSERT INTO patient_account (id, app_user_id, first_name, last_name)
  VALUES ('f0000000-0000-0000-0000-0000000000e1', 'f0000000-0000-0000-0000-0000000000a1', 'Gamma', 'A'),
         ('f0000000-0000-0000-0000-0000000000e2', 'f0000000-0000-0000-0000-0000000000a2', 'Delta', 'B');

-- refresh_token et mfa_enrollment pour user A (testés dans le CASCADE)
INSERT INTO refresh_token (id, app_user_id, token_hash, expires_at)
  VALUES ('f0000000-0000-0000-0000-000000000001',
          'f0000000-0000-0000-0000-0000000000a1', 'sha_constr_a', now() + interval '30 days');

INSERT INTO mfa_enrollment (id, app_user_id, secret_ciphertext, secret_key_ref, method, verified)
  VALUES ('f0000000-0000-0000-0000-000000000010',
          'f0000000-0000-0000-0000-0000000000a1', '\x1122'::bytea, 'k/constr/a', 'totp', false);

-- consent_record pour user B via app_user_id (chemin CGU) et pour account e2 (chemin RGPD)
INSERT INTO consent_record (id, app_user_id, purpose, granted)
  VALUES ('f0000000-0000-0000-0000-000000000030',
          'f0000000-0000-0000-0000-0000000000a2', 'cgu', true);

SET LOCAL app.current_account_id = 'f0000000-0000-0000-0000-0000000000e2';
INSERT INTO consent_record (id, patient_account_id, purpose, granted)
  VALUES ('f0000000-0000-0000-0000-000000000031',
          'f0000000-0000-0000-0000-0000000000e2', 'soins', true);

-- ===========================================================================
-- 1. CHECK : app_user.kind (patient|pro) — valeur invalide rejetée
-- ===========================================================================
SELECT throws_ok(
  $$ INSERT INTO app_user (email, password_hash, kind)
     VALUES ('bad.kind@example.test', '$h$', 'admin') $$,
  '23514', NULL,
  'app_user.kind invalide rejeté (CHECK kind IN patient, pro)');

-- ===========================================================================
-- 2. CHECK : app_user.status (active|suspended|disabled) — valeur invalide
-- ===========================================================================
SELECT throws_ok(
  $$ INSERT INTO app_user (email, password_hash, kind, status)
     VALUES ('bad.status@example.test', '$h$', 'patient', 'banned') $$,
  '23514', NULL,
  'app_user.status invalide rejeté (CHECK status IN active, suspended, disabled)');

-- ===========================================================================
-- 3. CHECK : mfa_enrollment.method — seul ''totp'' autorisé en v1
-- ===========================================================================
SELECT throws_ok(
  $$ INSERT INTO mfa_enrollment (app_user_id, secret_ciphertext, secret_key_ref, method)
     VALUES ('f0000000-0000-0000-0000-0000000000a2', '\x01'::bytea, 'k', 'sms') $$,
  '23514', NULL,
  'mfa_enrollment.method invalide rejeté (CHECK method = totp)');

-- ===========================================================================
-- 4. UNIQUE : app_user.email (citext — insensible à la casse)
-- ===========================================================================
SELECT throws_ok(
  $$ INSERT INTO app_user (email, password_hash, kind)
     VALUES ('constr.a@example.test', '$h$', 'patient') $$,
  '23505', NULL,
  'app_user.email UNIQUE → doublon exact rejeté (23505)');

SELECT throws_ok(
  $$ INSERT INTO app_user (email, password_hash, kind)
     VALUES ('CONSTR.A@EXAMPLE.TEST', '$h$', 'pro') $$,
  '23505', NULL,
  'app_user.email UNIQUE citext → collision casse rejetée (23505)');

-- ===========================================================================
-- 5. UNIQUE : consent_record(patient_account_id, purpose) — doublon RGPD refusé
-- ===========================================================================
SELECT throws_ok(
  $$ INSERT INTO consent_record (patient_account_id, purpose, granted)
     VALUES ('f0000000-0000-0000-0000-0000000000e2', 'soins', false) $$,
  '23505', NULL,
  'consent_record UNIQUE(patient_account_id, purpose) → doublon refusé (23505)');

-- ===========================================================================
-- 6. UNIQUE : consent_record(app_user_id, purpose) — doublon CGU refusé
-- ===========================================================================
SELECT throws_ok(
  $$ INSERT INTO consent_record (app_user_id, purpose, granted)
     VALUES ('f0000000-0000-0000-0000-0000000000a2', 'cgu', false) $$,
  '23505', NULL,
  'consent_record UNIQUE(app_user_id, purpose) → doublon CGU refusé (23505)');

-- ===========================================================================
-- 7. FK consent_record.patient_account_id → patient_account : NO ACTION.
--    Empêche de supprimer un patient_account référencé par un consentement actif.
-- ===========================================================================
SET LOCAL app.current_account_id = 'f0000000-0000-0000-0000-0000000000e2';
SELECT throws_ok(
  $$ DELETE FROM patient_account WHERE id = 'f0000000-0000-0000-0000-0000000000e2' $$,
  '23503', NULL,
  '⭐ FK NO ACTION : supprimer patient_account référencé par consent_record bloqué (23503)');

-- ===========================================================================
-- 8. CHECK crypto pair patient_account (fn, ln) : ciphertext sans key_ref rejeté
-- ===========================================================================
SET LOCAL app.current_account_id = 'f0000000-0000-0000-0000-0000000000e1';
SELECT throws_ok(
  $$ UPDATE patient_account
     SET first_name_ciphertext = '\x01'::bytea
     WHERE id = 'f0000000-0000-0000-0000-0000000000e1' $$,
  '23514', NULL,
  'patient_account : first_name_ciphertext sans key_ref rejeté (CHECK fn_crypto_pair)');

SELECT throws_ok(
  $$ UPDATE patient_account
     SET last_name_ciphertext = '\x01'::bytea
     WHERE id = 'f0000000-0000-0000-0000-0000000000e1' $$,
  '23514', NULL,
  'patient_account : last_name_ciphertext sans key_ref rejeté (CHECK ln_crypto_pair)');

-- ===========================================================================
-- 9. FK ON DELETE CASCADE : suppression app_user entraîne la suppression de
--    patient_account, refresh_token et mfa_enrollment (ON DELETE CASCADE).
--    User A n''a pas de consent_record lié à son patient_account_e1, donc
--    pas de FK NO ACTION bloquant la cascade (voir §7 ci-dessus).
-- ===========================================================================

-- Vérifier présence des lignes avant la suppression
SET LOCAL app.current_account_id = 'f0000000-0000-0000-0000-0000000000e1';
SELECT is(
  (SELECT count(*) FROM patient_account WHERE id = 'f0000000-0000-0000-0000-0000000000e1')::int, 1,
  'patient_account A présent avant DELETE app_user');

SET LOCAL app.current_user_id = 'f0000000-0000-0000-0000-0000000000a1';
SELECT is(
  (SELECT count(*) FROM refresh_token WHERE id = 'f0000000-0000-0000-0000-000000000001')::int, 1,
  'refresh_token A présent avant DELETE app_user');
SELECT is(
  (SELECT count(*) FROM mfa_enrollment WHERE id = 'f0000000-0000-0000-0000-000000000010')::int, 1,
  'mfa_enrollment A présent avant DELETE app_user');

-- Suppression sous le contexte de user A (policy user_self_delete)
DELETE FROM app_user WHERE id = 'f0000000-0000-0000-0000-0000000000a1';

-- Après CASCADE : les trois tables doivent être à 0 avec le MÊME contexte GUC
-- (même GUC → même filtre RLS ; si 1→0, c''est bien une suppression physique, pas du filtrage)
SELECT is(
  (SELECT count(*) FROM patient_account WHERE id = 'f0000000-0000-0000-0000-0000000000e1')::int, 0,
  '⭐ CASCADE : patient_account supprimé avec app_user (ON DELETE CASCADE)');
SELECT is(
  (SELECT count(*) FROM refresh_token WHERE id = 'f0000000-0000-0000-0000-000000000001')::int, 0,
  '⭐ CASCADE : refresh_token supprimé avec app_user (ON DELETE CASCADE)');
SELECT is(
  (SELECT count(*) FROM mfa_enrollment WHERE id = 'f0000000-0000-0000-0000-000000000010')::int, 0,
  '⭐ CASCADE : mfa_enrollment supprimé avec app_user (ON DELETE CASCADE)');

SELECT * FROM finish();
ROLLBACK;
