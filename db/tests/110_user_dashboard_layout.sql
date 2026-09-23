-- 110_user_dashboard_layout.sql — Structure + RLS user_dashboard_layout (issue #7162).
-- Vérifie : colonnes/types/défauts, UNIQUE (app_user_id, app), RLS fail-closed +
--           non-fuite inter-user, FK app_user.
-- Tourne sous nubia_app (NOSUPERUSER, NOBYPASSRLS) — GUC app.current_user_id scopé.
BEGIN;
SELECT * FROM no_plan();

-- ===========================================================================
-- 1. Structure de la table user_dashboard_layout
-- ===========================================================================
SELECT has_table('user_dashboard_layout', 'user_dashboard_layout : table présente');
SELECT has_column('user_dashboard_layout', 'id',              'user_dashboard_layout.id présent');
SELECT col_type_is('user_dashboard_layout', 'id', 'uuid',     'user_dashboard_layout.id uuid');
SELECT col_has_default('user_dashboard_layout', 'id',         'user_dashboard_layout.id DEFAULT gen_random_uuid()');

SELECT has_column('user_dashboard_layout', 'app_user_id',     'user_dashboard_layout.app_user_id présent');
SELECT col_type_is('user_dashboard_layout', 'app_user_id', 'uuid', 'user_dashboard_layout.app_user_id uuid');
SELECT col_not_null('user_dashboard_layout', 'app_user_id',   'user_dashboard_layout.app_user_id NOT NULL');

SELECT has_column('user_dashboard_layout', 'app',             'user_dashboard_layout.app présent');
SELECT col_not_null('user_dashboard_layout', 'app',           'user_dashboard_layout.app NOT NULL');

SELECT has_column('user_dashboard_layout', 'layout',          'user_dashboard_layout.layout présent');
SELECT col_type_is('user_dashboard_layout', 'layout', 'jsonb','user_dashboard_layout.layout jsonb');
SELECT col_not_null('user_dashboard_layout', 'layout',        'user_dashboard_layout.layout NOT NULL');
SELECT col_has_default('user_dashboard_layout', 'layout',     'user_dashboard_layout.layout DEFAULT []');

SELECT has_column('user_dashboard_layout', 'created_at',      'user_dashboard_layout.created_at présent');
SELECT has_column('user_dashboard_layout', 'updated_at',      'user_dashboard_layout.updated_at présent');

-- ===========================================================================
-- 2. UNIQUE (app_user_id, app)
-- ===========================================================================
SELECT ok(
  EXISTS(SELECT 1 FROM pg_constraint
    WHERE conrelid = 'user_dashboard_layout'::regclass
      AND contype = 'u'
      AND conkey = (
        SELECT array_agg(attnum ORDER BY attnum) FROM pg_attribute
        WHERE attrelid = 'user_dashboard_layout'::regclass
          AND attname IN ('app_user_id', 'app')
      )),
  'user_dashboard_layout : UNIQUE (app_user_id, app) présente');

-- ===========================================================================
-- 3. RLS : ENABLE + FORCE + policies présentes
-- ===========================================================================
SELECT ok( (SELECT relrowsecurity FROM pg_class WHERE relname = 'user_dashboard_layout'),
  'user_dashboard_layout : ROW LEVEL SECURITY activée');
SELECT ok( (SELECT relforcerowsecurity FROM pg_class WHERE relname = 'user_dashboard_layout'),
  'user_dashboard_layout : FORCE ROW LEVEL SECURITY');
SELECT ok( EXISTS(SELECT 1 FROM pg_policies
    WHERE tablename = 'user_dashboard_layout' AND policyname = 'user_dashboard_layout_owner_select'),
  'user_dashboard_layout : policy owner_select présente');
SELECT ok( EXISTS(SELECT 1 FROM pg_policies
    WHERE tablename = 'user_dashboard_layout' AND policyname = 'user_dashboard_layout_owner_insert'),
  'user_dashboard_layout : policy owner_insert présente');
SELECT ok( EXISTS(SELECT 1 FROM pg_policies
    WHERE tablename = 'user_dashboard_layout' AND policyname = 'user_dashboard_layout_owner_update'),
  'user_dashboard_layout : policy owner_update présente');

-- ===========================================================================
-- Fixtures : deux utilisateurs platform.
-- INSERT via owner_insert WITH CHECK (GUC positionné).
-- ===========================================================================
INSERT INTO app_user (id, email, password_hash, kind)
  VALUES ('f7000000-0000-0000-0000-0000000000a1', 'dashlayout.a@example.test', '$argon2id$fixture', 'pro');
INSERT INTO app_user (id, email, password_hash, kind)
  VALUES ('f7000000-0000-0000-0000-0000000000a2', 'dashlayout.b@example.test', '$argon2id$fixture', 'pro');

SET LOCAL app.current_user_id = 'f7000000-0000-0000-0000-0000000000a1';
INSERT INTO user_dashboard_layout (id, app_user_id, app, layout)
  VALUES ('f7000000-0000-0000-0000-000000000001',
          'f7000000-0000-0000-0000-0000000000a1',
          'pro', '["kpi_tiles", "today_schedule"]'::jsonb);

SET LOCAL app.current_user_id = 'f7000000-0000-0000-0000-0000000000a2';
INSERT INTO user_dashboard_layout (id, app_user_id, app, layout)
  VALUES ('f7000000-0000-0000-0000-000000000002',
          'f7000000-0000-0000-0000-0000000000a2',
          'pro', '["today_notes"]'::jsonb);

-- ===========================================================================
-- 4. FAIL-CLOSED (sans GUC → 0 ligne visible)
-- ===========================================================================
RESET app.current_user_id;
SELECT is(
  (SELECT count(*) FROM user_dashboard_layout
   WHERE id IN ('f7000000-0000-0000-0000-000000000001',
                'f7000000-0000-0000-0000-000000000002'))::int, 0,
  '⭐ fail-closed user_dashboard_layout : aucune ligne visible sans app.current_user_id');

-- ===========================================================================
-- 5. ISOLATION inter-user (non-fuite)
-- ===========================================================================
SET LOCAL app.current_user_id = 'f7000000-0000-0000-0000-0000000000a1';
SELECT is(
  (SELECT count(*) FROM user_dashboard_layout
   WHERE id IN ('f7000000-0000-0000-0000-000000000001',
                'f7000000-0000-0000-0000-000000000002'))::int, 1,
  'user_dashboard_layout contexte user A : 1 ligne visible (la sienne)');
SELECT is(
  (SELECT count(*) FROM user_dashboard_layout WHERE id = 'f7000000-0000-0000-0000-000000000002')::int, 0,
  '⭐ non-fuite user_dashboard_layout : user A ne voit PAS la ligne de user B');

SET LOCAL app.current_user_id = 'f7000000-0000-0000-0000-0000000000a2';
SELECT is(
  (SELECT count(*) FROM user_dashboard_layout
   WHERE id IN ('f7000000-0000-0000-0000-000000000001',
                'f7000000-0000-0000-0000-000000000002'))::int, 1,
  'user_dashboard_layout contexte user B : 1 ligne visible (la sienne)');
SELECT is(
  (SELECT count(*) FROM user_dashboard_layout WHERE id = 'f7000000-0000-0000-0000-000000000001')::int, 0,
  '⭐ non-fuite user_dashboard_layout : user B ne voit PAS la ligne de user A');

-- ===========================================================================
-- 6. UNICITÉ (app_user_id, app) — doublon refusé (23505)
-- ===========================================================================
SELECT throws_ok(
  $$ INSERT INTO user_dashboard_layout (app_user_id, app, layout)
     VALUES ('f7000000-0000-0000-0000-0000000000a2', 'pro', '["week_summary"]'::jsonb) $$,
  '23505', NULL,
  '⭐ user_dashboard_layout UNIQUE(app_user_id, app) → doublon refusé (23505)');

-- ===========================================================================
-- 7. FK → app_user (23503 si user inexistant)
-- ===========================================================================
SET LOCAL app.current_user_id = '00000000-0000-0000-0000-000000000099';
SELECT throws_ok(
  $$ INSERT INTO user_dashboard_layout (app_user_id, app, layout)
     VALUES ('00000000-0000-0000-0000-000000000099', 'pro', '[]'::jsonb) $$,
  '23503', NULL,
  'user_dashboard_layout.app_user_id FK → app_user.id (23503 si user inexistant)');

SELECT * FROM finish();
ROLLBACK;
