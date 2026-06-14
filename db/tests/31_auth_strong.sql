-- 31_auth_strong.sql — TDD audit pgTAP : Auth tables (refresh_token, mfa_*, password_reset).
-- Issue #1830 — T-DB-D004.
--
-- Invariants couverts :
--   RT1.  refresh_token : FORCE ROW LEVEL SECURITY activée (0047).
--   RT2.  refresh_token : token expiré insérable (pas de CHECK DB — responsabilité applicative).
--   RT3.  refresh_token : token expiré visible via RLS (RLS ne filtre pas expires_at).
--   RT4.  refresh_token : soft-revoke — revoked_at IS NOT NULL détecte un token révoqué.
--   RT5.  refresh_token : WRITE isolation — UPDATE cross-user → 0 lignes affectées.
--   MFA1. mfa_enrollment : FORCE ROW LEVEL SECURITY activée (0047).
--   MFA2. mfa_enrollment : verified flag false → true visible sous le bon user_id.
--   MFA3. mfa_enrollment : DELETE cross-user → 0 lignes affectées (WRITE isolation).
--   PRT1. app_user : password_reset_token + password_reset_expires_at setables (reset request).
--   PRT2. app_user : reset « consommé » = token effacé (NULL après usage simulé).
--   AL1.  account_auth_select (0069) : fail-closed sans app.current_login_user_id.
--   AL2.  account_auth_select (0069) : GUC login → voit son propre patient_account.
--   AL3.  account_auth_select (0069) : GUC login user B → ne voit PAS le compte de user A.
--
-- Exécuté par pg_prove sous nubia_app (NOSUPERUSER, NOBYPASSRLS).
-- Fixtures auto-containées (BEGIN…ROLLBACK). Préfixe UUID 18300000.
BEGIN;
SELECT * FROM no_plan();

-- ===========================================================================
-- Pré-condition : exécuté sous nubia_app
-- ===========================================================================
SELECT is(current_user::text, 'nubia_app',
    '⭐ tests auth_strong exécutés sous nubia_app');

-- ===========================================================================
-- Fixtures : deux utilisateurs + deux comptes patient.
-- INSERTs ouverts (policies *_insert WITH CHECK(true) — pas de GUC requis).
-- Préfixe UUID 18300000 (propre à cette suite, issue #1830).
-- ===========================================================================
INSERT INTO app_user (id, email, password_hash, kind)
    VALUES ('18300000-0000-0000-0000-0000000000a1', 'auth.strong.a@example.test', '$argon2id$fixture', 'patient');
INSERT INTO app_user (id, email, password_hash, kind)
    VALUES ('18300000-0000-0000-0000-0000000000a2', 'auth.strong.b@example.test', '$argon2id$fixture', 'patient');

INSERT INTO patient_account (id, app_user_id, first_name, last_name)
    VALUES ('18300000-0000-0000-0000-0000000000e1', '18300000-0000-0000-0000-0000000000a1', 'Auth', 'StrongA');
INSERT INTO patient_account (id, app_user_id, first_name, last_name)
    VALUES ('18300000-0000-0000-0000-0000000000e2', '18300000-0000-0000-0000-0000000000a2', 'Auth', 'StrongB');

-- refresh_token actif pour user A
INSERT INTO refresh_token (id, app_user_id, token_hash, expires_at)
    VALUES ('18300000-0000-0000-0000-000000000001',
            '18300000-0000-0000-0000-0000000000a1',
            'sha256_strong_a_active',
            now() + interval '30 days');

-- refresh_token actif pour user B
INSERT INTO refresh_token (id, app_user_id, token_hash, expires_at)
    VALUES ('18300000-0000-0000-0000-000000000002',
            '18300000-0000-0000-0000-0000000000a2',
            'sha256_strong_b_active',
            now() + interval '30 days');

-- mfa_enrollment non vérifié pour user A
INSERT INTO mfa_enrollment (id, app_user_id, secret_ciphertext, secret_key_ref, method, verified)
    VALUES ('18300000-0000-0000-0000-000000000010',
            '18300000-0000-0000-0000-0000000000a1',
            '\x0102'::bytea, 'kms/ref/1830a', 'totp', false);

-- mfa_enrollment pour user B
INSERT INTO mfa_enrollment (id, app_user_id, secret_ciphertext, secret_key_ref, method, verified)
    VALUES ('18300000-0000-0000-0000-000000000011',
            '18300000-0000-0000-0000-0000000000a2',
            '\x0304'::bytea, 'kms/ref/1830b', 'totp', false);

-- ===========================================================================
-- RT1. refresh_token : FORCE ROW LEVEL SECURITY activée (0047).
-- ===========================================================================
SELECT ok(
    (SELECT relforcerowsecurity FROM pg_class WHERE relname = 'refresh_token'),
    'RT1 refresh_token : FORCE ROW LEVEL SECURITY activée (0047)');

-- ===========================================================================
-- MFA1. mfa_enrollment : FORCE ROW LEVEL SECURITY activée (0047).
-- ===========================================================================
SELECT ok(
    (SELECT relforcerowsecurity FROM pg_class WHERE relname = 'mfa_enrollment'),
    'MFA1 mfa_enrollment : FORCE ROW LEVEL SECURITY activée (0047)');

-- ===========================================================================
-- RT2. Token expiré : insérable (pas de CHECK DB sur expires_at).
-- La base n'empêche pas l'insertion d'un token déjà expiré — c'est l'app
-- qui valide expires_at < now() au moment de l'usage.
-- ===========================================================================
SELECT lives_ok(
    $$ INSERT INTO refresh_token (id, app_user_id, token_hash, expires_at)
       VALUES ('18300000-0000-0000-0000-000000000003',
               '18300000-0000-0000-0000-0000000000a1',
               'sha256_strong_a_expired',
               now() - interval '1 hour') $$,
    'RT2 token expiré insérable (pas de CHECK DB sur expires_at)');

-- ===========================================================================
-- RT3. Token expiré visible via RLS (RLS ne filtre pas expires_at).
-- C'est l'applicatif qui lit expires_at et décide de rejeter le token.
-- ===========================================================================
SET LOCAL app.current_user_id = '18300000-0000-0000-0000-0000000000a1';
SELECT is(
    (SELECT count(*)::int FROM refresh_token
     WHERE id = '18300000-0000-0000-0000-000000000003'
       AND expires_at < now()),
    1,
    '⭐ RT3 token expiré visible via RLS (filtrage applicatif, pas DB)');

-- ===========================================================================
-- RT4. Soft-revoke : revoked_at IS NOT NULL détecte un token révoqué.
-- L'UPDATE est autorisé sous app.current_user_id = propriétaire du token.
-- ===========================================================================
UPDATE refresh_token
   SET revoked_at = now()
 WHERE id = '18300000-0000-0000-0000-000000000001';

SELECT ok(
    (SELECT revoked_at IS NOT NULL FROM refresh_token
     WHERE id = '18300000-0000-0000-0000-000000000001'),
    '⭐ RT4 soft-revoke : revoked_at IS NOT NULL après révocation');

-- ===========================================================================
-- RT5. WRITE isolation refresh_token : UPDATE cross-user → 0 lignes affectées.
-- Contexte user A tente de révoquer le token de user B.
-- La policy token_user_update bloque silencieusement (0 lignes, pas d'erreur).
-- ===========================================================================
SET LOCAL app.current_user_id = '18300000-0000-0000-0000-0000000000a1';
UPDATE refresh_token
   SET revoked_at = now()
 WHERE id = '18300000-0000-0000-0000-000000000002';

-- Vérifier depuis le contexte user B que son token est intact.
SET LOCAL app.current_user_id = '18300000-0000-0000-0000-0000000000a2';
SELECT is(
    (SELECT revoked_at FROM refresh_token
     WHERE id = '18300000-0000-0000-0000-000000000002'),
    NULL::timestamptz,
    '⭐ RT5 WRITE isolation refresh_token : user A ne peut pas révoquer le token de user B');

-- ===========================================================================
-- MFA2. verified flag false → true : transition visible sous le bon user_id.
-- ===========================================================================
SET LOCAL app.current_user_id = '18300000-0000-0000-0000-0000000000a1';
UPDATE mfa_enrollment
   SET verified = true
 WHERE id = '18300000-0000-0000-0000-000000000010';

SELECT is(
    (SELECT verified FROM mfa_enrollment WHERE id = '18300000-0000-0000-0000-000000000010'),
    true,
    'MFA2 verified false → true : transition visible sous le bon user_id');

-- ===========================================================================
-- MFA3. DELETE cross-user mfa_enrollment → 0 lignes affectées.
-- Contexte user A tente de supprimer l'enrollment de user B.
-- La policy mfa_user_delete bloque silencieusement.
-- ===========================================================================
SET LOCAL app.current_user_id = '18300000-0000-0000-0000-0000000000a1';
DELETE FROM mfa_enrollment WHERE id = '18300000-0000-0000-0000-000000000011';

-- Vérifier depuis le contexte user B que son enrollment existe toujours.
SET LOCAL app.current_user_id = '18300000-0000-0000-0000-0000000000a2';
SELECT is(
    (SELECT count(*)::int FROM mfa_enrollment
     WHERE id = '18300000-0000-0000-0000-000000000011'),
    1,
    '⭐ MFA3 DELETE cross-user : enrollment de user B intact après tentative par user A');

-- ===========================================================================
-- PRT1. Password reset request : colonnes setables sur son propre app_user.
-- La policy user_self_update permet de modifier sa propre ligne quand
-- app.current_user_id = id de l'utilisateur.
-- ===========================================================================
SET LOCAL app.current_user_id = '18300000-0000-0000-0000-0000000000a1';
UPDATE app_user
   SET password_reset_token     = 'reset_token_fixture_1830',
       password_reset_expires_at = now() + interval '15 minutes'
 WHERE id = '18300000-0000-0000-0000-0000000000a1';

SELECT ok(
    (SELECT password_reset_token IS NOT NULL AND password_reset_expires_at > now()
       FROM app_user WHERE id = '18300000-0000-0000-0000-0000000000a1'),
    'PRT1 password_reset_token + expires_at setables (demande de reset)');

-- ===========================================================================
-- PRT2. Password reset consommé : token effacé (NULL) après usage simulé.
-- ===========================================================================
UPDATE app_user
   SET password_reset_token     = NULL,
       password_reset_expires_at = NULL
 WHERE id = '18300000-0000-0000-0000-0000000000a1';

SELECT is(
    (SELECT password_reset_token FROM app_user WHERE id = '18300000-0000-0000-0000-0000000000a1'),
    NULL::text,
    'PRT2 password_reset_token effacé à NULL après consommation');

-- ===========================================================================
-- AL1. account_auth_select (0069) : fail-closed sans GUC login.
-- Reset des GUC user + account : les deux familles de policies patient_account
-- sont fail-closed → 0 ligne visible.
-- app.current_login_user_id n'a jamais été positionné dans cette transaction.
-- ===========================================================================
RESET app.current_account_id;
RESET app.current_user_id;
SELECT is(
    (SELECT count(*)::int FROM patient_account
     WHERE id IN ('18300000-0000-0000-0000-0000000000e1',
                  '18300000-0000-0000-0000-0000000000e2')),
    0,
    '⭐ AL1 fail-closed account_auth_select : 0 ligne sans app.current_login_user_id');

-- ===========================================================================
-- AL2. account_auth_select (0069) : GUC login → voit son propre patient_account.
-- Simule le handler POST /v1/auth/login : set current_login_user_id = user.id,
-- puis récupère l'account_id correspondant.
-- ===========================================================================
SET LOCAL app.current_login_user_id = '18300000-0000-0000-0000-0000000000a1';
SELECT is(
    (SELECT count(*)::int FROM patient_account
     WHERE id = '18300000-0000-0000-0000-0000000000e1'),
    1,
    '⭐ AL2 account_auth_select : GUC login user A → voit son patient_account');

-- ===========================================================================
-- AL3. account_auth_select (0069) : isolation — GUC login user B
-- ne doit PAS exposer le compte de user A (non-fuite inter-user).
-- ===========================================================================
SET LOCAL app.current_login_user_id = '18300000-0000-0000-0000-0000000000a2';
SELECT is(
    (SELECT count(*)::int FROM patient_account
     WHERE id = '18300000-0000-0000-0000-0000000000e1'),
    0,
    '⭐ AL3 isolation account_auth_select : GUC login user B → ne voit PAS le compte de user A');

SELECT * FROM finish();
ROLLBACK;
