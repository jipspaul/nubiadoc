-- 10_consent_notification_rls.sql — RLS isolation consent_record + notification_preference (issue #720).
-- Vérifie : fail-closed, non-fuite inter-compte, unicité consent, contraintes FK.
-- Tourne sous nubia_app (NOSUPERUSER, NOBYPASSRLS) — GUC app.current_account_id scopé.
BEGIN;
SELECT * FROM no_plan();

-- ===========================================================================
-- Fixtures : deux app_users + deux patient_accounts.
-- INSERT ouvert (policies user_app_insert / account_app_insert WITH CHECK(true)).
-- ===========================================================================
INSERT INTO app_user (id, email, password_hash, kind)
  VALUES ('d0000000-0000-0000-0000-0000000000a1', 'consent.a@example.test', '$argon2id$fixture', 'patient');
INSERT INTO app_user (id, email, password_hash, kind)
  VALUES ('d0000000-0000-0000-0000-0000000000a2', 'consent.b@example.test', '$argon2id$fixture', 'patient');

INSERT INTO patient_account (id, app_user_id, first_name, last_name)
  VALUES ('d0000000-0000-0000-0000-0000000000e1', 'd0000000-0000-0000-0000-0000000000a1', 'Compte', 'A');
INSERT INTO patient_account (id, app_user_id, first_name, last_name)
  VALUES ('d0000000-0000-0000-0000-0000000000e2', 'd0000000-0000-0000-0000-0000000000a2', 'Compte', 'B');

-- consent_record : INSERT ouvert (consent_account_insert WITH CHECK(true)).
INSERT INTO consent_record (id, patient_account_id, purpose, granted)
  VALUES ('d0000000-0000-0000-0000-000000000001',
          'd0000000-0000-0000-0000-0000000000e1',
          'soins', true);
INSERT INTO consent_record (id, patient_account_id, purpose, granted)
  VALUES ('d0000000-0000-0000-0000-000000000002',
          'd0000000-0000-0000-0000-0000000000e2',
          'soins', true);

-- notification_preference : INSERT borné (notif_pref_account_insert WITH CHECK(patient_account_id = GUC)).
SET LOCAL app.current_account_id = 'd0000000-0000-0000-0000-0000000000e1';
INSERT INTO notification_preference (id, patient_account_id, channel, enabled, type)
  VALUES ('d0000000-0000-0000-0000-000000000010',
          'd0000000-0000-0000-0000-0000000000e1',
          'email', true, 'rdv');

SET LOCAL app.current_account_id = 'd0000000-0000-0000-0000-0000000000e2';
INSERT INTO notification_preference (id, patient_account_id, channel, enabled, type)
  VALUES ('d0000000-0000-0000-0000-000000000011',
          'd0000000-0000-0000-0000-0000000000e2',
          'email', true, 'rdv');

-- ===========================================================================
-- 1. consent_record : FAIL-CLOSED (sans GUC → 0 ligne visible)
-- ===========================================================================
RESET app.current_account_id;
SELECT is(
  (SELECT count(*) FROM consent_record
   WHERE id IN ('d0000000-0000-0000-0000-000000000001',
                'd0000000-0000-0000-0000-000000000002'))::int, 0,
  '⭐ fail-closed consent_record : aucun consentement visible sans app.current_account_id');

-- ===========================================================================
-- 2. notification_preference : FAIL-CLOSED
-- ===========================================================================
SELECT is(
  (SELECT count(*) FROM notification_preference
   WHERE id IN ('d0000000-0000-0000-0000-000000000010',
                'd0000000-0000-0000-0000-000000000011'))::int, 0,
  '⭐ fail-closed notification_preference : aucune préférence visible sans app.current_account_id');

-- ===========================================================================
-- 3. ISOLATION : compte A voit ses données, pas celles de B
-- ===========================================================================
SET LOCAL app.current_account_id = 'd0000000-0000-0000-0000-0000000000e1';

SELECT is(
  (SELECT count(*) FROM consent_record
   WHERE id IN ('d0000000-0000-0000-0000-000000000001',
                'd0000000-0000-0000-0000-000000000002'))::int, 1,
  'consent_record contexte compte A : 1 consentement visible (le sien)');
SELECT is(
  (SELECT count(*) FROM consent_record WHERE id = 'd0000000-0000-0000-0000-000000000002')::int, 0,
  '⭐ non-fuite consent_record : compte A ne voit PAS les consentements de B');

SELECT is(
  (SELECT count(*) FROM notification_preference
   WHERE id IN ('d0000000-0000-0000-0000-000000000010',
                'd0000000-0000-0000-0000-000000000011'))::int, 1,
  'notification_preference contexte compte A : 1 préférence visible (la sienne)');
SELECT is(
  (SELECT count(*) FROM notification_preference WHERE id = 'd0000000-0000-0000-0000-000000000011')::int, 0,
  '⭐ non-fuite notification_preference : compte A ne voit PAS les préférences de B');

SET LOCAL app.current_account_id = 'd0000000-0000-0000-0000-0000000000e2';

SELECT is(
  (SELECT count(*) FROM consent_record
   WHERE id IN ('d0000000-0000-0000-0000-000000000001',
                'd0000000-0000-0000-0000-000000000002'))::int, 1,
  'consent_record contexte compte B : 1 consentement visible (le sien)');
SELECT is(
  (SELECT count(*) FROM consent_record WHERE id = 'd0000000-0000-0000-0000-000000000001')::int, 0,
  '⭐ non-fuite consent_record : compte B ne voit PAS les consentements de A');

SELECT is(
  (SELECT count(*) FROM notification_preference
   WHERE id IN ('d0000000-0000-0000-0000-000000000010',
                'd0000000-0000-0000-0000-000000000011'))::int, 1,
  'notification_preference contexte compte B : 1 préférence visible (la sienne)');
SELECT is(
  (SELECT count(*) FROM notification_preference WHERE id = 'd0000000-0000-0000-0000-000000000010')::int, 0,
  '⭐ non-fuite notification_preference : compte B ne voit PAS les préférences de A');

-- ===========================================================================
-- 4. UNICITÉ (patient_account_id, purpose) sur consent_record (23505)
-- ===========================================================================
SELECT throws_ok(
  $$ INSERT INTO consent_record (patient_account_id, purpose, granted)
     VALUES ('d0000000-0000-0000-0000-0000000000e2', 'soins', false) $$,
  '23505', NULL,
  'consent_record UNIQUE(patient_account_id, purpose) → doublon refusé (23505)');

-- ===========================================================================
-- 5. FK → patient_account (23503 si compte inexistant)
-- ===========================================================================
SELECT throws_ok(
  $$ INSERT INTO consent_record (patient_account_id, purpose, granted)
     VALUES ('00000000-0000-0000-0000-000000000099', 'soins', true) $$,
  '23503', NULL,
  'consent_record.patient_account_id FK → patient_account.id (23503 si inexistant)');

-- Pour notification_preference : GUC = UUID orphelin pour passer le WITH CHECK, FK bloque.
SET LOCAL app.current_account_id = '00000000-0000-0000-0000-000000000099';
SELECT throws_ok(
  $$ INSERT INTO notification_preference (patient_account_id, channel, enabled, type)
     VALUES ('00000000-0000-0000-0000-000000000099', 'push', true, 'rdv') $$,
  '23503', NULL,
  'notification_preference.patient_account_id FK → patient_account.id (23503 si inexistant)');

SELECT * FROM finish();
ROLLBACK;
