-- 31_cabinet_strong.sql — TDD audit pgTAP : Cabinet multi-tenancy core.
-- Issue #1829 — T-DB-D003.
--
-- Invariants couverts :
--   CAB1. cabinet : FORCE ROW LEVEL SECURITY actif.
--   CAB2. cabinet : fail-closed sans app.current_cabinet_id.
--   CAB3. cabinet : isolation — contexte A ne voit PAS le cabinet B.
--   CM1.  cabinet_membership : FORCE ROW LEVEL SECURITY actif.
--   CM2.  cabinet_membership : fail-closed sans app.current_cabinet_id.
--   CM3.  cabinet_membership : isolation — contexte A ne voit PAS les memberships de B.
--   CM4.  cabinet_membership : WITH CHECK — insertion cross-tenant refusée (42501).
--   CM5.  cabinet_membership : CHECK role — valeur invalide refusée (23514).
--   CM6.  cabinet_membership : UNIQUE (cabinet_id, user_id) — doublon refusé (23505).
--   CM7.  cabinet_membership : invariant actif — un user ne peut être membre actif que
--         d'un seul cabinet à la fois (unique partial index WHERE active AND left_at IS NULL).
--
-- Exécuté par pg_prove sous nubia_app (NOSUPERUSER, NOBYPASSRLS).
-- Fixtures auto-containées (BEGIN…ROLLBACK). Préfixe UUID 18290000.

BEGIN;
SELECT * FROM no_plan();

-- ===========================================================================
-- Pré-condition : tests exécutés sous nubia_app
-- ===========================================================================
SELECT is(current_user::text, 'nubia_app',
    '⭐ tests cabinet_strong exécutés sous nubia_app');

-- ===========================================================================
-- Fixtures : deux cabinets A et B, deux users u1 et u2
-- ===========================================================================

-- Cabinet A
SET LOCAL app.current_cabinet_id = '18290000-0000-0000-0000-000000000001';
INSERT INTO cabinet (id, raison_sociale)
    VALUES ('18290000-0000-0000-0000-000000000001', 'Cabinet D003-A')
    ON CONFLICT DO NOTHING;

-- Cabinet B
SET LOCAL app.current_cabinet_id = '18290000-0000-0000-0000-000000000002';
INSERT INTO cabinet (id, raison_sociale)
    VALUES ('18290000-0000-0000-0000-000000000002', 'Cabinet D003-B')
    ON CONFLICT DO NOTHING;

-- Users (pas de RLS cabinet sur app_user ; INSERT libre pour nubia_app)
INSERT INTO app_user (id, email, password_hash, kind)
    VALUES ('18290000-0000-0000-0000-000000000011', 'u1.d003@nubia.test', '$argon2id$fixture', 'pro')
    ON CONFLICT DO NOTHING;
INSERT INTO app_user (id, email, password_hash, kind)
    VALUES ('18290000-0000-0000-0000-000000000012', 'u2.d003@nubia.test', '$argon2id$fixture', 'pro')
    ON CONFLICT DO NOTHING;

-- Membership A → u1 (actif, left_at IS NULL)
SET LOCAL app.current_cabinet_id = '18290000-0000-0000-0000-000000000001';
INSERT INTO cabinet_membership (id, cabinet_id, user_id, role)
    VALUES ('18290000-0000-0000-0000-000000000021',
            '18290000-0000-0000-0000-000000000001',
            '18290000-0000-0000-0000-000000000011',
            'practitioner')
    ON CONFLICT DO NOTHING;

-- Membership B → u2 (actif, left_at IS NULL)
SET LOCAL app.current_cabinet_id = '18290000-0000-0000-0000-000000000002';
INSERT INTO cabinet_membership (id, cabinet_id, user_id, role)
    VALUES ('18290000-0000-0000-0000-000000000022',
            '18290000-0000-0000-0000-000000000002',
            '18290000-0000-0000-0000-000000000012',
            'practitioner')
    ON CONFLICT DO NOTHING;

-- ===========================================================================
-- CAB1. FORCE ROW LEVEL SECURITY sur cabinet
-- ===========================================================================
SELECT ok(
    (SELECT relforcerowsecurity FROM pg_class WHERE relname = 'cabinet'),
    'CAB1 cabinet : FORCE ROW LEVEL SECURITY activée');

-- ===========================================================================
-- CAB2. FAIL-CLOSED cabinet : sans GUC → 0 cabinet visible
-- ===========================================================================
RESET app.current_cabinet_id;
SELECT is(
    (SELECT count(*)::int FROM cabinet
     WHERE id IN ('18290000-0000-0000-0000-000000000001',
                  '18290000-0000-0000-0000-000000000002')),
    0,
    '⭐ CAB2 fail-closed cabinet : aucun cabinet visible sans app.current_cabinet_id');

-- ===========================================================================
-- CAB3. ISOLATION cabinet : contexte A ne voit PAS le cabinet B
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '18290000-0000-0000-0000-000000000001';
SELECT is(
    (SELECT count(*)::int FROM cabinet
     WHERE id = '18290000-0000-0000-0000-000000000001'),
    1,
    'CAB3a contexte A : cabinet A visible');
SELECT is(
    (SELECT count(*)::int FROM cabinet
     WHERE id = '18290000-0000-0000-0000-000000000002'),
    0,
    '⭐ CAB3b non-fuite cabinet : contexte A ne voit PAS le cabinet B');

-- ===========================================================================
-- CM1. FORCE ROW LEVEL SECURITY sur cabinet_membership
-- ===========================================================================
SELECT ok(
    (SELECT relforcerowsecurity FROM pg_class WHERE relname = 'cabinet_membership'),
    'CM1 cabinet_membership : FORCE ROW LEVEL SECURITY activée');

-- ===========================================================================
-- CM2. FAIL-CLOSED cabinet_membership : sans GUC → 0 membership visible
-- ===========================================================================
RESET app.current_cabinet_id;
SELECT is(
    (SELECT count(*)::int FROM cabinet_membership
     WHERE id IN ('18290000-0000-0000-0000-000000000021',
                  '18290000-0000-0000-0000-000000000022')),
    0,
    '⭐ CM2 fail-closed cabinet_membership : aucun membership visible sans app.current_cabinet_id');

-- ===========================================================================
-- CM3. ISOLATION cabinet_membership : contexte A ne voit PAS les memberships de B
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '18290000-0000-0000-0000-000000000001';
SELECT is(
    (SELECT count(*)::int FROM cabinet_membership
     WHERE cabinet_id = '18290000-0000-0000-0000-000000000001'),
    1,
    'CM3a contexte A : 1 membership visible (cabinet A)');
SELECT is(
    (SELECT count(*)::int FROM cabinet_membership
     WHERE cabinet_id = '18290000-0000-0000-0000-000000000002'),
    0,
    '⭐ CM3b non-fuite cabinet_membership : contexte A ne voit PAS les memberships de B');

-- ===========================================================================
-- CM4. WITH CHECK cabinet_membership : insertion cross-tenant refusée
-- (contexte = B, on tente d'insérer un membership pour cabinet A)
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '18290000-0000-0000-0000-000000000002';
SELECT throws_ok(
    $$ INSERT INTO cabinet_membership (cabinet_id, user_id, role)
       VALUES (
           '18290000-0000-0000-0000-000000000001',
           '18290000-0000-0000-0000-000000000012',
           'secretary'
       ) $$,
    '42501', NULL,
    '⭐ CM4 WITH CHECK cabinet_membership : insertion cross-tenant (B→A) refusée');

-- ===========================================================================
-- CM5. CHECK role : valeur hors liste refusée
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '18290000-0000-0000-0000-000000000001';
SELECT throws_ok(
    $$ INSERT INTO cabinet_membership (cabinet_id, user_id, role)
       VALUES (
           '18290000-0000-0000-0000-000000000001',
           '18290000-0000-0000-0000-000000000012',
           'intrus'
       ) $$,
    '23514', NULL,
    '⭐ CM5 CHECK role : valeur ''intrus'' refusée (23514)');

-- ===========================================================================
-- CM6. UNIQUE (cabinet_id, user_id) : doublon dans le même cabinet refusé
-- ===========================================================================
SELECT throws_ok(
    $$ INSERT INTO cabinet_membership (cabinet_id, user_id, role)
       VALUES (
           '18290000-0000-0000-0000-000000000001',
           '18290000-0000-0000-0000-000000000011',
           'secretary'
       ) $$,
    '23505', NULL,
    '⭐ CM6 UNIQUE (cabinet_id, user_id) : doublon membership refusé (23505)');

-- ===========================================================================
-- CM7. INVARIANT actif : un user ne peut pas être membre actif de 2 cabinets
--      simultanément (active=true, left_at IS NULL).
--      u1 est déjà actif dans cabinet A → essai d'ajout dans cabinet B doit échouer.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '18290000-0000-0000-0000-000000000002';
SELECT throws_ok(
    $$ INSERT INTO cabinet_membership (cabinet_id, user_id, role, active)
       VALUES (
           '18290000-0000-0000-0000-000000000002',
           '18290000-0000-0000-0000-000000000011',
           'practitioner',
           true
       ) $$,
    '23505', NULL,
    '⭐ CM7 invariant : un user actif ne peut pas rejoindre un 2ème cabinet simultanément (23505)');

SELECT * FROM finish();
ROLLBACK;
