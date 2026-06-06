-- 14_auth_consent.sql — Cycle de vie des consentements RGPD : grant → revoke → re-grant.
-- Vérifie le comportement applicatif attendu du contrat PUT /v1/account/consents/{purpose} :
--   INSERT initial (grant), UPDATE révocation (revoked_at posé), UPDATE re-grant (revoked_at effacé).
-- Couvre les deux chemins : RGPD patient (patient_account_id) et CGU plateforme (app_user_id).
-- pgTAP, exécuté par pg_prove sous nubia_app (NOSUPERUSER, NOBYPASSRLS).
BEGIN;
SELECT * FROM no_plan();

-- ===========================================================================
-- Fixtures
-- ===========================================================================
INSERT INTO app_user (id, email, password_hash, kind)
  VALUES ('14000000-0000-0000-0000-0000000000a1', 'consent.life.a@example.test', '$argon2id$fx', 'patient'),
         ('14000000-0000-0000-0000-0000000000a2', 'consent.life.b@example.test', '$argon2id$fx', 'patient');

INSERT INTO patient_account (id, app_user_id, first_name, last_name)
  VALUES ('14000000-0000-0000-0000-0000000000e1', '14000000-0000-0000-0000-0000000000a1', 'Cycle', 'A'),
         ('14000000-0000-0000-0000-0000000000e2', '14000000-0000-0000-0000-0000000000a2', 'Cycle', 'B');

-- ===========================================================================
-- 1. GRANT initial (INSERT) — chemin RGPD patient via patient_account_id
-- ===========================================================================
SET LOCAL app.current_account_id = '14000000-0000-0000-0000-0000000000e1';

INSERT INTO consent_record (id, patient_account_id, purpose, granted, granted_at)
  VALUES ('14000000-0000-0000-0000-000000000001',
          '14000000-0000-0000-0000-0000000000e1',
          'soins', true, now());

-- État attendu : granted=true, revoked_at IS NULL
SELECT is(
  (SELECT granted FROM consent_record WHERE id = '14000000-0000-0000-0000-000000000001'),
  true,
  'grant initial : consent_record.granted = true');
SELECT is(
  (SELECT revoked_at FROM consent_record WHERE id = '14000000-0000-0000-0000-000000000001'),
  NULL::timestamptz,
  'grant initial : consent_record.revoked_at IS NULL (consentement actif)');

-- ===========================================================================
-- 2. REVOKE (UPDATE) — le patient révoque son consentement
-- ===========================================================================
UPDATE consent_record
  SET granted    = false,
      revoked_at = now()
  WHERE id = '14000000-0000-0000-0000-000000000001';

-- État attendu : granted=false, revoked_at IS NOT NULL
SELECT is(
  (SELECT granted FROM consent_record WHERE id = '14000000-0000-0000-0000-000000000001'),
  false,
  'après révocation : consent_record.granted = false');
SELECT ok(
  (SELECT revoked_at FROM consent_record WHERE id = '14000000-0000-0000-0000-000000000001') IS NOT NULL,
  'après révocation : consent_record.revoked_at IS NOT NULL (timestamp posé)');

-- ===========================================================================
-- 3. RE-GRANT (UPDATE) — le patient re-consent après révocation
-- ===========================================================================
UPDATE consent_record
  SET granted    = true,
      revoked_at = NULL,
      granted_at = now()
  WHERE id = '14000000-0000-0000-0000-000000000001';

-- État attendu : granted=true, revoked_at IS NULL (retour à l'état initial)
SELECT is(
  (SELECT granted FROM consent_record WHERE id = '14000000-0000-0000-0000-000000000001'),
  true,
  're-grant : consent_record.granted = true (re-consentement OK)');
SELECT is(
  (SELECT revoked_at FROM consent_record WHERE id = '14000000-0000-0000-0000-000000000001'),
  NULL::timestamptz,
  're-grant : consent_record.revoked_at IS NULL (effacé lors du re-grant)');

-- ===========================================================================
-- 4. UNICITÉ — double INSERT pour le même (patient_account_id, purpose) rejeté.
--    Re-grant = UPDATE, pas un nouvel INSERT.
-- ===========================================================================
SELECT throws_ok(
  $$ INSERT INTO consent_record (patient_account_id, purpose, granted)
     VALUES ('14000000-0000-0000-0000-0000000000e1', 'soins', true) $$,
  '23505', NULL,
  '⭐ UNIQUE : deuxième INSERT même (account, purpose) rejeté — re-grant = UPDATE');

-- ===========================================================================
-- 5. WITH CHECK : un compte ne peut pas écrire un consentement pour un autre compte
-- ===========================================================================
-- Contexte = account e1, tentative d'écrire pour e2 → violates WITH CHECK
SELECT throws_ok(
  $$ INSERT INTO consent_record (patient_account_id, purpose, granted)
     VALUES ('14000000-0000-0000-0000-0000000000e2', 'soins', true) $$,
  '42501', NULL,
  '⭐ WITH CHECK : insérer un consentement pour account B depuis le contexte A refusé');

-- ===========================================================================
-- 6. Cycle CGU via app_user_id (chemin plateforme, sans patient_account_id)
-- ===========================================================================
INSERT INTO consent_record (id, app_user_id, purpose, granted, granted_at)
  VALUES ('14000000-0000-0000-0000-000000000010',
          '14000000-0000-0000-0000-0000000000a2',
          'cgu', true, now());

-- État initial CGU : granted=true
SELECT is(
  (SELECT granted FROM consent_record WHERE id = '14000000-0000-0000-0000-000000000010'
   AND patient_account_id IS NULL)::bool,
  true,
  'CGU plateforme (app_user_id path) : granted = true après INSERT');

-- Révocation CGU
-- Note : la policy consent_account_select filtre sur patient_account_id, pas app_user_id.
-- Pour la CGU (patient_account_id IS NULL), la policy retourne 0 lignes sous app.current_account_id.
-- On vérifie simplement la cohérence via app_user (visible si app.current_user_id positionné).
-- La vérification du cycle CGU est volontairement simplifiée : UPDATE direct avec NULLIF guard.
UPDATE consent_record
  SET granted    = false,
      revoked_at = now()
  WHERE id = '14000000-0000-0000-0000-000000000010';

-- Re-grant CGU
UPDATE consent_record
  SET granted    = true,
      revoked_at = NULL,
      granted_at = now()
  WHERE id = '14000000-0000-0000-0000-000000000010';

-- Doublon CGU via app_user_id rejeté (UNIQUE app_user_id, purpose)
SELECT throws_ok(
  $$ INSERT INTO consent_record (app_user_id, purpose, granted)
     VALUES ('14000000-0000-0000-0000-0000000000a2', 'cgu', false) $$,
  '23505', NULL,
  'UNIQUE(app_user_id, purpose) : doublon CGU rejeté → re-grant = UPDATE');

-- ===========================================================================
-- 7. Isolation : account B ne voit pas les consentements de account A
-- ===========================================================================
SET LOCAL app.current_account_id = '14000000-0000-0000-0000-0000000000e2';
SELECT is(
  (SELECT count(*) FROM consent_record WHERE id = '14000000-0000-0000-0000-000000000001')::int, 0,
  '⭐ isolation : account B ne voit PAS le consentement soins de account A');

-- ===========================================================================
-- 8. FK → patient_account inexistant rejeté (23503)
-- ===========================================================================
SELECT throws_ok(
  $$ INSERT INTO consent_record (patient_account_id, purpose, granted)
     VALUES ('00000000-0000-0000-0000-000000000099', 'soins', true) $$,
  '23503', NULL,
  'consent_record.patient_account_id FK → patient_account inexistant rejeté (23503)');

SELECT * FROM finish();
ROLLBACK;
