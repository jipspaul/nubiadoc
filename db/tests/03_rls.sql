-- 03_rls.sql — ⭐ LE test le plus important : Row-Level Security sous nubia_app.
-- Réf. : docs/05 §2, §9.3 ; db/README §3-§4 ; PROMPT « Tests RLS ».
-- Vérifie : rôle non-superuser/non-bypass · fail-closed · non-fuite inter-cabinets ·
-- refus d'écriture cross-tenant (WITH CHECK) · entités plateforme visibles hors contexte.
BEGIN;
SELECT * FROM no_plan();

-- ===========================================================================
-- 0. Le rôle qui exécute ces tests EST bien nubia_app, non-superuser, non-bypass.
--    (Sinon la RLS serait inopérante : tout le test serait un faux positif.)
-- ===========================================================================
SELECT is(current_user::text, 'nubia_app', 'les tests RLS tournent sous nubia_app');
SELECT ok( NOT (SELECT rolsuper     FROM pg_roles WHERE rolname='nubia_app'),
  'nubia_app est NOSUPERUSER');
SELECT ok( NOT (SELECT rolbypassrls FROM pg_roles WHERE rolname='nubia_app'),
  'nubia_app est NOBYPASSRLS (RLS effective)');

-- ===========================================================================
-- Fixtures : deux cabinets A et B, chacun avec un patient. On insère sous le
-- contexte de chaque tenant (l'app elle-même est soumise à la RLS).
-- ===========================================================================
SET LOCAL app.current_cabinet_id = 'a0000000-0000-0000-0000-000000000001';
INSERT INTO cabinet (id, raison_sociale) VALUES ('a0000000-0000-0000-0000-000000000001','Cabinet A');
INSERT INTO patient (id, cabinet_id, first_name, last_name)
  VALUES ('a0000000-0000-0000-0000-0000000000d1','a0000000-0000-0000-0000-000000000001','Alice','A');

SET LOCAL app.current_cabinet_id = 'b0000000-0000-0000-0000-000000000001';
INSERT INTO cabinet (id, raison_sociale) VALUES ('b0000000-0000-0000-0000-000000000001','Cabinet B');
INSERT INTO patient (id, cabinet_id, first_name, last_name)
  VALUES ('b0000000-0000-0000-0000-0000000000d1','b0000000-0000-0000-0000-000000000001','Bob','B');

-- ===========================================================================
-- 1. FAIL-CLOSED : sans GUC positionné -> 0 ligne visible.
-- ===========================================================================
RESET app.current_cabinet_id;
SELECT is( (SELECT count(*) FROM patient)::int, 0,
  '⭐ fail-closed : aucun patient visible sans app.current_cabinet_id');
SELECT is( (SELECT count(*) FROM cabinet)::int, 0,
  '⭐ fail-closed : aucun cabinet visible sans contexte');

-- ===========================================================================
-- 2. ISOLATION : contexte A -> on voit A, jamais B (et inversement).
-- ===========================================================================
SET LOCAL app.current_cabinet_id = 'a0000000-0000-0000-0000-000000000001';
SELECT is( (SELECT count(*) FROM patient)::int, 1,
  'contexte A : 1 patient visible');
SELECT is( (SELECT count(*) FROM patient WHERE cabinet_id = 'b0000000-0000-0000-0000-000000000001')::int, 0,
  '⭐ non-fuite : contexte A ne voit AUCUN patient de B');
SELECT is( (SELECT first_name FROM patient LIMIT 1), 'Alice',
  'contexte A : c''est bien le patient de A');

SET LOCAL app.current_cabinet_id = 'b0000000-0000-0000-0000-000000000001';
SELECT is( (SELECT count(*) FROM patient)::int, 1,
  'contexte B : 1 patient visible');
SELECT is( (SELECT first_name FROM patient LIMIT 1), 'Bob',
  '⭐ non-fuite : contexte B voit B, pas A');

-- ===========================================================================
-- 3. WITH CHECK : écriture dans un AUTRE tenant refusée.
-- ===========================================================================
-- (contexte = B) tenter d'écrire une ligne marquée cabinet A
SELECT throws_ok(
  $$ INSERT INTO patient (cabinet_id, first_name, last_name)
     VALUES ('a0000000-0000-0000-0000-000000000001','Pirate','X') $$,
  '42501', NULL, '⭐ WITH CHECK : écrire dans le cabinet A depuis le contexte B refusé');

-- on ne peut pas non plus "déplacer" une ligne vers un autre tenant
SET LOCAL app.current_cabinet_id = 'a0000000-0000-0000-0000-000000000001';
SELECT throws_ok(
  $$ UPDATE patient SET cabinet_id = 'b0000000-0000-0000-0000-000000000001'
     WHERE id = 'a0000000-0000-0000-0000-0000000000d1' $$,
  '42501', NULL, '⭐ WITH CHECK : exfiltrer une ligne de A vers B refusé');

-- ===========================================================================
-- 4. ENTITÉS PLATEFORME : app_user et patient_account ont une RLS propre (0045).
--    Isolation par identifiant propre, pas par cabinet_id.
--    Annuaire public (profession, provider listé) : pas de RLS cabinet.
-- ===========================================================================

-- Fixtures : deux app_user (UUID ff et 10f) et deux patient_account (UUID e1 et e2).
-- INSERT ouvert (policy user_app_insert / account_app_insert) : pas de GUC requis.
INSERT INTO app_user (id, email, password_hash, kind)
  VALUES ('a0000000-0000-0000-0000-0000000000ff','patient.rls@example.test','$argon2id$fixture','patient');
INSERT INTO app_user (id, email, password_hash, kind)
  VALUES ('a0000000-0000-0000-0000-00000000010f','patient.b@example.test','$argon2id$fixture','patient');

INSERT INTO patient_account (id, app_user_id, first_name, last_name)
  VALUES ('a0000000-0000-0000-0000-0000000000e1','a0000000-0000-0000-0000-0000000000ff','Compte','A');
INSERT INTO patient_account (id, app_user_id, first_name, last_name)
  VALUES ('a0000000-0000-0000-0000-0000000000e2','a0000000-0000-0000-0000-00000000010f','Compte','B');

-- 4.1 app_user : fail-closed (sans GUC → 0 ligne visible)
RESET app.current_user_id;
SELECT is( (SELECT count(*) FROM app_user)::int, 0,
  '⭐ fail-closed app_user : aucun user visible sans app.current_user_id');

-- 4.2 app_user : accès borné à sa propre ligne + isolation inter-user
SET LOCAL app.current_user_id = 'a0000000-0000-0000-0000-0000000000ff';
SELECT is( (SELECT count(*) FROM app_user)::int, 1,
  'app_user context ff : 1 ligne visible (la sienne)');
SELECT is( (SELECT count(*) FROM app_user WHERE id = 'a0000000-0000-0000-0000-00000000010f')::int, 0,
  '⭐ non-fuite app_user : user ff ne voit PAS user 10f');

-- 4.3 patient_account : fail-closed (sans GUC → 0 ligne visible)
RESET app.current_account_id;
SELECT is( (SELECT count(*) FROM patient_account)::int, 0,
  '⭐ fail-closed patient_account : aucun compte sans app.current_account_id');

-- 4.4 patient_account : accès borné au compte courant + isolation inter-compte
SET LOCAL app.current_account_id = 'a0000000-0000-0000-0000-0000000000e1';
SELECT is( (SELECT count(*) FROM patient_account)::int, 1,
  'patient_account context e1 : 1 compte visible (le sien)');
SELECT is( (SELECT count(*) FROM patient_account WHERE id = 'a0000000-0000-0000-0000-0000000000e2')::int, 0,
  '⭐ non-fuite patient_account : account e1 ne voit PAS account e2');

-- Annuaire public : provider listé (créé sous contexte cabinet A — app.current_cabinet_id = A
-- est encore actif depuis section 3, aucun RESET depuis).
INSERT INTO provider (id, cabinet_id, user_id, display_name, is_listed)
  VALUES ('a0000000-0000-0000-0000-0000000000f1','a0000000-0000-0000-0000-000000000001',
          'a0000000-0000-0000-0000-0000000000ff','Dr Public', true);
INSERT INTO profession (id, label) VALUES ('a0000000-0000-0000-0000-0000000000b1','Chirurgien-dentiste');

RESET app.current_cabinet_id;
SELECT ok( (SELECT count(*) FROM profession) >= 1,
  'annuaire profession visible hors contexte cabinet');
-- (scopé sur la fixture : robuste même si du seed a déjà chargé des providers listés)
SELECT is( (SELECT count(*) FROM provider WHERE id = 'a0000000-0000-0000-0000-0000000000f1')::int, 1,
  'provider listé visible hors contexte cabinet (annuaire public)');

-- un provider NON listé ne doit pas fuiter dans l'annuaire public
SET LOCAL app.current_cabinet_id = 'a0000000-0000-0000-0000-000000000001';
INSERT INTO provider (id, cabinet_id, user_id, display_name, is_listed)
  VALUES ('a0000000-0000-0000-0000-0000000000f2','a0000000-0000-0000-0000-000000000001',
          'a0000000-0000-0000-0000-0000000000ff','Dr Cache', false);
RESET app.current_cabinet_id;
SELECT is( (SELECT count(*) FROM provider WHERE id = 'a0000000-0000-0000-0000-0000000000f2')::int, 0,
  'provider non listé invisible dans l''annuaire public (is_listed=false)');

SELECT * FROM finish();
ROLLBACK;
