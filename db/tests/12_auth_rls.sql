-- 12_auth_rls.sql — RLS plateforme auth : isolation cross-user sur toutes les tables auth.
-- Couvre le scénario « session utilisateur » complet : sous un contexte GUC user/account,
-- aucune donnée d'un autre utilisateur n'est visible (fail-closed + isolation sur 6 tables).
-- Complète 03_rls.sql (cabinet), 09_refresh_mfa_rls.sql, 10_consent_notification_rls.sql
-- qui testent chaque table séparément. Ici : test unifié cross-table.
-- pgTAP, exécuté par pg_prove sous nubia_app (NOSUPERUSER, NOBYPASSRLS).
BEGIN;
SELECT * FROM no_plan();

-- ===========================================================================
-- 0. Rôle d'exécution : bien nubia_app, non-superuser, non-bypass.
-- ===========================================================================
SELECT is(current_user::text, 'nubia_app',
  'tests RLS auth tournent sous nubia_app (non-superuser)');
SELECT ok(NOT (SELECT rolsuper FROM pg_roles WHERE rolname = 'nubia_app'),
  'nubia_app est NOSUPERUSER (RLS non bypassée)');
SELECT ok(NOT (SELECT rolbypassrls FROM pg_roles WHERE rolname = 'nubia_app'),
  'nubia_app est NOBYPASSRLS (RLS effective sur toutes les tables)');

-- ===========================================================================
-- 1. Garde-fou : toutes les tables auth platform ont RLS + FORCE activés.
--    (Détection rapide de toute régression d'activation lors d'une future migration.)
-- ===========================================================================
SELECT ok((SELECT relrowsecurity FROM pg_class WHERE relname = 'app_user'),
  'app_user : ENABLE ROW LEVEL SECURITY (0045)');
SELECT ok((SELECT relforcerowsecurity FROM pg_class WHERE relname = 'app_user'),
  'app_user : FORCE ROW LEVEL SECURITY (0045)');

SELECT ok((SELECT relrowsecurity FROM pg_class WHERE relname = 'patient_account'),
  'patient_account : ENABLE ROW LEVEL SECURITY (0045)');
SELECT ok((SELECT relforcerowsecurity FROM pg_class WHERE relname = 'patient_account'),
  'patient_account : FORCE ROW LEVEL SECURITY (0045)');

SELECT ok((SELECT relrowsecurity FROM pg_class WHERE relname = 'refresh_token'),
  'refresh_token : ENABLE ROW LEVEL SECURITY (0047)');
SELECT ok((SELECT relforcerowsecurity FROM pg_class WHERE relname = 'refresh_token'),
  'refresh_token : FORCE ROW LEVEL SECURITY (0047)');

SELECT ok((SELECT relrowsecurity FROM pg_class WHERE relname = 'mfa_enrollment'),
  'mfa_enrollment : ENABLE ROW LEVEL SECURITY (0047)');
SELECT ok((SELECT relforcerowsecurity FROM pg_class WHERE relname = 'mfa_enrollment'),
  'mfa_enrollment : FORCE ROW LEVEL SECURITY (0047)');

SELECT ok((SELECT relrowsecurity FROM pg_class WHERE relname = 'consent_record'),
  'consent_record : ENABLE ROW LEVEL SECURITY (0048)');
SELECT ok((SELECT relforcerowsecurity FROM pg_class WHERE relname = 'consent_record'),
  'consent_record : FORCE ROW LEVEL SECURITY (0048)');

SELECT ok((SELECT relrowsecurity FROM pg_class WHERE relname = 'notification_preference'),
  'notification_preference : ENABLE ROW LEVEL SECURITY (0049)');
SELECT ok((SELECT relforcerowsecurity FROM pg_class WHERE relname = 'notification_preference'),
  'notification_preference : FORCE ROW LEVEL SECURITY (0049)');

-- ===========================================================================
-- 2. Fixtures : deux utilisateurs (user A et user B), chacun avec son jeu
--    complet de données auth platform.
--    INSERT ouvert (policies *_app_insert WITH CHECK(true)).
-- ===========================================================================
INSERT INTO app_user (id, email, password_hash, kind)
  VALUES ('e0000000-0000-0000-0000-0000000000a1', 'auth.rls.a@example.test', '$argon2id$fixture', 'patient'),
         ('e0000000-0000-0000-0000-0000000000a2', 'auth.rls.b@example.test', '$argon2id$fixture', 'patient');

INSERT INTO patient_account (id, app_user_id, first_name, last_name)
  VALUES ('e0000000-0000-0000-0000-0000000000e1', 'e0000000-0000-0000-0000-0000000000a1', 'Alpha', 'A'),
         ('e0000000-0000-0000-0000-0000000000e2', 'e0000000-0000-0000-0000-0000000000a2', 'Beta',  'B');

-- refresh_token (INSERT ouvert : policy token_user_insert WITH CHECK(true))
INSERT INTO refresh_token (id, app_user_id, token_hash, expires_at)
  VALUES ('e0000000-0000-0000-0000-000000000001',
          'e0000000-0000-0000-0000-0000000000a1', 'sha_rls_12_a', now() + interval '30 days'),
         ('e0000000-0000-0000-0000-000000000002',
          'e0000000-0000-0000-0000-0000000000a2', 'sha_rls_12_b', now() + interval '30 days');

-- mfa_enrollment (INSERT ouvert : policy mfa_user_insert WITH CHECK(true))
INSERT INTO mfa_enrollment (id, app_user_id, secret_ciphertext, secret_key_ref, method, verified)
  VALUES ('e0000000-0000-0000-0000-000000000010',
          'e0000000-0000-0000-0000-0000000000a1', '\xaabb'::bytea, 'k/rls/a', 'totp', false),
         ('e0000000-0000-0000-0000-000000000011',
          'e0000000-0000-0000-0000-0000000000a2', '\xccdd'::bytea, 'k/rls/b', 'totp', false);

-- consent_record via patient_account_id (INSERT ouvert : policy consent_account_insert WITH CHECK(true))
INSERT INTO consent_record (id, patient_account_id, purpose, granted)
  VALUES ('e0000000-0000-0000-0000-000000000020',
          'e0000000-0000-0000-0000-0000000000e1', 'soins', true),
         ('e0000000-0000-0000-0000-000000000021',
          'e0000000-0000-0000-0000-0000000000e2', 'soins', true);

-- notification_preference (INSERT borné par GUC : policy notif_pref_account_insert WITH CHECK)
SET LOCAL app.current_account_id = 'e0000000-0000-0000-0000-0000000000e1';
INSERT INTO notification_preference (id, patient_account_id, channel, enabled, type)
  VALUES ('e0000000-0000-0000-0000-000000000030',
          'e0000000-0000-0000-0000-0000000000e1', 'email', true, 'rdv');
SET LOCAL app.current_account_id = 'e0000000-0000-0000-0000-0000000000e2';
INSERT INTO notification_preference (id, patient_account_id, channel, enabled, type)
  VALUES ('e0000000-0000-0000-0000-000000000031',
          'e0000000-0000-0000-0000-0000000000e2', 'email', true, 'rdv');

-- ===========================================================================
-- 3. FAIL-CLOSED : sans GUC positionné → 0 ligne visible sur toutes les tables.
-- ===========================================================================
RESET app.current_user_id;
RESET app.current_account_id;

SELECT is(
  (SELECT count(*) FROM app_user
   WHERE id IN ('e0000000-0000-0000-0000-0000000000a1',
                'e0000000-0000-0000-0000-0000000000a2'))::int, 0,
  '⭐ fail-closed app_user : 0 ligne visible sans GUC');
SELECT is(
  (SELECT count(*) FROM patient_account
   WHERE id IN ('e0000000-0000-0000-0000-0000000000e1',
                'e0000000-0000-0000-0000-0000000000e2'))::int, 0,
  '⭐ fail-closed patient_account : 0 ligne visible sans GUC');
SELECT is(
  (SELECT count(*) FROM refresh_token
   WHERE id IN ('e0000000-0000-0000-0000-000000000001',
                'e0000000-0000-0000-0000-000000000002'))::int, 0,
  '⭐ fail-closed refresh_token : 0 ligne visible sans GUC');
SELECT is(
  (SELECT count(*) FROM mfa_enrollment
   WHERE id IN ('e0000000-0000-0000-0000-000000000010',
                'e0000000-0000-0000-0000-000000000011'))::int, 0,
  '⭐ fail-closed mfa_enrollment : 0 ligne visible sans GUC');
SELECT is(
  (SELECT count(*) FROM consent_record
   WHERE id IN ('e0000000-0000-0000-0000-000000000020',
                'e0000000-0000-0000-0000-000000000021'))::int, 0,
  '⭐ fail-closed consent_record : 0 ligne visible sans GUC');
SELECT is(
  (SELECT count(*) FROM notification_preference
   WHERE id IN ('e0000000-0000-0000-0000-000000000030',
                'e0000000-0000-0000-0000-000000000031'))::int, 0,
  '⭐ fail-closed notification_preference : 0 ligne visible sans GUC');

-- ===========================================================================
-- 4. Session user A : voit UNIQUEMENT ses propres données (toutes tables).
-- ===========================================================================
SET LOCAL app.current_user_id    = 'e0000000-0000-0000-0000-0000000000a1';
SET LOCAL app.current_account_id = 'e0000000-0000-0000-0000-0000000000e1';

-- app_user
SELECT is(
  (SELECT count(*) FROM app_user
   WHERE id IN ('e0000000-0000-0000-0000-0000000000a1',
                'e0000000-0000-0000-0000-0000000000a2'))::int, 1,
  'session A — app_user : 1 ligne visible (la sienne)');
SELECT is(
  (SELECT count(*) FROM app_user WHERE id = 'e0000000-0000-0000-0000-0000000000a2')::int, 0,
  '⭐ session A — non-fuite app_user : user A ne voit PAS user B');

-- refresh_token
SELECT is(
  (SELECT count(*) FROM refresh_token
   WHERE id IN ('e0000000-0000-0000-0000-000000000001',
                'e0000000-0000-0000-0000-000000000002'))::int, 1,
  'session A — refresh_token : 1 ligne visible (le sien)');
SELECT is(
  (SELECT count(*) FROM refresh_token WHERE id = 'e0000000-0000-0000-0000-000000000002')::int, 0,
  '⭐ session A — non-fuite refresh_token : user A ne voit PAS le token de user B');

-- mfa_enrollment
SELECT is(
  (SELECT count(*) FROM mfa_enrollment
   WHERE id IN ('e0000000-0000-0000-0000-000000000010',
                'e0000000-0000-0000-0000-000000000011'))::int, 1,
  'session A — mfa_enrollment : 1 ligne visible (le sien)');
SELECT is(
  (SELECT count(*) FROM mfa_enrollment WHERE id = 'e0000000-0000-0000-0000-000000000011')::int, 0,
  '⭐ session A — non-fuite mfa_enrollment : user A ne voit PAS l''enrôlement de user B');

-- patient_account
SELECT is(
  (SELECT count(*) FROM patient_account
   WHERE id IN ('e0000000-0000-0000-0000-0000000000e1',
                'e0000000-0000-0000-0000-0000000000e2'))::int, 1,
  'session A — patient_account : 1 ligne visible (le sien)');
SELECT is(
  (SELECT count(*) FROM patient_account WHERE id = 'e0000000-0000-0000-0000-0000000000e2')::int, 0,
  '⭐ session A — non-fuite patient_account : account A ne voit PAS account B');

-- consent_record
SELECT is(
  (SELECT count(*) FROM consent_record
   WHERE id IN ('e0000000-0000-0000-0000-000000000020',
                'e0000000-0000-0000-0000-000000000021'))::int, 1,
  'session A — consent_record : 1 ligne visible (la sienne)');
SELECT is(
  (SELECT count(*) FROM consent_record WHERE id = 'e0000000-0000-0000-0000-000000000021')::int, 0,
  '⭐ session A — non-fuite consent_record : account A ne voit PAS les consentements de B');

-- notification_preference
SELECT is(
  (SELECT count(*) FROM notification_preference
   WHERE id IN ('e0000000-0000-0000-0000-000000000030',
                'e0000000-0000-0000-0000-000000000031'))::int, 1,
  'session A — notification_preference : 1 ligne visible (la sienne)');
SELECT is(
  (SELECT count(*) FROM notification_preference
   WHERE id = 'e0000000-0000-0000-0000-000000000031')::int, 0,
  '⭐ session A — non-fuite notification_preference : account A ne voit PAS les préférences de B');

-- ===========================================================================
-- 5. Bascule vers session user B : voit UNIQUEMENT les données de B, pas de A.
-- ===========================================================================
SET LOCAL app.current_user_id    = 'e0000000-0000-0000-0000-0000000000a2';
SET LOCAL app.current_account_id = 'e0000000-0000-0000-0000-0000000000e2';

SELECT is(
  (SELECT count(*) FROM app_user WHERE id = 'e0000000-0000-0000-0000-0000000000a1')::int, 0,
  '⭐ session B — non-fuite app_user : user B ne voit PAS user A après bascule de contexte');
SELECT is(
  (SELECT count(*) FROM refresh_token WHERE id = 'e0000000-0000-0000-0000-000000000001')::int, 0,
  '⭐ session B — non-fuite refresh_token : user B ne voit PAS le token de user A');
SELECT is(
  (SELECT count(*) FROM mfa_enrollment WHERE id = 'e0000000-0000-0000-0000-000000000010')::int, 0,
  '⭐ session B — non-fuite mfa_enrollment : user B ne voit PAS l''enrôlement de user A');
SELECT is(
  (SELECT count(*) FROM patient_account WHERE id = 'e0000000-0000-0000-0000-0000000000e1')::int, 0,
  '⭐ session B — non-fuite patient_account : account B ne voit PAS account A');
SELECT is(
  (SELECT count(*) FROM consent_record WHERE id = 'e0000000-0000-0000-0000-000000000020')::int, 0,
  '⭐ session B — non-fuite consent_record : account B ne voit PAS les consentements de A');
SELECT is(
  (SELECT count(*) FROM notification_preference
   WHERE id = 'e0000000-0000-0000-0000-000000000030')::int, 0,
  '⭐ session B — non-fuite notification_preference : account B ne voit PAS les préférences de A');

-- Et B voit bien ses propres données :
SELECT is(
  (SELECT count(*) FROM app_user WHERE id = 'e0000000-0000-0000-0000-0000000000a2')::int, 1,
  'session B — app_user : user B voit bien sa propre ligne');
SELECT is(
  (SELECT count(*) FROM refresh_token WHERE id = 'e0000000-0000-0000-0000-000000000002')::int, 1,
  'session B — refresh_token : user B voit bien son token');

SELECT * FROM finish();
ROLLBACK;
