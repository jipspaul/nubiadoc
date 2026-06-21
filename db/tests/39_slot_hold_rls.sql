-- 39_slot_hold_rls.sql — pgTAP : isolation cabinet sur slot_holds (0108).
-- Issue #2460 — DB-T025.
--
-- Invariants couverts :
--   FORCE1. slot_holds : FORCE ROW LEVEL SECURITY activee.
--   POL1.   policy slot_hold_cabinet_isolation presente (0108).
--   POL2.   policy slot_holds_seed presente pour nubia_seed (0095).
--   AR1.    fail-closed : aucun hold visible sans GUC app.current_cabinet_id.
--   AR2a.   contexte A → voit son propre hold (meme cabinet).
--   AR2b.   contexte A → ne voit pas le hold de B (non-fuite inter-cabinet).
--   AR3.    WITH CHECK : INSERT refuse si le slot appartient a un autre cabinet.
--
-- Execute par pg_prove sous nubia_app (NOSUPERUSER, NOBYPASSRLS).
-- Fixtures auto-contenues (BEGIN…ROLLBACK). Prefixe UUID 24600000.

BEGIN;
SELECT * FROM no_plan();

-- ===========================================================================
-- Pre-conditions
-- ===========================================================================
SELECT is(current_user::text, 'nubia_app',
    'PRE slot_hold_rls : execute sous nubia_app');

SELECT ok(NOT (SELECT rolbypassrls FROM pg_roles WHERE rolname = 'nubia_app'),
    'PRE nubia_app NOBYPASSRLS confirme');

-- ===========================================================================
-- FORCE1. FORCE ROW LEVEL SECURITY activee sur slot_holds
-- ===========================================================================
SELECT ok(
    (SELECT relforcerowsecurity FROM pg_class WHERE relname = 'slot_holds'),
    'FORCE1 slot_holds : FORCE ROW LEVEL SECURITY activee');

-- ===========================================================================
-- POL1. Policy slot_hold_cabinet_isolation presente (0108)
-- ===========================================================================
SELECT ok(
    EXISTS(SELECT 1 FROM pg_policies
           WHERE tablename  = 'slot_holds'
             AND policyname = 'slot_hold_cabinet_isolation'),
    'POL1 slot_holds : policy slot_hold_cabinet_isolation presente (0108)');

-- ===========================================================================
-- POL2. Policy slot_holds_seed presente pour nubia_seed (0095)
-- ===========================================================================
SELECT ok(
    EXISTS(SELECT 1 FROM pg_policies
           WHERE tablename  = 'slot_holds'
             AND policyname = 'slot_holds_seed'),
    'POL2 slot_holds : policy slot_holds_seed presente (0095)');

-- ===========================================================================
-- Fixtures : 2 cabinets, 2 providers, 2 slots (un par cabinet), 2 holds.
-- Prefixe UUID 24600000 (propre a cette suite).
-- ===========================================================================

-- Cabinet A
SET LOCAL app.current_cabinet_id = '24600000-0000-0000-0000-000000000001';
INSERT INTO cabinet (id, raison_sociale)
    VALUES ('24600000-0000-0000-0000-000000000001', 'Cabinet SlotHold-RLS-A');

INSERT INTO app_user (id, email, password_hash, kind)
    VALUES ('24600000-0000-0000-0000-0000000000a1',
            'dr.2460a@nubia.test', '$argon2id$fixture', 'pro');

INSERT INTO provider (id, cabinet_id, user_id, display_name, rpps_verified, is_listed)
    VALUES ('24600000-0000-0000-0000-0000000000e1',
            '24600000-0000-0000-0000-000000000001',
            '24600000-0000-0000-0000-0000000000a1',
            'Dr SlotHold A', true, true);

INSERT INTO app_user (id, email, password_hash, kind)
    VALUES ('24600000-0000-0000-0000-0000000000b1',
            'pat.2460a@nubia.test', '$argon2id$fixture', 'patient');

-- Slot du cabinet A (cabinet_id requis pour la policy transitive)
INSERT INTO availability_slot (id, provider_id, cabinet_id, starts_at, ends_at, status)
    VALUES ('24600000-0000-0000-0000-0000000000f1',
            '24600000-0000-0000-0000-0000000000e1',
            '24600000-0000-0000-0000-000000000001',
            now() + interval '1 day',
            now() + interval '1 day' + interval '30 min',
            'open');

-- Hold sur le slot A
INSERT INTO slot_holds (id, slot_id, user_id, hold_token, expires_at)
    VALUES ('24600000-0000-0000-0000-000000000100',
            '24600000-0000-0000-0000-0000000000f1',
            '24600000-0000-0000-0000-0000000000b1',
            'hold-2460-a',
            now() + interval '5 minutes');

-- Cabinet B
SET LOCAL app.current_cabinet_id = '24600000-0000-0000-0000-000000000002';
INSERT INTO cabinet (id, raison_sociale)
    VALUES ('24600000-0000-0000-0000-000000000002', 'Cabinet SlotHold-RLS-B');

INSERT INTO app_user (id, email, password_hash, kind)
    VALUES ('24600000-0000-0000-0000-0000000000a2',
            'dr.2460b@nubia.test', '$argon2id$fixture', 'pro');

INSERT INTO provider (id, cabinet_id, user_id, display_name, rpps_verified, is_listed)
    VALUES ('24600000-0000-0000-0000-0000000000e2',
            '24600000-0000-0000-0000-000000000002',
            '24600000-0000-0000-0000-0000000000a2',
            'Dr SlotHold B', true, true);

INSERT INTO app_user (id, email, password_hash, kind)
    VALUES ('24600000-0000-0000-0000-0000000000b2',
            'pat.2460b@nubia.test', '$argon2id$fixture', 'patient');

-- Slot du cabinet B
INSERT INTO availability_slot (id, provider_id, cabinet_id, starts_at, ends_at, status)
    VALUES ('24600000-0000-0000-0000-0000000000f2',
            '24600000-0000-0000-0000-0000000000e2',
            '24600000-0000-0000-0000-000000000002',
            now() + interval '2 days',
            now() + interval '2 days' + interval '30 min',
            'open');

-- Hold sur le slot B
INSERT INTO slot_holds (id, slot_id, user_id, hold_token, expires_at)
    VALUES ('24600000-0000-0000-0000-000000000200',
            '24600000-0000-0000-0000-0000000000f2',
            '24600000-0000-0000-0000-0000000000b2',
            'hold-2460-b',
            now() + interval '5 minutes');

-- ===========================================================================
-- AR1. FAIL-CLOSED : sans GUC → 0 hold visible
-- ===========================================================================
RESET app.current_cabinet_id;
SELECT is(
    (SELECT count(*)::int FROM slot_holds
     WHERE id IN ('24600000-0000-0000-0000-000000000100',
                  '24600000-0000-0000-0000-000000000200')),
    0,
    '⭐ AR1 fail-closed slot_holds : aucun hold visible sans app.current_cabinet_id');

-- ===========================================================================
-- AR2. ISOLATION : contexte A → 1 hold propre, 0 hold de B
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '24600000-0000-0000-0000-000000000001';
SELECT is(
    (SELECT count(*)::int FROM slot_holds
     WHERE id IN ('24600000-0000-0000-0000-000000000100',
                  '24600000-0000-0000-0000-000000000200')),
    1,
    'AR2a contexte A : 1 hold visible (slot du cabinet A)');

SELECT is(
    (SELECT count(*)::int FROM slot_holds
     WHERE id = '24600000-0000-0000-0000-000000000200'),
    0,
    '⭐ AR2b non-fuite slot_holds : contexte A ne voit PAS le hold de B');

-- ===========================================================================
-- AR3. WITH CHECK : INSERT refuse si le slot appartient a un autre cabinet.
-- Contexte B tente d'inserer un hold sur le slot A → rejet (42501).
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '24600000-0000-0000-0000-000000000002';
SELECT throws_ok(
    $$ INSERT INTO slot_holds (slot_id, user_id, hold_token, expires_at)
       VALUES (
           '24600000-0000-0000-0000-0000000000f1',
           '24600000-0000-0000-0000-0000000000b2',
           'hold-cross-tenant',
           now() + interval '5 minutes'
       ) $$,
    '42501', NULL,
    '⭐ AR3 WITH CHECK slot_holds : INSERT cross-cabinet (B sur slot A) refuse (42501)');

SELECT * FROM finish();
ROLLBACK;
