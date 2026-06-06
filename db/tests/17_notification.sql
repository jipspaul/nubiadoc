-- 17_notification.sql — Structure + RLS notification (centre notifs in-app, issue #697).
-- Vérifie : colonnes/types/défauts, index, RLS fail-closed + non-fuite inter-user,
--           mise à jour statut de lecture, append-only (pas de DELETE), FORCE RLS.
-- Tourne sous nubia_app (NOSUPERUSER, NOBYPASSRLS) — GUC app.current_user_id scopé.
BEGIN;
SELECT * FROM no_plan();

-- ===========================================================================
-- 1. Structure de la table notification
-- ===========================================================================
SELECT has_table('notification', 'notification : table présente');

SELECT has_column('notification', 'id',              'notification.id présent');
SELECT col_type_is('notification', 'id', 'uuid',     'notification.id uuid');
SELECT col_has_default('notification', 'id',         'notification.id DEFAULT gen_random_uuid()');

SELECT has_column('notification', 'app_user_id',     'notification.app_user_id présent');
SELECT col_type_is('notification', 'app_user_id', 'uuid', 'notification.app_user_id uuid');
SELECT col_not_null('notification', 'app_user_id',   'notification.app_user_id NOT NULL');

SELECT has_column('notification', 'kind',            'notification.kind présent');
SELECT col_not_null('notification', 'kind',          'notification.kind NOT NULL');

SELECT has_column('notification', 'title',           'notification.title présent');
SELECT col_not_null('notification', 'title',         'notification.title NOT NULL');

SELECT has_column('notification', 'body_ciphertext', 'notification.body_ciphertext présent');
SELECT col_type_is('notification', 'body_ciphertext', 'bytea', 'notification.body_ciphertext bytea (chiffré KMS)');
SELECT col_not_null('notification', 'body_ciphertext', 'notification.body_ciphertext NOT NULL');

SELECT has_column('notification', 'body_key_ref',    'notification.body_key_ref présent');
SELECT col_type_is('notification', 'body_key_ref', 'text', 'notification.body_key_ref text');
SELECT col_not_null('notification', 'body_key_ref',  'notification.body_key_ref NOT NULL');

SELECT has_column('notification', 'data',            'notification.data présent');
SELECT col_type_is('notification', 'data', 'jsonb',  'notification.data jsonb');
SELECT col_not_null('notification', 'data',          'notification.data NOT NULL');
SELECT col_has_default('notification', 'data',       'notification.data DEFAULT {}');

SELECT has_column('notification', 'is_read',         'notification.is_read présent');
SELECT col_type_is('notification', 'is_read', 'boolean', 'notification.is_read boolean');
SELECT col_not_null('notification', 'is_read',       'notification.is_read NOT NULL');
SELECT col_has_default('notification', 'is_read',    'notification.is_read DEFAULT false');

SELECT has_column('notification', 'created_at',      'notification.created_at présent');
SELECT col_type_is('notification', 'created_at', 'timestamp with time zone', 'notification.created_at timestamptz');
SELECT col_not_null('notification', 'created_at',    'notification.created_at NOT NULL');
SELECT col_has_default('notification', 'created_at', 'notification.created_at DEFAULT now()');

SELECT has_column('notification', 'read_at',         'notification.read_at présent');
SELECT col_type_is('notification', 'read_at', 'timestamp with time zone', 'notification.read_at timestamptz');
SELECT col_is_null('notification', 'read_at',        'notification.read_at nullable');

-- ===========================================================================
-- 2. Index (app_user_id, is_read, created_at DESC)
-- ===========================================================================
SELECT ok(
  EXISTS(SELECT 1 FROM pg_indexes
    WHERE tablename = 'notification'
      AND indexname = 'idx_notification_user_read_created'),
  'notification : index idx_notification_user_read_created présent');

-- ===========================================================================
-- 3. RLS : ENABLE + FORCE + policies présentes
-- ===========================================================================
SELECT ok( (SELECT relrowsecurity      FROM pg_class WHERE relname = 'notification'),
  'notification : ROW LEVEL SECURITY activée');
SELECT ok( (SELECT relforcerowsecurity FROM pg_class WHERE relname = 'notification'),
  '⭐ notification : FORCE ROW LEVEL SECURITY');

SELECT ok( EXISTS(SELECT 1 FROM pg_policies
    WHERE tablename = 'notification' AND policyname = 'notification_owner_select'),
  'notification : policy notification_owner_select présente');
SELECT ok( EXISTS(SELECT 1 FROM pg_policies
    WHERE tablename = 'notification' AND policyname = 'notification_owner_insert'),
  'notification : policy notification_owner_insert présente');
SELECT ok( EXISTS(SELECT 1 FROM pg_policies
    WHERE tablename = 'notification' AND policyname = 'notification_owner_update'),
  'notification : policy notification_owner_update présente');

-- ===========================================================================
-- Fixtures : deux utilisateurs plateforme.
-- INSERT borné par notification_owner_insert WITH CHECK (GUC positionné).
-- ===========================================================================
INSERT INTO app_user (id, email, password_hash, kind)
  VALUES ('f7000000-0000-0000-0000-0000000000a1', 'notif.a@example.test', '$argon2id$fixture', 'patient');
INSERT INTO app_user (id, email, password_hash, kind)
  VALUES ('f7000000-0000-0000-0000-0000000000a2', 'notif.b@example.test', '$argon2id$fixture', 'patient');

SET LOCAL app.current_user_id = 'f7000000-0000-0000-0000-0000000000a1';
INSERT INTO notification (id, app_user_id, kind, title, body_ciphertext, body_key_ref)
  VALUES ('f7000000-0000-0000-0000-000000000001',
          'f7000000-0000-0000-0000-0000000000a1',
          'rdv_rappel', 'Rappel RDV', '\xDEADBEEF', 'SEED_PLACEHOLDER');

SET LOCAL app.current_user_id = 'f7000000-0000-0000-0000-0000000000a2';
INSERT INTO notification (id, app_user_id, kind, title, body_ciphertext, body_key_ref)
  VALUES ('f7000000-0000-0000-0000-000000000002',
          'f7000000-0000-0000-0000-0000000000a2',
          'message', 'Nouveau message', '\xCAFEBABE', 'SEED_PLACEHOLDER');

-- ===========================================================================
-- 4. FAIL-CLOSED (sans GUC → 0 ligne visible)
-- ===========================================================================
RESET app.current_user_id;
SELECT is(
  (SELECT count(*) FROM notification
   WHERE id IN ('f7000000-0000-0000-0000-000000000001',
                'f7000000-0000-0000-0000-000000000002'))::int, 0,
  '⭐ fail-closed notification : aucune notification visible sans app.current_user_id');

-- ===========================================================================
-- 5. ISOLATION inter-user (non-fuite)
-- ===========================================================================
SET LOCAL app.current_user_id = 'f7000000-0000-0000-0000-0000000000a1';
SELECT is(
  (SELECT count(*) FROM notification
   WHERE id IN ('f7000000-0000-0000-0000-000000000001',
                'f7000000-0000-0000-0000-000000000002'))::int, 1,
  'notification contexte user A : 1 notification visible (la sienne)');
SELECT is(
  (SELECT count(*) FROM notification WHERE id = 'f7000000-0000-0000-0000-000000000002')::int, 0,
  '⭐ non-fuite notification : user A ne voit PAS la notification de user B');

SET LOCAL app.current_user_id = 'f7000000-0000-0000-0000-0000000000a2';
SELECT is(
  (SELECT count(*) FROM notification
   WHERE id IN ('f7000000-0000-0000-0000-000000000001',
                'f7000000-0000-0000-0000-000000000002'))::int, 1,
  'notification contexte user B : 1 notification visible (la sienne)');
SELECT is(
  (SELECT count(*) FROM notification WHERE id = 'f7000000-0000-0000-0000-000000000001')::int, 0,
  '⭐ non-fuite notification : user B ne voit PAS la notification de user A');

-- ===========================================================================
-- 6. Mise à jour du statut de lecture (is_read, read_at)
-- ===========================================================================
SET LOCAL app.current_user_id = 'f7000000-0000-0000-0000-0000000000a2';
UPDATE notification
   SET is_read = true, read_at = '2026-06-06 10:00:00+00'
 WHERE id = 'f7000000-0000-0000-0000-000000000002';

SELECT is(
  (SELECT is_read FROM notification WHERE id = 'f7000000-0000-0000-0000-000000000002'),
  true,
  'notification : is_read passé à true après UPDATE');
SELECT ok(
  (SELECT read_at FROM notification WHERE id = 'f7000000-0000-0000-0000-000000000002') IS NOT NULL,
  'notification : read_at renseigné après marque de lecture');

-- ===========================================================================
-- 7. APPEND-ONLY : nubia_app ne peut pas DELETE une notification
-- ===========================================================================
SELECT throws_ok(
  $$ DELETE FROM notification WHERE id = 'f7000000-0000-0000-0000-000000000002' $$,
  '42501', NULL,
  '⭐ append-only notification : DELETE refusé pour nubia_app (42501)');

-- ===========================================================================
-- 8. FK → app_user (23503 si user inexistant)
-- ===========================================================================
SET LOCAL app.current_user_id = '00000000-0000-0000-0000-000000000099';
SELECT throws_ok(
  $$ INSERT INTO notification (app_user_id, kind, title, body_ciphertext, body_key_ref)
     VALUES ('00000000-0000-0000-0000-000000000099',
             'test', 'Test', '\x00', 'SEED_PLACEHOLDER') $$,
  '23503', NULL,
  'notification.app_user_id FK → app_user.id (23503 si user inexistant)');

SELECT * FROM finish();
ROLLBACK;
