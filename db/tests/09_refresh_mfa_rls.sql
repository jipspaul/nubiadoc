-- 09_refresh_mfa_rls.sql — RLS isolation refresh_token + mfa_enrollment (issue #719).
-- Vérifie : fail-closed, non-fuite inter-user, unicité token_hash, contraintes FK.
-- Tourne sous nubia_app (NOSUPERUSER, NOBYPASSRLS) — GUC app.current_user_id scopé.
BEGIN;
SELECT * FROM no_plan();

-- ===========================================================================
-- Fixtures : deux utilisateurs platform.
-- INSERT ouvert (policy user_app_insert WITH CHECK (true) — pas de GUC requis).
-- ===========================================================================
INSERT INTO app_user (id, email, password_hash, kind)
  VALUES ('c0000000-0000-0000-0000-0000000000a1', 'rls.token.a@example.test', '$argon2id$fixture', 'patient');
INSERT INTO app_user (id, email, password_hash, kind)
  VALUES ('c0000000-0000-0000-0000-0000000000a2', 'rls.token.b@example.test', '$argon2id$fixture', 'pro');

-- refresh_token : un token par user.
-- INSERT ouvert (policy token_user_insert WITH CHECK (true) — pas de GUC requis).
INSERT INTO refresh_token (id, app_user_id, token_hash, expires_at)
  VALUES ('c0000000-0000-0000-0000-000000000001',
          'c0000000-0000-0000-0000-0000000000a1',
          'sha256_token_user_a',
          now() + interval '30 days');
INSERT INTO refresh_token (id, app_user_id, token_hash, expires_at)
  VALUES ('c0000000-0000-0000-0000-000000000002',
          'c0000000-0000-0000-0000-0000000000a2',
          'sha256_token_user_b',
          now() + interval '30 days');

-- ===========================================================================
-- 1. refresh_token : FAIL-CLOSED (sans GUC → 0 ligne visible)
-- ===========================================================================
RESET app.current_user_id;
SELECT is(
  (SELECT count(*) FROM refresh_token
   WHERE id IN ('c0000000-0000-0000-0000-000000000001',
                'c0000000-0000-0000-0000-000000000002'))::int, 0,
  '⭐ fail-closed refresh_token : aucun token visible sans app.current_user_id');

-- ===========================================================================
-- 2. refresh_token : ISOLATION inter-user
-- ===========================================================================
SET LOCAL app.current_user_id = 'c0000000-0000-0000-0000-0000000000a1';
SELECT is(
  (SELECT count(*) FROM refresh_token
   WHERE id IN ('c0000000-0000-0000-0000-000000000001',
                'c0000000-0000-0000-0000-000000000002'))::int, 1,
  'refresh_token contexte user A : 1 token visible (le sien)');
SELECT is(
  (SELECT count(*) FROM refresh_token WHERE id = 'c0000000-0000-0000-0000-000000000002')::int, 0,
  '⭐ non-fuite refresh_token : user A ne voit PAS le token de user B');

SET LOCAL app.current_user_id = 'c0000000-0000-0000-0000-0000000000a2';
SELECT is(
  (SELECT count(*) FROM refresh_token
   WHERE id IN ('c0000000-0000-0000-0000-000000000001',
                'c0000000-0000-0000-0000-000000000002'))::int, 1,
  'refresh_token contexte user B : 1 token visible (le sien)');
SELECT is(
  (SELECT count(*) FROM refresh_token WHERE id = 'c0000000-0000-0000-0000-000000000001')::int, 0,
  '⭐ non-fuite refresh_token : user B ne voit PAS le token de user A');

-- ===========================================================================
-- 3. refresh_token : UNICITÉ token_hash (erreur 23505)
-- ===========================================================================
SELECT throws_ok(
  $$ INSERT INTO refresh_token (app_user_id, token_hash, expires_at)
     VALUES ('c0000000-0000-0000-0000-0000000000a2',
             'sha256_token_user_a',
             now() + interval '1 day') $$,
  '23505', NULL,
  'refresh_token.token_hash UNIQUE → doublon refusé (23505)');

-- ===========================================================================
-- 4. refresh_token : FK → app_user (erreur 23503 si user inexistant)
-- ===========================================================================
SELECT throws_ok(
  $$ INSERT INTO refresh_token (app_user_id, token_hash, expires_at)
     VALUES ('00000000-0000-0000-0000-000000000099',
             'sha256_orphan',
             now() + interval '1 day') $$,
  '23503', NULL,
  'refresh_token.app_user_id FK → app_user.id (23503 si user inexistant)');

-- ===========================================================================
-- 5. mfa_enrollment fixtures
-- INSERT ouvert (policy mfa_user_insert WITH CHECK (true)).
-- ===========================================================================
INSERT INTO mfa_enrollment (id, app_user_id, secret_ciphertext, secret_key_ref, method, verified)
  VALUES ('c0000000-0000-0000-0000-000000000010',
          'c0000000-0000-0000-0000-0000000000a1',
          '\x0102'::bytea, 'key/ref/a', 'totp', false);
INSERT INTO mfa_enrollment (id, app_user_id, secret_ciphertext, secret_key_ref, method, verified)
  VALUES ('c0000000-0000-0000-0000-000000000011',
          'c0000000-0000-0000-0000-0000000000a2',
          '\x0304'::bytea, 'key/ref/b', 'totp', false);

-- ===========================================================================
-- 6. mfa_enrollment : FAIL-CLOSED
-- ===========================================================================
RESET app.current_user_id;
SELECT is(
  (SELECT count(*) FROM mfa_enrollment
   WHERE id IN ('c0000000-0000-0000-0000-000000000010',
                'c0000000-0000-0000-0000-000000000011'))::int, 0,
  '⭐ fail-closed mfa_enrollment : aucun enrôlement visible sans app.current_user_id');

-- ===========================================================================
-- 7. mfa_enrollment : ISOLATION inter-user
-- ===========================================================================
SET LOCAL app.current_user_id = 'c0000000-0000-0000-0000-0000000000a1';
SELECT is(
  (SELECT count(*) FROM mfa_enrollment
   WHERE id IN ('c0000000-0000-0000-0000-000000000010',
                'c0000000-0000-0000-0000-000000000011'))::int, 1,
  'mfa_enrollment contexte user A : 1 enrôlement visible (le sien)');
SELECT is(
  (SELECT count(*) FROM mfa_enrollment WHERE id = 'c0000000-0000-0000-0000-000000000011')::int, 0,
  '⭐ non-fuite mfa_enrollment : user A ne voit PAS l''enrôlement de user B');

SET LOCAL app.current_user_id = 'c0000000-0000-0000-0000-0000000000a2';
SELECT is(
  (SELECT count(*) FROM mfa_enrollment
   WHERE id IN ('c0000000-0000-0000-0000-000000000010',
                'c0000000-0000-0000-0000-000000000011'))::int, 1,
  'mfa_enrollment contexte user B : 1 enrôlement visible (le sien)');
SELECT is(
  (SELECT count(*) FROM mfa_enrollment WHERE id = 'c0000000-0000-0000-0000-000000000010')::int, 0,
  '⭐ non-fuite mfa_enrollment : user B ne voit PAS l''enrôlement de user A');

-- ===========================================================================
-- 8. mfa_enrollment : FK → app_user (erreur 23503 si user inexistant)
-- ===========================================================================
SELECT throws_ok(
  $$ INSERT INTO mfa_enrollment (app_user_id, secret_ciphertext, secret_key_ref, method)
     VALUES ('00000000-0000-0000-0000-000000000099',
             '\x01'::bytea, 'k', 'totp') $$,
  '23503', NULL,
  'mfa_enrollment.app_user_id FK → app_user.id (23503 si user inexistant)');

SELECT * FROM finish();
ROLLBACK;
