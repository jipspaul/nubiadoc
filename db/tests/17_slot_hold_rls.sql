-- 17_slot_hold_rls.sql — TDD audit pgTAP : RLS cabinet isolation sur slot_holds.
-- Issue #2461 — DB-T025.b.
--
-- Invariants couverts :
--   PRE.  tests exécutés sous nubia_app (NOSUPERUSER, NOBYPASSRLS).
--   SH1.  slot_holds : FORCE ROW LEVEL SECURITY actif (0095).
--   SH2.  slot_holds : policy slot_hold_cabinet_isolation présente (0110).
--   SH3.  slot_holds : fail-closed — GUC absent → 0 holds visibles.
--   SH4.  slot_holds : cabinet A voit ses propres holds (isolation positive).
--   SH5.  slot_holds : cabinet B ne voit PAS les holds du cabinet A.
--
-- La policy slot_hold_cabinet_isolation (migration 0108) remplace slot_holds_app (0095).
-- Isolation transitive : slot_holds n'a pas de cabinet_id → vérification via
-- availability_slot.cabinet_id (EXISTS subquery). GUC absent → nullif → NULL →
-- EXISTS = false → fail-closed.
--
-- Exécuté par pg_prove sous nubia_app (NOSUPERUSER, NOBYPASSRLS).
-- Fixtures auto-containées (BEGIN…ROLLBACK). Préfixe UUID 24610000.

BEGIN;
SELECT * FROM no_plan();

-- ===========================================================================
-- PRE. Pré-condition : tests exécutés sous nubia_app
-- ===========================================================================
SELECT is(current_user::text, 'nubia_app',
    '⭐ tests slot_hold_rls exécutés sous nubia_app');

-- ===========================================================================
-- Fixtures : deux cabinets A et B, providers, slots (cabinet_id set), holds
-- ===========================================================================

-- Cabinet A
SET LOCAL app.current_cabinet_id = '24610000-0000-0000-0000-000000000001';
INSERT INTO cabinet (id, raison_sociale)
    VALUES ('24610000-0000-0000-0000-000000000001', 'Cabinet T025-A')
    ON CONFLICT DO NOTHING;

-- Cabinet B (pas de hold — pour vérifier la non-fuite)
SET LOCAL app.current_cabinet_id = '24610000-0000-0000-0000-000000000002';
INSERT INTO cabinet (id, raison_sociale)
    VALUES ('24610000-0000-0000-0000-000000000002', 'Cabinet T025-B')
    ON CONFLICT DO NOTHING;

-- Users pro (pas de RLS cabinet sur app_user — INSERT libre)
INSERT INTO app_user (id, email, password_hash, kind)
    VALUES ('24610000-0000-0000-0000-000000000011', 'prov.a.t025@nubia.test', '$argon2id$fixture', 'pro')
    ON CONFLICT DO NOTHING;

-- Provider A (cabinet A)
SET LOCAL app.current_cabinet_id = '24610000-0000-0000-0000-000000000001';
INSERT INTO provider (id, cabinet_id, user_id, display_name, rpps_verified, is_listed)
    VALUES ('24610000-0000-0000-0000-000000000021',
            '24610000-0000-0000-0000-000000000001',
            '24610000-0000-0000-0000-000000000011',
            'Dr T025-A', false, false)
    ON CONFLICT DO NOTHING;

-- Slot A (cabinet A) — cabinet_id requis pour la vérification transitive de slot_hold_cabinet_isolation
INSERT INTO availability_slot (id, provider_id, cabinet_id, starts_at, ends_at, status)
    VALUES ('24610000-0000-0000-0000-000000000031',
            '24610000-0000-0000-0000-000000000021',
            '24610000-0000-0000-0000-000000000001',
            now() + interval '10 days',
            now() + interval '10 days' + interval '30 min',
            'open')
    ON CONFLICT DO NOTHING;

-- User patient (pour slot_holds.user_id — pas de RLS cabinet sur app_user)
INSERT INTO app_user (id, email, password_hash, kind)
    VALUES ('24610000-0000-0000-0000-000000000041', 'pat.t025@nubia.test', '$argon2id$fixture', 'patient')
    ON CONFLICT DO NOTHING;

-- Hold A (slot A, contexte cabinet A) — INSERT autorisé car availability_slot.cabinet_id = GUC
INSERT INTO slot_holds (id, slot_id, user_id, hold_token, expires_at)
    VALUES ('24610000-0000-0000-0000-000000000051',
            '24610000-0000-0000-0000-000000000031',
            '24610000-0000-0000-0000-000000000041',
            'tok-t025-a',
            now() + interval '5 minutes');

-- ===========================================================================
-- SH1. FORCE ROW LEVEL SECURITY sur slot_holds
-- ===========================================================================
SELECT ok(
    (SELECT relforcerowsecurity FROM pg_class WHERE relname = 'slot_holds'),
    'SH1 slot_holds : FORCE ROW LEVEL SECURITY activée');

-- ===========================================================================
-- SH2. Policy slot_hold_cabinet_isolation présente (0110)
-- ===========================================================================
SELECT ok(
    EXISTS(SELECT 1 FROM pg_policies
           WHERE tablename  = 'slot_holds'
             AND policyname = 'slot_hold_cabinet_isolation'),
    'SH2 slot_holds : policy slot_hold_cabinet_isolation présente (0110)');

-- ===========================================================================
-- SH3. FAIL-CLOSED : sans GUC app.current_cabinet_id → 0 holds visibles
-- ===========================================================================
RESET app.current_cabinet_id;
SELECT is(
    (SELECT count(*)::int FROM slot_holds
     WHERE id = '24610000-0000-0000-0000-000000000051'),
    0,
    '⭐ SH3 fail-closed slot_holds : aucun hold visible sans app.current_cabinet_id');

-- ===========================================================================
-- SH4. Cabinet A voit ses propres holds (isolation positive)
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '24610000-0000-0000-0000-000000000001';
SELECT is(
    (SELECT count(*)::int FROM slot_holds
     WHERE id = '24610000-0000-0000-0000-000000000051'),
    1,
    'SH4 contexte A : hold du cabinet A visible');

-- ===========================================================================
-- SH5. Cabinet B ne voit PAS les holds du cabinet A
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '24610000-0000-0000-0000-000000000002';
SELECT is(
    (SELECT count(*)::int FROM slot_holds
     WHERE id = '24610000-0000-0000-0000-000000000051'),
    0,
    '⭐ SH5 non-fuite slot_holds : contexte B ne voit PAS les holds du cabinet A');

SELECT * FROM finish();
ROLLBACK;
