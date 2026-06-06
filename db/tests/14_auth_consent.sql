-- 14_auth_consent.sql — Cycle de vie du consentement RGPD (issue #732).
-- Vérifie : grant initial → révocation → re-grant ; unicité idempotente ; FK compte.
-- Tourne sous nubia_app (NOSUPERUSER, NOBYPASSRLS).
BEGIN;
SELECT * FROM no_plan();

-- ===========================================================================
-- Fixtures : un app_user + un patient_account.
-- Préfixe 14000000 (hors seed migrations : a/b/c/d/e0000000).
-- ===========================================================================
INSERT INTO app_user (id, email, password_hash, kind)
  VALUES ('14000000-0000-0000-0000-0000000000a1', 'consent.lifecycle@example.test', '$argon2id$fixture', 'patient');
INSERT INTO patient_account (id, app_user_id, first_name, last_name)
  VALUES ('14000000-0000-0000-0000-0000000000e1', '14000000-0000-0000-0000-0000000000a1', 'Cycle', 'Consentement');

-- Contexte RLS : SELECT/UPDATE sur consent_record borné au compte courant (0048).
SET LOCAL app.current_account_id = '14000000-0000-0000-0000-0000000000e1';

-- ===========================================================================
-- 1. GRANT initial
-- ===========================================================================
INSERT INTO consent_record (id, patient_account_id, purpose, granted)
  VALUES ('14000000-0000-0000-0000-000000000001',
          '14000000-0000-0000-0000-0000000000e1',
          'soins', true);

SELECT is(
  (SELECT granted FROM consent_record WHERE id = '14000000-0000-0000-0000-000000000001'),
  true,
  'consent lifecycle 1/3 : consentement accordé (granted = true)');

SELECT is(
  (SELECT revoked_at FROM consent_record WHERE id = '14000000-0000-0000-0000-000000000001'),
  NULL::timestamptz,
  'consent lifecycle 1/3 : revoked_at NULL (non encore révoqué)');

-- ===========================================================================
-- 2. REVOKE
-- ===========================================================================
UPDATE consent_record
   SET granted = false, revoked_at = now()
 WHERE id = '14000000-0000-0000-0000-000000000001';

SELECT is(
  (SELECT granted FROM consent_record WHERE id = '14000000-0000-0000-0000-000000000001'),
  false,
  'consent lifecycle 2/3 : consentement révoqué (granted = false)');

SELECT ok(
  (SELECT revoked_at FROM consent_record WHERE id = '14000000-0000-0000-0000-000000000001') IS NOT NULL,
  'consent lifecycle 2/3 : revoked_at renseigné après révocation');

-- ===========================================================================
-- 3. RE-GRANT
-- ===========================================================================
UPDATE consent_record
   SET granted = true, revoked_at = NULL
 WHERE id = '14000000-0000-0000-0000-000000000001';

SELECT is(
  (SELECT granted FROM consent_record WHERE id = '14000000-0000-0000-0000-000000000001'),
  true,
  'consent lifecycle 3/3 : re-consentement accordé (granted = true)');

SELECT is(
  (SELECT revoked_at FROM consent_record WHERE id = '14000000-0000-0000-0000-000000000001'),
  NULL::timestamptz,
  'consent lifecycle 3/3 : revoked_at réinitialisé à NULL après re-grant');

-- ===========================================================================
-- 4. Idempotence : UNIQUE(patient_account_id, purpose) — pas de double ligne.
--    Même après re-grant, une 2ᵉ insertion pour le même purpose est rejetée.
-- ===========================================================================
SELECT throws_ok(
  $$ INSERT INTO consent_record (patient_account_id, purpose, granted)
     VALUES ('14000000-0000-0000-0000-0000000000e1', 'soins', true) $$,
  '23505', NULL,
  '⭐ consent idempotence : UNIQUE(patient_account_id, purpose) → doublon rejeté même après re-grant');

-- ===========================================================================
-- 5. Consentements distincts par purpose → coexistent sans conflit.
-- ===========================================================================
SELECT lives_ok(
  $$ INSERT INTO consent_record (patient_account_id, purpose, granted)
     VALUES ('14000000-0000-0000-0000-0000000000e1', 'marketing', false) $$,
  'consent purpose différent (marketing) → accepté sans conflit');

SELECT is(
  (SELECT count(*) FROM consent_record
   WHERE patient_account_id = '14000000-0000-0000-0000-0000000000e1')::int, 2,
  'deux consentements distincts (soins + marketing) coexistent pour le même compte');

-- ===========================================================================
-- 6. FK → patient_account : compte inexistant rejeté.
-- ===========================================================================
SELECT throws_ok(
  $$ INSERT INTO consent_record (patient_account_id, purpose, granted)
     VALUES ('00000000-0000-0000-0000-000000000099', 'soins', true) $$,
  '23503', NULL,
  'consent_record.patient_account_id FK → patient_account.id (23503 si compte inexistant)');

SELECT * FROM finish();
ROLLBACK;
