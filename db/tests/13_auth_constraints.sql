-- 13_auth_constraints.sql — Contraintes auth/account (issue #732).
-- Vérifie : UNIQUE email, UNIQUE consent, UNIQUE notif_pref, FK CASCADE.
-- Tourne sous nubia_app (NOSUPERUSER, NOBYPASSRLS).
BEGIN;
SELECT * FROM no_plan();

-- ===========================================================================
-- 1. FK ON DELETE CASCADE (via catalogue pg_constraint)
--    confdeltype : 'c' = CASCADE, 'a' = NO ACTION, 'r' = RESTRICT, 'n' = SET NULL
-- ===========================================================================
SELECT is(
  (SELECT c.confdeltype::text
     FROM pg_constraint c
     JOIN pg_class t ON t.oid = c.conrelid
    WHERE t.relname = 'patient_account'
      AND c.conname = 'patient_account_app_user_id_fkey'),
  'c',
  'patient_account.app_user_id FK → app_user ON DELETE CASCADE (0015)');

SELECT is(
  (SELECT c.confdeltype::text
     FROM pg_constraint c
     JOIN pg_class t ON t.oid = c.conrelid
    WHERE t.relname = 'refresh_token'
      AND c.conname = 'refresh_token_app_user_id_fkey'),
  'c',
  'refresh_token.app_user_id FK → app_user ON DELETE CASCADE (0016)');

SELECT is(
  (SELECT c.confdeltype::text
     FROM pg_constraint c
     JOIN pg_class t ON t.oid = c.conrelid
    WHERE t.relname = 'mfa_enrollment'
      AND c.conname = 'mfa_enrollment_app_user_id_fkey'),
  'c',
  'mfa_enrollment.app_user_id FK → app_user ON DELETE CASCADE (0046)');

-- ===========================================================================
-- Fixtures minimales pour les tests de contraintes comportementales.
-- Préfixe 13000000 (hors seed migrations : a/b/c/d/e0000000).
-- ===========================================================================
INSERT INTO app_user (id, email, password_hash, kind)
  VALUES ('13000000-0000-0000-0000-0000000000a1', 'constraints.auth@example.test', '$argon2id$fixture', 'patient');

INSERT INTO patient_account (id, app_user_id, first_name, last_name)
  VALUES ('13000000-0000-0000-0000-0000000000e1', '13000000-0000-0000-0000-0000000000a1', 'Test', 'Contrainte');

-- ===========================================================================
-- 2. app_user.email UNIQUE (citext — insensible à la casse)
-- ===========================================================================
SELECT throws_ok(
  $$ INSERT INTO app_user (email, password_hash, kind)
     VALUES ('constraints.auth@example.test', '$h$', 'pro') $$,
  '23505', NULL,
  'app_user.email UNIQUE → doublon exact rejeté (23505)');

SELECT throws_ok(
  $$ INSERT INTO app_user (email, password_hash, kind)
     VALUES ('CONSTRAINTS.AUTH@EXAMPLE.TEST', '$h$', 'pro') $$,
  '23505', NULL,
  'app_user.email UNIQUE citext → doublon insensible à la casse rejeté (23505)');

-- ===========================================================================
-- 3. consent_record : UNIQUE(patient_account_id, purpose) — upsert RGPD idempotent
-- ===========================================================================
-- INSERT ouvert (policy consent_account_insert WITH CHECK(true) — pas de GUC requis)
INSERT INTO consent_record (id, patient_account_id, purpose, granted)
  VALUES ('13000000-0000-0000-0000-000000000001',
          '13000000-0000-0000-0000-0000000000e1',
          'soins', true);

SELECT throws_ok(
  $$ INSERT INTO consent_record (patient_account_id, purpose, granted)
     VALUES ('13000000-0000-0000-0000-0000000000e1', 'soins', false) $$,
  '23505', NULL,
  'consent_record UNIQUE(patient_account_id, purpose) → doublon rejeté (23505)');

-- FK → patient_account : compte inexistant rejeté (23503)
SELECT throws_ok(
  $$ INSERT INTO consent_record (patient_account_id, purpose, granted)
     VALUES ('00000000-0000-0000-0000-000000000099', 'soins', true) $$,
  '23503', NULL,
  'consent_record.patient_account_id FK → patient_account.id (23503 si compte inexistant)');

-- ===========================================================================
-- 4. notification_preference : UNIQUE(patient_account_id, channel, type) (0049)
-- ===========================================================================
-- INSERT borné par GUC app.current_account_id (policy notif_pref_account_insert)
SET LOCAL app.current_account_id = '13000000-0000-0000-0000-0000000000e1';

INSERT INTO notification_preference (id, patient_account_id, channel, enabled, type)
  VALUES ('13000000-0000-0000-0000-000000000010',
          '13000000-0000-0000-0000-0000000000e1',
          'email', true, 'rdv');

SELECT throws_ok(
  $$ INSERT INTO notification_preference (patient_account_id, channel, enabled, type)
     VALUES ('13000000-0000-0000-0000-0000000000e1', 'email', false, 'rdv') $$,
  '23505', NULL,
  'notification_preference UNIQUE(patient_account_id, channel, type) → doublon rejeté (23505)');

-- Canal différent → accepté (tuple (account_id, push, rdv) distinct)
SELECT lives_ok(
  $$ INSERT INTO notification_preference (patient_account_id, channel, enabled, type)
     VALUES ('13000000-0000-0000-0000-0000000000e1', 'push', true, 'rdv') $$,
  'notification_preference canal différent (push vs email) → accepté');

SELECT * FROM finish();
ROLLBACK;
