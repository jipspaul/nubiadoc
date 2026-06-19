-- 36_secretariat_strong.sql -- TDD audit pgTAP : Secretariat role + isolation (approfondissement).
-- Issue #1834 -- T-DB-D008.
--
-- Invariants couverts (complementaires a 27_secretariat_rls.sql et 28_secretariat_isolation.sql) :
--   PRE1.   execute sous nubia_app (NOSUPERUSER).
--   PRE2.   nubia_app NOBYPASSRLS confirme.
--   FORCE1. secretariat : FORCE ROW LEVEL SECURITY activee (0086).
--   FORCE2. provider_secretariat : FORCE ROW LEVEL SECURITY activee (0087).
--   FORCE3. secretariat_membership : FORCE ROW LEVEL SECURITY activee (0088).
--   POL1.   secretariat : policy tenant_isolation presente (0086).
--   POL2.   provider_secretariat : policy tenant_isolation presente (0087).
--   POL3.   secretariat_membership : policy tenant_isolation presente (0088).
--   C1.     secretariat.name NOT NULL : INSERT NULL name rejete (23502).
--   C2.     secretariat_membership.role CHECK : valeur hors ('secretary','manager') rejetee (23514).
--   C3.     provider_secretariat UNIQUE partial active : doublon actif rejete (23505).
--   C4.     secretariat_membership UNIQUE partial active : doublon actif rejete (23505).
--   N1.     workflow nominal : creer un nouveau secretariat dans le cabinet courant OK.
--   N2.     workflow nominal : ajouter un membre manager OK.
--   N3.     workflow nominal : assigner le provider a un second secretariat OK.
--   N4.     soft-delete secretariat_membership : active=false OK.
--   N4b.    active=false confirme apres desactivation.
--   N5.     apres desactivation, readhesion active autorisee (UNIQUE partial = active seulement).
--   FN1.    user_all_memberships : fonction presente dans le schema public.
--   FN2.    user_all_memberships : retourne 0 lignes pour un user inexistant.
--
-- Execute par pg_prove sous nubia_app (NOSUPERUSER, NOBYPASSRLS).
-- Fixtures auto-containees (BEGIN...ROLLBACK). Prefixe UUID 18340000.

BEGIN;
SELECT * FROM no_plan();

-- ===========================================================================
-- Pre-conditions : role et attributs RLS
-- ===========================================================================
SELECT is(current_user::text, 'nubia_app',
    'PRE1 secretariat_strong : execute sous nubia_app');

SELECT ok(NOT (SELECT rolbypassrls FROM pg_roles WHERE rolname = 'nubia_app'),
    'PRE2 nubia_app NOBYPASSRLS confirme');

-- ===========================================================================
-- FORCE1-3. FORCE ROW LEVEL SECURITY activee sur les 3 tables secretariat
-- ===========================================================================
SELECT ok(
    (SELECT relforcerowsecurity FROM pg_class WHERE relname = 'secretariat'),
    'FORCE1 secretariat : FORCE ROW LEVEL SECURITY activee (0086)');

SELECT ok(
    (SELECT relforcerowsecurity FROM pg_class WHERE relname = 'provider_secretariat'),
    'FORCE2 provider_secretariat : FORCE ROW LEVEL SECURITY activee (0087)');

SELECT ok(
    (SELECT relforcerowsecurity FROM pg_class WHERE relname = 'secretariat_membership'),
    'FORCE3 secretariat_membership : FORCE ROW LEVEL SECURITY activee (0088)');

-- ===========================================================================
-- POL1-3. Policies tenant_isolation presentes sur les 3 tables
-- ===========================================================================
SELECT ok(
    EXISTS(SELECT 1 FROM pg_policies
           WHERE tablename  = 'secretariat'
             AND policyname = 'tenant_isolation'),
    'POL1 secretariat : policy tenant_isolation presente (0086)');

SELECT ok(
    EXISTS(SELECT 1 FROM pg_policies
           WHERE tablename  = 'provider_secretariat'
             AND policyname = 'tenant_isolation'),
    'POL2 provider_secretariat : policy tenant_isolation presente (0087)');

SELECT ok(
    EXISTS(SELECT 1 FROM pg_policies
           WHERE tablename  = 'secretariat_membership'
             AND policyname = 'tenant_isolation'),
    'POL3 secretariat_membership : policy tenant_isolation presente (0088)');

-- ===========================================================================
-- Fixtures : cabinet A avec secretariat, provider et 2 utilisateurs pro.
-- Prefixe UUID 18340000 (propre a cette suite, hors des autres fixtures).
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '18340000-0000-0000-0000-000000000001';

INSERT INTO cabinet (id, raison_sociale)
    VALUES ('18340000-0000-0000-0000-000000000001', 'Cabinet Secretariat-Strong-A');

INSERT INTO secretariat (id, cabinet_id, name)
    VALUES ('18340000-0000-0000-0000-000000000011',
            '18340000-0000-0000-0000-000000000001', 'Secretariat Principal A');

INSERT INTO app_user (id, email, password_hash, kind)
    VALUES ('18340000-0000-0000-0000-0000000000a1',
            'prat.1834a@nubia.test', '$argon2id$fixture', 'pro');

INSERT INTO app_user (id, email, password_hash, kind)
    VALUES ('18340000-0000-0000-0000-0000000000a2',
            'secr.1834a@nubia.test', '$argon2id$fixture', 'pro');

INSERT INTO provider (id, cabinet_id, user_id, display_name, rpps_verified, is_listed)
    VALUES ('18340000-0000-0000-0000-0000000000b1',
            '18340000-0000-0000-0000-000000000001',
            '18340000-0000-0000-0000-0000000000a1',
            'Dr StrongA', false, false);

-- Cabinet B (second tenant, pour les guards cross-tenant si besoin)
SET LOCAL app.current_cabinet_id = '18340000-0000-0000-0000-000000000002';
INSERT INTO cabinet (id, raison_sociale)
    VALUES ('18340000-0000-0000-0000-000000000002', 'Cabinet Secretariat-Strong-B');

-- Retour contexte A pour tous les tests qui suivent
SET LOCAL app.current_cabinet_id = '18340000-0000-0000-0000-000000000001';

-- ===========================================================================
-- C1. secretariat.name NOT NULL : INSERT avec name=NULL rejete (23502)
-- ===========================================================================
SELECT throws_ok(
    $$ INSERT INTO secretariat (cabinet_id, name)
       VALUES ('18340000-0000-0000-0000-000000000001', NULL) $$,
    '23502', NULL,
    'C1 secretariat.name NOT NULL : NULL rejete (23502)');

-- ===========================================================================
-- C2. secretariat_membership.role CHECK : valeur invalide rejetee (23514)
-- ===========================================================================
SELECT throws_ok(
    $$ INSERT INTO secretariat_membership (cabinet_id, secretariat_id, user_id, role)
       VALUES ('18340000-0000-0000-0000-000000000001',
               '18340000-0000-0000-0000-000000000011',
               '18340000-0000-0000-0000-0000000000a2',
               'admin') $$,
    '23514', NULL,
    'C2 secretariat_membership.role CHECK : admin rejete (23514 — valeurs valides : secretary, manager)');

-- ===========================================================================
-- C3. provider_secretariat UNIQUE partial active : doublon actif rejete (23505)
-- Premier lien actif insere en dehors de throws_ok ; le doublon teste dans throws_ok.
-- ===========================================================================
INSERT INTO provider_secretariat (id, provider_id, secretariat_id, active)
    VALUES ('18340000-0000-0000-0000-000000001001',
            '18340000-0000-0000-0000-0000000000b1',
            '18340000-0000-0000-0000-000000000011',
            true);

SELECT throws_ok(
    $$ INSERT INTO provider_secretariat (provider_id, secretariat_id, active)
       VALUES ('18340000-0000-0000-0000-0000000000b1',
               '18340000-0000-0000-0000-000000000011',
               true) $$,
    '23505', NULL,
    'C3 provider_secretariat UNIQUE partial active : doublon actif rejete (23505)');

-- ===========================================================================
-- C4. secretariat_membership UNIQUE partial active : doublon actif rejete (23505)
-- Premier membre actif insere en dehors de throws_ok ; le doublon teste dans throws_ok.
-- ===========================================================================
INSERT INTO secretariat_membership (id, cabinet_id, secretariat_id, user_id, role, active)
    VALUES ('18340000-0000-0000-0000-000000002001',
            '18340000-0000-0000-0000-000000000001',
            '18340000-0000-0000-0000-000000000011',
            '18340000-0000-0000-0000-0000000000a2',
            'secretary', true);

SELECT throws_ok(
    $$ INSERT INTO secretariat_membership (cabinet_id, secretariat_id, user_id, role, active)
       VALUES ('18340000-0000-0000-0000-000000000001',
               '18340000-0000-0000-0000-000000000011',
               '18340000-0000-0000-0000-0000000000a2',
               'manager', true) $$,
    '23505', NULL,
    'C4 secretariat_membership UNIQUE partial active : doublon actif rejete (23505)');

-- ===========================================================================
-- N1. Workflow nominal : creer un second secretariat dans le cabinet courant OK
-- ===========================================================================
SELECT lives_ok(
    $$ INSERT INTO secretariat (id, cabinet_id, name)
       VALUES ('18340000-0000-0000-0000-000000000012',
               '18340000-0000-0000-0000-000000000001', 'Secretariat Secondaire A') $$,
    'N1 secretariat : creation nominale OK');

-- ===========================================================================
-- N2. Workflow nominal : ajouter un membre manager dans le secretariat OK
-- ===========================================================================
INSERT INTO app_user (id, email, password_hash, kind)
    VALUES ('18340000-0000-0000-0000-0000000000a3',
            'mgr.1834a@nubia.test', '$argon2id$fixture', 'pro');

SELECT lives_ok(
    $$ INSERT INTO secretariat_membership (id, cabinet_id, secretariat_id, user_id, role, active)
       VALUES ('18340000-0000-0000-0000-000000002002',
               '18340000-0000-0000-0000-000000000001',
               '18340000-0000-0000-0000-000000000011',
               '18340000-0000-0000-0000-0000000000a3',
               'manager', true) $$,
    'N2 secretariat_membership : ajout membre manager OK');

-- ===========================================================================
-- N3. Workflow nominal : assigner le provider a un second secretariat OK
--     (meme provider, autre secretariat -> pas de conflit sur l'index partial)
-- ===========================================================================
SELECT lives_ok(
    $$ INSERT INTO provider_secretariat (id, provider_id, secretariat_id, active)
       VALUES ('18340000-0000-0000-0000-000000001002',
               '18340000-0000-0000-0000-0000000000b1',
               '18340000-0000-0000-0000-000000000012',
               true) $$,
    'N3 provider_secretariat : assignation a un second secretariat OK');

-- ===========================================================================
-- N4. Soft-delete secretariat_membership : active=false OK (pas de DELETE dur)
-- ===========================================================================
SELECT lives_ok(
    $$ UPDATE secretariat_membership
       SET active = false
       WHERE id = '18340000-0000-0000-0000-000000002001' $$,
    'N4 secretariat_membership : desactivation (active=false) OK');

SELECT is(
    (SELECT active FROM secretariat_membership
     WHERE id = '18340000-0000-0000-0000-000000002001'),
    false,
    'N4b secretariat_membership : active=false confirme apres desactivation');

-- ===========================================================================
-- N5. Apres desactivation, une readhesion active du meme user est autorisee.
--     L'index UNIQUE partial ne porte que sur (secretariat_id, user_id) WHERE active=true.
--     La ligne precedente ayant active=false, le nouvel INSERT doit passer.
-- ===========================================================================
SELECT lives_ok(
    $$ INSERT INTO secretariat_membership (id, cabinet_id, secretariat_id, user_id, role, active)
       VALUES ('18340000-0000-0000-0000-000000002003',
               '18340000-0000-0000-0000-000000000001',
               '18340000-0000-0000-0000-000000000011',
               '18340000-0000-0000-0000-0000000000a2',
               'secretary', true) $$,
    'N5 secretariat_membership : readhesion active apres desactivation autorisee');

-- ===========================================================================
-- FN1. user_all_memberships : fonction presente dans le schema public (0089)
-- ===========================================================================
SELECT ok(
    EXISTS(SELECT 1 FROM pg_proc p
           JOIN pg_namespace n ON n.oid = p.pronamespace
           WHERE n.nspname = 'public' AND p.proname = 'user_all_memberships'),
    'FN1 user_all_memberships : fonction presente dans le schema public (0089)');

-- ===========================================================================
-- FN2. user_all_memberships : retourne 0 lignes pour un user inexistant
-- ===========================================================================
SELECT is(
    (SELECT count(*)::int FROM user_all_memberships('00000000-0000-0000-0000-000000000000')),
    0,
    'FN2 user_all_memberships : 0 ligne pour un user inexistant (uuid nul)');

SELECT * FROM finish();
ROLLBACK;
