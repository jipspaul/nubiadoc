-- 12_auth_rls.sql — RLS comportementale : isolation inter-user + inter-compte (issue #732).
-- Vérifie : nubia_app NOSUPERUSER/NOBYPASSRLS, fail-closed, ⭐ non-fuite READ + WRITE.
-- Complète 03_rls.sql (isolation READ) avec les tests d'isolation WRITE (UPDATE/DELETE).
-- Tourne sous nubia_app (NOSUPERUSER, NOBYPASSRLS).
BEGIN;
SELECT * FROM no_plan();

-- ===========================================================================
-- 0. Rôle : nubia_app doit être NOSUPERUSER + NOBYPASSRLS — sinon RLS inopérante.
-- ===========================================================================
SELECT is(current_user::text, 'nubia_app',
  'tests RLS tournent sous nubia_app');
SELECT ok( NOT (SELECT rolsuper     FROM pg_roles WHERE rolname = 'nubia_app'),
  'nubia_app NOSUPERUSER');
SELECT ok( NOT (SELECT rolbypassrls FROM pg_roles WHERE rolname = 'nubia_app'),
  'nubia_app NOBYPASSRLS (RLS effective)');

-- ===========================================================================
-- Fixtures : deux utilisateurs + deux comptes patient.
-- INSERT ouvert (policies user_app_insert / account_app_insert WITH CHECK(true)).
-- Préfixe 12000000 (hors seed migrations : a/b/c/d/e0000000).
-- ===========================================================================
INSERT INTO app_user (id, email, password_hash, kind)
  VALUES ('12000000-0000-0000-0000-0000000000a1', 'rls.auth.a@example.test', '$argon2id$fixture', 'patient');
INSERT INTO app_user (id, email, password_hash, kind)
  VALUES ('12000000-0000-0000-0000-0000000000a2', 'rls.auth.b@example.test', '$argon2id$fixture', 'patient');

INSERT INTO patient_account (id, app_user_id, first_name, last_name)
  VALUES ('12000000-0000-0000-0000-0000000000e1', '12000000-0000-0000-0000-0000000000a1', 'Auth', 'A');
INSERT INTO patient_account (id, app_user_id, first_name, last_name)
  VALUES ('12000000-0000-0000-0000-0000000000e2', '12000000-0000-0000-0000-0000000000a2', 'Auth', 'B');

-- ===========================================================================
-- 1. app_user : FAIL-CLOSED + isolation READ
-- ===========================================================================
RESET app.current_user_id;
SELECT is(
  (SELECT count(*) FROM app_user
   WHERE id IN ('12000000-0000-0000-0000-0000000000a1',
                '12000000-0000-0000-0000-0000000000a2'))::int, 0,
  '⭐ fail-closed app_user : 0 ligne visible sans app.current_user_id');

SET LOCAL app.current_user_id = '12000000-0000-0000-0000-0000000000a1';
SELECT is(
  (SELECT count(*) FROM app_user
   WHERE id IN ('12000000-0000-0000-0000-0000000000a1',
                '12000000-0000-0000-0000-0000000000a2'))::int, 1,
  'app_user contexte user A : 1 ligne visible (la sienne)');
SELECT is(
  (SELECT count(*) FROM app_user WHERE id = '12000000-0000-0000-0000-0000000000a2')::int, 0,
  '⭐ non-fuite app_user READ : user A ne voit PAS la ligne de user B');

-- ===========================================================================
-- 2. app_user : isolation WRITE — user A ne peut pas modifier la ligne de user B.
--    La policy user_self_update (USING) rend la ligne de B invisible pour A :
--    l'UPDATE affecte 0 lignes sans erreur.
-- ===========================================================================
UPDATE app_user SET status = 'suspended'
 WHERE id = '12000000-0000-0000-0000-0000000000a2';

SET LOCAL app.current_user_id = '12000000-0000-0000-0000-0000000000a2';
SELECT is(
  (SELECT status FROM app_user WHERE id = '12000000-0000-0000-0000-0000000000a2')::text,
  'active',
  '⭐ non-fuite app_user WRITE : user A ne peut pas modifier le statut de user B');

-- ===========================================================================
-- 3. patient_account : FAIL-CLOSED + isolation READ
-- ===========================================================================
RESET app.current_account_id;
SELECT is(
  (SELECT count(*) FROM patient_account
   WHERE id IN ('12000000-0000-0000-0000-0000000000e1',
                '12000000-0000-0000-0000-0000000000e2'))::int, 0,
  '⭐ fail-closed patient_account : 0 ligne visible sans app.current_account_id');

SET LOCAL app.current_account_id = '12000000-0000-0000-0000-0000000000e1';
SELECT is(
  (SELECT count(*) FROM patient_account
   WHERE id IN ('12000000-0000-0000-0000-0000000000e1',
                '12000000-0000-0000-0000-0000000000e2'))::int, 1,
  'patient_account contexte compte A : 1 ligne visible (la sienne)');
SELECT is(
  (SELECT count(*) FROM patient_account WHERE id = '12000000-0000-0000-0000-0000000000e2')::int, 0,
  '⭐ non-fuite patient_account READ : compte A ne voit PAS la ligne de compte B');

-- ===========================================================================
-- 4. patient_account : isolation WRITE — compte A ne peut pas modifier compte B.
-- ===========================================================================
UPDATE patient_account SET first_name = 'Pirated'
 WHERE id = '12000000-0000-0000-0000-0000000000e2';

SET LOCAL app.current_account_id = '12000000-0000-0000-0000-0000000000e2';
SELECT is(
  (SELECT first_name FROM patient_account WHERE id = '12000000-0000-0000-0000-0000000000e2')::text,
  'Auth',
  '⭐ non-fuite patient_account WRITE : compte A ne peut pas modifier first_name de compte B');

SELECT * FROM finish();
ROLLBACK;
