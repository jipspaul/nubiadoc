-- 19_messaging_rls.sql — RLS conversation + message (issue #823).
-- Tests : isolation tenant · écriture cross-cabinet refusée · fail-closed.
-- Exécuté par pg_prove sous nubia_app (NOSUPERUSER, NOBYPASSRLS).
BEGIN;
SELECT * FROM no_plan();

-- ===========================================================================
-- Fixtures : deux cabinets C1 et C2, chacun avec un patient.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = 'c1000000-0000-0000-0000-000000000001';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('c1000000-0000-0000-0000-000000000001', 'Cabinet Msg-1');
INSERT INTO patient (id, cabinet_id, first_name, last_name) VALUES
  ('c1000000-0000-0000-0000-000000000011', 'c1000000-0000-0000-0000-000000000001', 'Alice', 'Msg');

SET LOCAL app.current_cabinet_id = 'c2000000-0000-0000-0000-000000000002';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('c2000000-0000-0000-0000-000000000002', 'Cabinet Msg-2');
INSERT INTO patient (id, cabinet_id, first_name, last_name) VALUES
  ('c2000000-0000-0000-0000-000000000022', 'c2000000-0000-0000-0000-000000000002', 'Bob', 'Msg');

-- Conversation dans C1, message associé.
SET LOCAL app.current_cabinet_id = 'c1000000-0000-0000-0000-000000000001';
INSERT INTO conversation (id, cabinet_id, patient_id, scope, status) VALUES
  ('c1000000-0000-0000-0000-00000000ff01',
   'c1000000-0000-0000-0000-000000000001',
   'c1000000-0000-0000-0000-000000000011',
   'patient_cabinet', 'open');
INSERT INTO message (id, cabinet_id, conversation_id, sender_kind, body_ciphertext, body_key_ref) VALUES
  ('c1000000-0000-0000-0000-00000000ee01',
   'c1000000-0000-0000-0000-000000000001',
   'c1000000-0000-0000-0000-00000000ff01',
   'patient', '\xDEADBEEF', 'key_c1');

-- Conversation dans C2, message associé.
SET LOCAL app.current_cabinet_id = 'c2000000-0000-0000-0000-000000000002';
INSERT INTO conversation (id, cabinet_id, patient_id, scope, status) VALUES
  ('c2000000-0000-0000-0000-00000000ff02',
   'c2000000-0000-0000-0000-000000000002',
   'c2000000-0000-0000-0000-000000000022',
   'patient_cabinet', 'open');
INSERT INTO message (id, cabinet_id, conversation_id, sender_kind, body_ciphertext, body_key_ref) VALUES
  ('c2000000-0000-0000-0000-00000000ee02',
   'c2000000-0000-0000-0000-000000000002',
   'c2000000-0000-0000-0000-00000000ff02',
   'patient', '\xCAFEBABE', 'key_c2');

-- ===========================================================================
-- 1. FAIL-CLOSED : sans GUC → 0 conversation et 0 message visibles.
-- ===========================================================================
RESET app.current_cabinet_id;
SELECT is( (SELECT count(*)::int FROM conversation), 0,
  '⭐ fail-closed conversation : 0 visible sans app.current_cabinet_id');
SELECT is( (SELECT count(*)::int FROM message), 0,
  '⭐ fail-closed message : 0 visible sans app.current_cabinet_id');

-- ===========================================================================
-- 2. ISOLATION : contexte C1 → on voit C1 seulement.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = 'c1000000-0000-0000-0000-000000000001';
SELECT is( (SELECT count(*)::int FROM conversation), 1,
  'contexte C1 : 1 conversation visible');
SELECT is( (SELECT count(*)::int FROM message), 1,
  'contexte C1 : 1 message visible');
SELECT is(
  (SELECT count(*)::int FROM conversation
   WHERE cabinet_id = 'c2000000-0000-0000-0000-000000000002'), 0,
  '⭐ non-fuite conversation : C1 ne voit PAS la conversation de C2');
SELECT is(
  (SELECT count(*)::int FROM message
   WHERE cabinet_id = 'c2000000-0000-0000-0000-000000000002'), 0,
  '⭐ non-fuite message : C1 ne voit PAS les messages de C2');

-- Contexte C2 : symétrique.
SET LOCAL app.current_cabinet_id = 'c2000000-0000-0000-0000-000000000002';
SELECT is( (SELECT count(*)::int FROM conversation), 1,
  'contexte C2 : 1 conversation visible');
SELECT is( (SELECT count(*)::int FROM message), 1,
  'contexte C2 : 1 message visible');

-- ===========================================================================
-- 3. WITH CHECK — écriture cross-cabinet refusée (conversation + message).
-- ===========================================================================
-- Contexte C2 : tenter d'insérer une conversation dans C1.
SELECT throws_ok(
  $$ INSERT INTO conversation (cabinet_id, scope, status)
     VALUES ('c1000000-0000-0000-0000-000000000001', 'patient_cabinet', 'open') $$,
  '42501', NULL,
  '⭐ WITH CHECK conversation : écrire dans C1 depuis contexte C2 refusé');

-- Tenter d'insérer un message dans C1.
SELECT throws_ok(
  $$ INSERT INTO message (cabinet_id, conversation_id, sender_kind, body_ciphertext, body_key_ref)
     VALUES ('c1000000-0000-0000-0000-000000000001',
             'c1000000-0000-0000-0000-00000000ff01',
             'secretary', '\xAABBCC', 'key_pirate') $$,
  '42501', NULL,
  '⭐ WITH CHECK message : écrire dans C1 depuis contexte C2 refusé');

-- ===========================================================================
-- 4. Schéma : colonnes soft-delete et chiffrement (issue #823).
-- ===========================================================================
SELECT has_column('conversation', 'deleted_at',
  'conversation.deleted_at présente (soft-delete, 0057)');
SELECT col_type_is('conversation', 'deleted_at', 'timestamp with time zone',
  'conversation.deleted_at timestamptz');
SELECT col_is_null('conversation', 'deleted_at',
  'conversation.deleted_at nullable (actif par défaut)');

SELECT col_type_is('message', 'body_ciphertext', 'bytea',
  'message.body_ciphertext bytea (chiffré)');
SELECT col_not_null('message', 'body_ciphertext',
  'message.body_ciphertext NOT NULL');
SELECT col_not_null('message', 'body_key_ref',
  'message.body_key_ref NOT NULL');

SELECT col_has_default('message', 'triage_flag',
  'message.triage_flag a un défaut');
SELECT is(
  (SELECT pg_get_expr(d.adbin, d.adrelid)
     FROM pg_attrdef d JOIN pg_attribute a ON a.attrelid = d.adrelid AND a.attnum = d.adnum
    WHERE d.adrelid = 'message'::regclass AND a.attname = 'triage_flag'),
  '''normal''::text',
  'message.triage_flag défaut = normal');

-- ===========================================================================
-- 5. RLS activée + FORCE sur les deux tables.
-- ===========================================================================
SELECT ok( (SELECT relrowsecurity FROM pg_class WHERE relname = 'conversation'),
  'conversation : ROW LEVEL SECURITY activée');
SELECT ok( (SELECT relforcerowsecurity FROM pg_class WHERE relname = 'conversation'),
  'conversation : FORCE ROW LEVEL SECURITY');
SELECT ok( EXISTS(SELECT 1 FROM pg_policies WHERE tablename = 'conversation' AND policyname = 'tenant_isolation'),
  'conversation : policy tenant_isolation présente');

SELECT ok( (SELECT relrowsecurity FROM pg_class WHERE relname = 'message'),
  'message : ROW LEVEL SECURITY activée');
SELECT ok( (SELECT relforcerowsecurity FROM pg_class WHERE relname = 'message'),
  'message : FORCE ROW LEVEL SECURITY');
SELECT ok( EXISTS(SELECT 1 FROM pg_policies WHERE tablename = 'message' AND policyname = 'tenant_isolation'),
  'message : policy tenant_isolation présente');

SELECT * FROM finish();
ROLLBACK;
