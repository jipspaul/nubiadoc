-- 17_slot_hold_rls.sql — Isolation RLS slot_holds par cabinet (issue #2447).
-- Tests :
--   1. Cabinet A voit ses holds (créneau lié au cabinet A).
--   2. Cabinet B ne voit pas les holds du cabinet A.
--   3. GUC absent → 0 rows (fail-closed).
-- Exécuté par pg_prove sous nubia_app (NOSUPERUSER, NOBYPASSRLS).
-- Fixtures auto-containées (BEGIN…ROLLBACK). Préfixe UUID 24470000.

BEGIN;
SELECT * FROM no_plan();

-- ===========================================================================
-- Fixtures : cabinet A + provider A + slot A + hold A ; cabinet B (sans hold).
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '24470000-0000-0000-0000-000000000001';

INSERT INTO cabinet (id, raison_sociale) VALUES
  ('24470000-0000-0000-0000-000000000001', 'Cabinet Hold-RLS A');

INSERT INTO app_user (id, email, password_hash, kind) VALUES
  ('24470000-0000-0000-0000-0000000000a1', 'pro-a@2447.test', '$argon2id$fixture', 'pro');

INSERT INTO provider (id, cabinet_id, user_id, display_name, rpps_verified, is_listed) VALUES
  ('24470000-0000-0000-0000-000000000101',
   '24470000-0000-0000-0000-000000000001',
   '24470000-0000-0000-0000-0000000000a1',
   'Dr Hold A', false, false);

INSERT INTO availability_slot (id, provider_id, cabinet_id, starts_at, ends_at, status) VALUES
  ('24470000-0000-0000-0000-0000000000f1',
   '24470000-0000-0000-0000-000000000101',
   '24470000-0000-0000-0000-000000000001',
   now() + interval '1 day',
   now() + interval '1 day' + interval '30 min',
   'open');

INSERT INTO app_user (id, email, password_hash, kind) VALUES
  ('24470000-0000-0000-0000-0000000000a3', 'patient@2447.test', '$argon2id$fixture', 'patient');

INSERT INTO slot_holds (id, slot_id, user_id, hold_token, expires_at) VALUES
  ('24470000-0000-0000-0000-000000000100',
   '24470000-0000-0000-0000-0000000000f1',
   '24470000-0000-0000-0000-0000000000a3',
   'hold-2447-test',
   now() + interval '5 minutes');

-- Cabinet B (pas de hold — pour vérifier la non-fuite)
SET LOCAL app.current_cabinet_id = '24470000-0000-0000-0000-000000000002';

INSERT INTO cabinet (id, raison_sociale) VALUES
  ('24470000-0000-0000-0000-000000000002', 'Cabinet Hold-RLS B');

-- ===========================================================================
-- 1. Cabinet A voit ses holds.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '24470000-0000-0000-0000-000000000001';

SELECT is(
  (SELECT count(*)::int FROM slot_holds
   WHERE id = '24470000-0000-0000-0000-000000000100'),
  1,
  '⭐ cabinet A : voit son hold (slot lié au cabinet A)');

-- ===========================================================================
-- 2. Cabinet B ne voit pas les holds du cabinet A.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '24470000-0000-0000-0000-000000000002';

SELECT is(
  (SELECT count(*)::int FROM slot_holds
   WHERE id = '24470000-0000-0000-0000-000000000100'),
  0,
  '⭐ cabinet B : ne voit pas le hold du cabinet A (isolation RLS)');

-- ===========================================================================
-- 3. GUC absent → 0 rows (fail-closed).
-- ===========================================================================
RESET app.current_cabinet_id;

SELECT is(
  (SELECT count(*)::int FROM slot_holds
   WHERE id = '24470000-0000-0000-0000-000000000100'),
  0,
  '⭐ fail-closed : aucun hold visible sans app.current_cabinet_id');

SELECT * FROM finish();
ROLLBACK;
