-- 114_conversation_cabinet_qualification.sql
-- pgTAP : qualification des conversations cabinet (migration 0298, #7152).
--   CQ1.  has_index idx_conversation_cabinet_status_priority sur (cabinet_id, status, priority).
--   CQ2.  Cabinet A crée une conversation qualifiée (origin/motif/priority/
--         assignee_user_id/summary/status='in_progress') OK.
--   CQ3.  status='done' accepté (élargissement de l'énumération) OK.
--   CQ4.  origin hors énumération refusé (23514).
--   CQ5.  priority hors énumération refusée (23514).
--   CQ6.  status hors énumération refusé (23514).
--   CQ7.  assignee_user_id référençant un app_user inexistant refusé (23503).
-- Exécuté par pg_prove sous nubia_app (NOSUPERUSER, NOBYPASSRLS).
-- Fixtures auto-contenues (BEGIN…ROLLBACK). Préfixe UUID 71520000.
-- Issue : #7152

BEGIN;
SELECT plan(7);

-- ===========================================================================
-- CQ1. Index composite (cabinet_id, status, priority).
-- ===========================================================================
SELECT has_index('conversation', 'idx_conversation_cabinet_status_priority',
  ARRAY['cabinet_id', 'status', 'priority'],
  'CQ1 idx_conversation_cabinet_status_priority présent sur (cabinet_id, status, priority)');

-- ===========================================================================
-- Fixtures : 1 cabinet, 1 patient, 1 app_user (assignee).
-- ===========================================================================
INSERT INTO app_user (id, email, password_hash, kind, status) VALUES
  ('71520000-0000-0000-0000-0000000000a1', 'secretaire.7152@nubia.test', '$argon2id$fixture', 'pro', 'active');

SET LOCAL app.current_cabinet_id = '71520000-0000-0000-0000-000000000c01';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('71520000-0000-0000-0000-000000000c01', 'Cabinet Qualification-7152');
INSERT INTO patient (id, cabinet_id, first_name, last_name) VALUES
  ('71520000-0000-0000-0000-000000000e01', '71520000-0000-0000-0000-000000000c01',
   'Patient', 'A');

-- ===========================================================================
-- CQ2. Conversation qualifiée complète OK.
-- ===========================================================================
INSERT INTO conversation
  (id, cabinet_id, patient_id, origin, motif, priority, assignee_user_id, summary, status)
VALUES
  ('71520000-0000-0000-0000-000000000f01', '71520000-0000-0000-0000-000000000c01',
   '71520000-0000-0000-0000-000000000e01', 'phone', 'Douleur dentaire', 'high',
   '71520000-0000-0000-0000-0000000000a1', 'Patiente rappelée, RDV proposé demain matin.',
   'in_progress');
SELECT is(
  (SELECT count(*)::int FROM conversation
   WHERE id = '71520000-0000-0000-0000-000000000f01'),
  1,
  'CQ2 conversation : création cabinet A qualifiée (origin/motif/priority/assignee/summary/status) OK');

-- ===========================================================================
-- CQ3. status='done' accepté.
-- ===========================================================================
UPDATE conversation SET status = 'done'
  WHERE id = '71520000-0000-0000-0000-000000000f01';
SELECT is(
  (SELECT status FROM conversation WHERE id = '71520000-0000-0000-0000-000000000f01'),
  'done',
  'CQ3 conversation_status_check : status=''done'' accepté (élargissement de l''énumération)');

-- ===========================================================================
-- CQ4. origin hors énumération refusé.
-- ===========================================================================
SELECT throws_ok(
  $$ INSERT INTO conversation (cabinet_id, patient_id, origin)
     VALUES ('71520000-0000-0000-0000-000000000c01',
             '71520000-0000-0000-0000-000000000e01', 'fax') $$,
  '23514', NULL,
  'CQ4 conversation_origin_check : origin hors énumération refusé (23514)');

-- ===========================================================================
-- CQ5. priority hors énumération refusée.
-- ===========================================================================
SELECT throws_ok(
  $$ INSERT INTO conversation (cabinet_id, patient_id, priority)
     VALUES ('71520000-0000-0000-0000-000000000c01',
             '71520000-0000-0000-0000-000000000e01', 'critical') $$,
  '23514', NULL,
  'CQ5 conversation_priority_check : priority hors énumération refusée (23514)');

-- ===========================================================================
-- CQ6. status hors énumération refusé.
-- ===========================================================================
SELECT throws_ok(
  $$ INSERT INTO conversation (cabinet_id, patient_id, status)
     VALUES ('71520000-0000-0000-0000-000000000c01',
             '71520000-0000-0000-0000-000000000e01', 'archived') $$,
  '23514', NULL,
  'CQ6 conversation_status_check : status hors énumération refusé (23514)');

-- ===========================================================================
-- CQ7. assignee_user_id référençant un app_user inexistant refusé.
-- ===========================================================================
SELECT throws_ok(
  $$ INSERT INTO conversation (cabinet_id, patient_id, assignee_user_id)
     VALUES ('71520000-0000-0000-0000-000000000c01',
             '71520000-0000-0000-0000-000000000e01',
             '71520000-0000-0000-0000-0000000000ff') $$,
  '23503', NULL,
  'CQ7 conversation_assignee_user_id_fkey : app_user inexistant refusé (23503)');

RESET app.current_cabinet_id;
SELECT * FROM finish();
ROLLBACK;
