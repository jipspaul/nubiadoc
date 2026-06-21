-- 39_slot_hold_rls.sql — DB-T025 : RLS isolation cabinet sur slot_holds.
-- Issue #2447.
--
-- Invariants couverts :
--   SH1. slot_hold_cabinet_isolation — GUC cabinet A → hold du cabinet A visible (1 ligne).
--   SH2. slot_hold_cabinet_isolation — GUC cabinet B → hold du cabinet A invisible (0 ligne).
--   SH3. fail-closed — GUC absent → 0 ligne visible.
--
-- Exécuté par pg_prove sous nubia_app (NOSUPERUSER, NOBYPASSRLS).
-- Fixtures auto-containées (BEGIN…ROLLBACK). Préfixe UUID 24470000.

BEGIN;
SELECT * FROM no_plan();

-- ===========================================================================
-- Pré-condition : exécuté sous nubia_app
-- ===========================================================================
SELECT is(current_user::text, 'nubia_app',
    '⭐ tests slot_hold_rls exécutés sous nubia_app');

-- ===========================================================================
-- Fixtures
-- Cabinet A possède un créneau ; un patient pose un hold sur ce créneau.
-- Cabinet B existe mais ne possède aucun créneau (isolation négative).
-- Préfixe UUID 24470000.
-- ===========================================================================

-- Cabinet A
SET LOCAL app.current_cabinet_id = '24470000-0000-0000-0000-000000000001';
INSERT INTO cabinet (id, raison_sociale)
    VALUES ('24470000-0000-0000-0000-000000000001', 'Cabinet Hold A');

-- Cabinet B
SET LOCAL app.current_cabinet_id = '24470000-0000-0000-0000-000000000002';
INSERT INTO cabinet (id, raison_sociale)
    VALUES ('24470000-0000-0000-0000-000000000002', 'Cabinet Hold B');

-- Utilisateurs plateforme (app_user sans RLS cabinet)
INSERT INTO app_user (id, email, password_hash, kind)
    VALUES ('24470000-0000-0000-0000-0000000000a1', 'dr.hold2447@nubia.test', '$argon2id$fixture', 'pro');
INSERT INTO app_user (id, email, password_hash, kind)
    VALUES ('24470000-0000-0000-0000-0000000000a2', 'pat.hold2447@nubia.test', '$argon2id$fixture', 'patient');

-- Provider pour cabinet A
SET LOCAL app.current_cabinet_id = '24470000-0000-0000-0000-000000000001';
INSERT INTO provider (id, cabinet_id, user_id, display_name, rpps_verified, is_listed)
    VALUES ('24470000-0000-0000-0000-0000000000e1',
            '24470000-0000-0000-0000-000000000001',
            '24470000-0000-0000-0000-0000000000a1',
            'Dr Hold2447', false, false);

-- Créneau appartenant au cabinet A (cabinet_id explicite)
INSERT INTO availability_slot (id, provider_id, cabinet_id, starts_at, ends_at, status)
    VALUES ('24470000-0000-0000-0000-0000000000f1',
            '24470000-0000-0000-0000-0000000000e1',
            '24470000-0000-0000-0000-000000000001',
            now() + interval '1 day',
            now() + interval '1 day' + interval '30 min',
            'open');

-- Hold sur le créneau du cabinet A (slot_holds_app WITH CHECK(true) → ok sans GUC restriction)
INSERT INTO slot_holds (id, slot_id, user_id, hold_token, expires_at)
    VALUES ('24470000-0000-0000-0000-000000000100',
            '24470000-0000-0000-0000-0000000000f1',
            '24470000-0000-0000-0000-0000000000a2',
            'hold-test-2447',
            now() + interval '5 minutes');

-- ===========================================================================
-- SH1. GUC cabinet A → hold visible (1 ligne).
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '24470000-0000-0000-0000-000000000001';
SELECT is(
    (SELECT count(*)::int FROM slot_holds
      WHERE id = '24470000-0000-0000-0000-000000000100'),
    1,
    '⭐ SH1 slot_hold_cabinet_isolation : GUC cabinet A → hold visible (1 ligne)');

-- ===========================================================================
-- SH2. GUC cabinet B → hold du cabinet A invisible (0 ligne).
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '24470000-0000-0000-0000-000000000002';
SELECT is(
    (SELECT count(*)::int FROM slot_holds
      WHERE id = '24470000-0000-0000-0000-000000000100'),
    0,
    '⭐ SH2 slot_hold_cabinet_isolation : GUC cabinet B → hold de A invisible (0 ligne)');

-- ===========================================================================
-- SH3. GUC absent → 0 ligne visible (fail-closed).
-- ===========================================================================
RESET app.current_cabinet_id;
SELECT is(
    (SELECT count(*)::int FROM slot_holds
      WHERE id = '24470000-0000-0000-0000-000000000100'),
    0,
    '⭐ SH3 slot_hold_cabinet_isolation : GUC absent → 0 ligne visible (fail-closed)');

SELECT * FROM finish();
ROLLBACK;
