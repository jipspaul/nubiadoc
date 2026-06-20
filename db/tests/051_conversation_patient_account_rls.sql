-- db/tests/051_conversation_patient_account_rls.sql
-- pgTAP : RLS conversation — isolation inter-compte patient via patient_account_id.
-- Vérifie la policy conversation_patient_read (migration 0101) :
-- seul l'owner du JWT (app.patient_account_id) lit ses conversations.
-- Issue : #2236

BEGIN;
SELECT plan(4);

-- Fixtures : un cabinet commun, deux patient_accounts (A, B), une conversation chacun.
SET LOCAL app.current_cabinet_id = '22360000-0000-0000-0000-000000000001';

INSERT INTO cabinet (id, raison_sociale) VALUES
  ('22360000-0000-0000-0000-000000000001', 'Cabinet RLS-2236');

INSERT INTO app_user (id, email, password_hash, kind) VALUES
  ('22360001-0000-0000-0000-000000000001', 'rls-conv-a-2236@nubia.test', 'hash', 'patient'),
  ('22360001-0000-0000-0000-000000000002', 'rls-conv-b-2236@nubia.test', 'hash', 'patient');

INSERT INTO patient_account (id, app_user_id, first_name, last_name) VALUES
  ('22360002-0000-0000-0000-000000000001', '22360001-0000-0000-0000-000000000001', 'Alice', 'RLS'),
  ('22360002-0000-0000-0000-000000000002', '22360001-0000-0000-0000-000000000002', 'Bob',   'RLS');

-- Conversations sans patient_id (liaison clinique optionnelle depuis 0036).
-- Le WITH CHECK conversation passe car cabinet_id = app.current_cabinet_id.
INSERT INTO conversation (id, cabinet_id, patient_account_id, scope, status) VALUES
  ('22360003-0000-0000-0000-000000000001',
   '22360000-0000-0000-0000-000000000001',
   '22360002-0000-0000-0000-000000000001',
   'patient_cabinet', 'open'),
  ('22360003-0000-0000-0000-000000000002',
   '22360000-0000-0000-0000-000000000001',
   '22360002-0000-0000-0000-000000000002',
   'patient_cabinet', 'open');

-- Passage en contexte patient : on efface le GUC cabinet pour ne tester que
-- la policy conversation_patient_read (tenant_isolation ne doit pas interférer).
RESET app.current_cabinet_id;

-- Test 1 : Patient A voit sa conversation uniquement (1 sur 2 UUIDs testés)
SELECT set_config('app.patient_account_id', '22360002-0000-0000-0000-000000000001', true);
SELECT is(
  (SELECT count(*)::int FROM conversation
   WHERE id IN (
     '22360003-0000-0000-0000-000000000001'::uuid,
     '22360003-0000-0000-0000-000000000002'::uuid)),
  1,
  'Patient A voit uniquement sa conversation (conversation_patient_read)'
);

-- Test 2 : Patient A ne voit pas la conversation de B (cross-account bloqué)
SELECT is(
  (SELECT count(*)::int FROM conversation
   WHERE id = '22360003-0000-0000-0000-000000000002'::uuid),
  0,
  'Patient A ne peut pas voir la conversation de B (isolation inter-compte)'
);

-- Test 3 : Patient B voit sa conversation uniquement
SELECT set_config('app.patient_account_id', '22360002-0000-0000-0000-000000000002', true);
SELECT is(
  (SELECT count(*)::int FROM conversation
   WHERE id IN (
     '22360003-0000-0000-0000-000000000001'::uuid,
     '22360003-0000-0000-0000-000000000002'::uuid)),
  1,
  'Patient B voit uniquement sa conversation (conversation_patient_read)'
);

-- Test 4 : Sans GUC → fail-closed (0 rows)
SELECT set_config('app.patient_account_id', '', true);
SELECT is(
  (SELECT count(*)::int FROM conversation
   WHERE id IN (
     '22360003-0000-0000-0000-000000000001'::uuid,
     '22360003-0000-0000-0000-000000000002'::uuid)),
  0,
  'Sans GUC app.patient_account_id → fail-closed (0 ligne)'
);

SELECT * FROM finish();
ROLLBACK;
