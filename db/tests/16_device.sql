-- 16_device.sql — Structure + RLS device (FCM push tokens, issue #696).
-- Vérifie : colonnes/types/défauts, UNIQUE partiel, RLS fail-closed + non-fuite inter-user, FK.
-- Tourne sous nubia_app (NOSUPERUSER, NOBYPASSRLS) — GUC app.current_user_id scopé.
BEGIN;
SELECT * FROM no_plan();

-- ===========================================================================
-- 1. Structure de la table device
-- ===========================================================================
SELECT has_table('device', 'device : table présente');
SELECT has_column('device', 'id',             'device.id présent');
SELECT col_type_is('device', 'id', 'uuid',    'device.id uuid');
SELECT col_has_default('device', 'id',        'device.id DEFAULT gen_random_uuid()');

SELECT has_column('device', 'app_user_id',    'device.app_user_id présent');
SELECT col_type_is('device', 'app_user_id', 'uuid', 'device.app_user_id uuid');
SELECT col_not_null('device', 'app_user_id',  'device.app_user_id NOT NULL');

SELECT has_column('device', 'fcm_token',      'device.fcm_token présent');
SELECT col_not_null('device', 'fcm_token',    'device.fcm_token NOT NULL');

SELECT has_column('device', 'platform',       'device.platform présent');
SELECT col_not_null('device', 'platform',     'device.platform NOT NULL');

SELECT has_column('device', 'active',         'device.active présent');
SELECT col_not_null('device', 'active',       'device.active NOT NULL');
SELECT col_has_default('device', 'active',    'device.active DEFAULT true');

SELECT has_column('device', 'created_at',     'device.created_at présent');
SELECT col_not_null('device', 'created_at',   'device.created_at NOT NULL');
SELECT col_has_default('device', 'created_at','device.created_at DEFAULT now()');

SELECT has_column('device', 'deleted_at',     'device.deleted_at présent (soft-delete)');
SELECT col_is_null('device', 'deleted_at',    'device.deleted_at nullable');

-- ===========================================================================
-- 2. UNIQUE partiel (app_user_id, platform) WHERE deleted_at IS NULL
-- ===========================================================================
SELECT ok(
  EXISTS(SELECT 1 FROM pg_indexes
    WHERE tablename = 'device'
      AND indexname = 'idx_device_active_platform'
      AND indexdef LIKE '%UNIQUE%'),
  'device : index UNIQUE partiel idx_device_active_platform présent');

-- ===========================================================================
-- 3. RLS : ENABLE + FORCE + policy présente
-- ===========================================================================
SELECT ok( (SELECT relrowsecurity     FROM pg_class WHERE relname = 'device'),
  'device : ROW LEVEL SECURITY activée');
SELECT ok( (SELECT relforcerowsecurity FROM pg_class WHERE relname = 'device'),
  'device : FORCE ROW LEVEL SECURITY');
SELECT ok( EXISTS(SELECT 1 FROM pg_policies WHERE tablename = 'device' AND policyname = 'device_owner'),
  'device : policy device_owner présente');

-- ===========================================================================
-- Fixtures : deux utilisateurs platform.
-- INSERT via device_owner WITH CHECK (GUC positionné).
-- ===========================================================================
INSERT INTO app_user (id, email, password_hash, kind)
  VALUES ('f6000000-0000-0000-0000-0000000000a1', 'device.a@example.test', '$argon2id$fixture', 'patient');
INSERT INTO app_user (id, email, password_hash, kind)
  VALUES ('f6000000-0000-0000-0000-0000000000a2', 'device.b@example.test', '$argon2id$fixture', 'patient');

SET LOCAL app.current_user_id = 'f6000000-0000-0000-0000-0000000000a1';
INSERT INTO device (id, app_user_id, fcm_token, platform)
  VALUES ('f6000000-0000-0000-0000-000000000001',
          'f6000000-0000-0000-0000-0000000000a1',
          'fcm_token_a_ios', 'ios');

SET LOCAL app.current_user_id = 'f6000000-0000-0000-0000-0000000000a2';
INSERT INTO device (id, app_user_id, fcm_token, platform)
  VALUES ('f6000000-0000-0000-0000-000000000002',
          'f6000000-0000-0000-0000-0000000000a2',
          'fcm_token_b_android', 'android');

-- ===========================================================================
-- 4. FAIL-CLOSED (sans GUC → 0 ligne visible)
-- ===========================================================================
RESET app.current_user_id;
SELECT is(
  (SELECT count(*) FROM device
   WHERE id IN ('f6000000-0000-0000-0000-000000000001',
                'f6000000-0000-0000-0000-000000000002'))::int, 0,
  '⭐ fail-closed device : aucun device visible sans app.current_user_id');

-- ===========================================================================
-- 5. ISOLATION inter-user (non-fuite)
-- ===========================================================================
SET LOCAL app.current_user_id = 'f6000000-0000-0000-0000-0000000000a1';
SELECT is(
  (SELECT count(*) FROM device
   WHERE id IN ('f6000000-0000-0000-0000-000000000001',
                'f6000000-0000-0000-0000-000000000002'))::int, 1,
  'device contexte user A : 1 device visible (le sien)');
SELECT is(
  (SELECT count(*) FROM device WHERE id = 'f6000000-0000-0000-0000-000000000002')::int, 0,
  '⭐ non-fuite device : user A ne voit PAS le device de user B');

SET LOCAL app.current_user_id = 'f6000000-0000-0000-0000-0000000000a2';
SELECT is(
  (SELECT count(*) FROM device
   WHERE id IN ('f6000000-0000-0000-0000-000000000001',
                'f6000000-0000-0000-0000-000000000002'))::int, 1,
  'device contexte user B : 1 device visible (le sien)');
SELECT is(
  (SELECT count(*) FROM device WHERE id = 'f6000000-0000-0000-0000-000000000001')::int, 0,
  '⭐ non-fuite device : user B ne voit PAS le device de user A');

-- ===========================================================================
-- 6. UNICITÉ (app_user_id, platform) — doublon refusé (23505)
-- ===========================================================================
SELECT throws_ok(
  $$ INSERT INTO device (app_user_id, fcm_token, platform)
     VALUES ('f6000000-0000-0000-0000-0000000000a2',
             'fcm_token_b_dup', 'android') $$,
  '23505', NULL,
  '⭐ device UNIQUE(app_user_id, platform) → doublon refusé (23505)');

-- ===========================================================================
-- 7. FK → app_user (23503 si user inexistant)
-- ===========================================================================
SET LOCAL app.current_user_id = '00000000-0000-0000-0000-000000000099';
SELECT throws_ok(
  $$ INSERT INTO device (app_user_id, fcm_token, platform)
     VALUES ('00000000-0000-0000-0000-000000000099',
             'fcm_orphan', 'web') $$,
  '23503', NULL,
  'device.app_user_id FK → app_user.id (23503 si user inexistant)');

SELECT * FROM finish();
ROLLBACK;
