-- 91_conversation_secretariat_provider_composite_fk.sql
-- pgTAP : FK composite tenant-scopée — groupes conversation/secretariat/
-- provider, migration 0216, audit #4291.
--   MS1/MS2.  message.conversation_id -> conversation(id, cabinet_id) :
--             légitime OK, exploit cross-cabinet refusé (23503).
--   SM1/SM2.  secretariat_membership.secretariat_id ->
--             secretariat(id, cabinet_id) : légitime OK, exploit
--             cross-cabinet refusé (23503).
--   PV1/PV2.  provider_verification.provider_id -> provider(id, cabinet_id) :
--             légitime OK, exploit cross-cabinet refusé (23503).
--   FC. Fail-closed : sans GUC -> 0 ligne visible.
-- Exécuté par pg_prove sous nubia_app (NOSUPERUSER, NOBYPASSRLS).
-- Fixtures auto-contenues (BEGIN…ROLLBACK). Préfixe UUID 42910006-...
-- Issue : #4291

BEGIN;
SELECT plan(7);

-- ===========================================================================
-- Fixtures : 2 cabinets, chacun avec patient, secretariat, provider.
-- ===========================================================================
INSERT INTO app_user (id, email, kind, status) VALUES
  ('42910006-0000-0000-0000-0000000000a1', 'sec-csp-a@demo-42916.test', 'pro', 'active'),
  ('42910006-0000-0000-0000-0000000000a2', 'sec-csp-b@demo-42916.test', 'pro', 'active');

SET LOCAL app.current_cabinet_id = '42910006-0000-0000-0000-000000000c11';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('42910006-0000-0000-0000-000000000c11', 'Cabinet CSP-4291-A');
INSERT INTO patient (id, cabinet_id, first_name, last_name) VALUES
  ('42910006-0000-0000-0000-000000000e11', '42910006-0000-0000-0000-000000000c11',
   'Patient', 'A');
INSERT INTO conversation (id, cabinet_id, patient_id) VALUES
  ('42910006-0000-0000-0000-000000000f11', '42910006-0000-0000-0000-000000000c11',
   '42910006-0000-0000-0000-000000000e11');
INSERT INTO secretariat (id, cabinet_id, name) VALUES
  ('42910006-0000-0000-0000-000000000611', '42910006-0000-0000-0000-000000000c11',
   'Secrétariat A');
INSERT INTO provider (id, cabinet_id, user_id, display_name) VALUES
  ('42910006-0000-0000-0000-000000000711', '42910006-0000-0000-0000-000000000c11',
   '42910006-0000-0000-0000-0000000000a1', 'Dr Provider A');
RESET app.current_cabinet_id;

SET LOCAL app.current_cabinet_id = '42910006-0000-0000-0000-000000000c12';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('42910006-0000-0000-0000-000000000c12', 'Cabinet CSP-4291-B');
RESET app.current_cabinet_id;

-- ===========================================================================
-- MS1/MS2. message.conversation_id
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '42910006-0000-0000-0000-000000000c11';
INSERT INTO message (cabinet_id, conversation_id, sender_kind, body_ciphertext, body_key_ref) VALUES
  ('42910006-0000-0000-0000-000000000c11', '42910006-0000-0000-0000-000000000f11',
   'secretary', '\x00', 'key-a');
SELECT lives_ok(
  $$ SELECT 1 $$,
  'MS1 message : fixture légitime cabinet A / conversation A insérée sans erreur');
RESET app.current_cabinet_id;
SET LOCAL app.current_cabinet_id = '42910006-0000-0000-0000-000000000c12';
SELECT throws_ok(
  $$ INSERT INTO message (cabinet_id, conversation_id, sender_kind, body_ciphertext, body_key_ref)
     VALUES ('42910006-0000-0000-0000-000000000c12',
             '42910006-0000-0000-0000-000000000f11', 'secretary', '\x00', 'key-b') $$,
  '23503', NULL,
  '⭐ MS2 message : rattacher la conversation d''un autre cabinet refusé (23503, RLS FK)');
RESET app.current_cabinet_id;

-- ===========================================================================
-- SM1/SM2. secretariat_membership.secretariat_id
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '42910006-0000-0000-0000-000000000c11';
INSERT INTO secretariat_membership (cabinet_id, secretariat_id, user_id, role) VALUES
  ('42910006-0000-0000-0000-000000000c11', '42910006-0000-0000-0000-000000000611',
   '42910006-0000-0000-0000-0000000000a1', 'secretary');
SELECT lives_ok(
  $$ SELECT 1 $$,
  'SM1 secretariat_membership : fixture légitime cabinet A / secretariat A insérée sans erreur');
RESET app.current_cabinet_id;
SET LOCAL app.current_cabinet_id = '42910006-0000-0000-0000-000000000c12';
SELECT throws_ok(
  $$ INSERT INTO secretariat_membership (cabinet_id, secretariat_id, user_id, role)
     VALUES ('42910006-0000-0000-0000-000000000c12',
             '42910006-0000-0000-0000-000000000611', '42910006-0000-0000-0000-0000000000a2',
             'secretary') $$,
  '23503', NULL,
  '⭐ SM2 secretariat_membership : rattacher le secretariat d''un autre cabinet refusé (23503, RLS FK)');
RESET app.current_cabinet_id;

-- ===========================================================================
-- PV1/PV2. provider_verification.provider_id
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '42910006-0000-0000-0000-000000000c11';
INSERT INTO provider_verification (cabinet_id, provider_id, identifier, id_type) VALUES
  ('42910006-0000-0000-0000-000000000c11', '42910006-0000-0000-0000-000000000711',
   '12345678901', 'rpps');
SELECT lives_ok(
  $$ SELECT 1 $$,
  'PV1 provider_verification : fixture légitime cabinet A / provider A insérée sans erreur');
RESET app.current_cabinet_id;
SET LOCAL app.current_cabinet_id = '42910006-0000-0000-0000-000000000c12';
SELECT throws_ok(
  $$ INSERT INTO provider_verification (cabinet_id, provider_id, identifier, id_type)
     VALUES ('42910006-0000-0000-0000-000000000c12',
             '42910006-0000-0000-0000-000000000711', '98765432109', 'rpps') $$,
  '23503', NULL,
  '⭐ PV2 provider_verification : rattacher le provider d''un autre cabinet refusé (23503, RLS FK)');
RESET app.current_cabinet_id;

-- ===========================================================================
-- FC. Fail-closed : sans GUC -> 0 ligne visible.
-- ===========================================================================
SELECT is(
  (SELECT count(*)::int FROM message WHERE conversation_id = '42910006-0000-0000-0000-000000000f11')
    + (SELECT count(*)::int FROM secretariat_membership WHERE secretariat_id = '42910006-0000-0000-0000-000000000611')
    + (SELECT count(*)::int FROM provider_verification WHERE provider_id = '42910006-0000-0000-0000-000000000711'),
  0,
  '⭐ FC fail-closed : 0 ligne visible (message/secretariat_membership/provider_verification) sans GUC positionné');

SELECT * FROM finish();
ROLLBACK;
