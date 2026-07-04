-- 45_conversation_pharmacy_rls.sql — Cloisonnement triadique de la messagerie
-- pharmacie (issue #3311, lot B6).
-- Vérifie : un cabinet ne voit JAMAIS une conversation patient_pharmacy et
-- réciproquement · isolation cross-pharmacie · le patient voit ses deux fils ·
-- sender_kind pharmacist accepté · WITH CHECK cross-tenant refusé.
-- Exécuté par pg_prove sous nubia_app. Fixtures BEGIN…ROLLBACK. Préfixe 33110000.

BEGIN;
SELECT * FROM no_plan();

-- Fixtures : compte patient + cabinet A (fil cabinet) + pharmacie X (fil pharmacie).
INSERT INTO app_user (id, email, kind, status)
  VALUES ('33110000-0000-0000-0000-0000000000a1', 'patient-b6@demo-3311.test', 'patient', 'active')
  ON CONFLICT DO NOTHING;
INSERT INTO patient_account (id, app_user_id, first_name, last_name)
  VALUES ('33110000-0000-0000-0000-0000000000b1', '33110000-0000-0000-0000-0000000000a1', 'Jean', 'Demo')
  ON CONFLICT DO NOTHING;

SET LOCAL app.current_cabinet_id = '33110000-0000-0000-0000-000000000001';
INSERT INTO cabinet (id, raison_sociale)
  VALUES ('33110000-0000-0000-0000-000000000001', 'Cabinet B6-A')
  ON CONFLICT DO NOTHING;
INSERT INTO conversation (id, cabinet_id, patient_account_id, scope)
  VALUES ('33110000-0000-0000-0000-000000000051', '33110000-0000-0000-0000-000000000001',
          '33110000-0000-0000-0000-0000000000b1', 'patient_cabinet')
  ON CONFLICT DO NOTHING;
INSERT INTO message (id, cabinet_id, conversation_id, sender_kind, body_ciphertext, body_key_ref)
  VALUES ('33110000-0000-0000-0000-000000000061', '33110000-0000-0000-0000-000000000001',
          '33110000-0000-0000-0000-000000000051', 'patient', '\x00', 'poc-stub')
  ON CONFLICT DO NOTHING;
RESET app.current_cabinet_id;

SET LOCAL app.current_pharmacy_id = '33110000-0000-0000-0000-0000000000f1';
INSERT INTO pharmacy (id, raison_sociale, is_listed)
  VALUES ('33110000-0000-0000-0000-0000000000f1', 'Pharmacie B6-X', true)
  ON CONFLICT DO NOTHING;
INSERT INTO conversation (id, pharmacy_id, patient_account_id, scope, patient_display_name)
  VALUES ('33110000-0000-0000-0000-000000000052', '33110000-0000-0000-0000-0000000000f1',
          '33110000-0000-0000-0000-0000000000b1', 'patient_pharmacy', 'Jean D.')
  ON CONFLICT DO NOTHING;
INSERT INTO message (id, pharmacy_id, conversation_id, sender_kind, body_ciphertext, body_key_ref)
  VALUES ('33110000-0000-0000-0000-000000000062', '33110000-0000-0000-0000-0000000000f1',
          '33110000-0000-0000-0000-000000000052', 'pharmacist', '\x00', 'poc-stub')
  ON CONFLICT DO NOTHING;
RESET app.current_pharmacy_id;

-- 1. CLOISONNEMENT : le cabinet ne voit jamais le fil pharmacie.
SET LOCAL app.current_cabinet_id = '33110000-0000-0000-0000-000000000001';
SELECT is(
  (SELECT count(*)::int FROM conversation WHERE id = '33110000-0000-0000-0000-000000000052'),
  0, '⭐ cloisonnement : le cabinet ne voit pas la conversation patient_pharmacy');
SELECT is(
  (SELECT count(*)::int FROM message WHERE id = '33110000-0000-0000-0000-000000000062'),
  0, '⭐ cloisonnement : le cabinet ne voit pas les messages pharmacie');
RESET app.current_cabinet_id;

-- 2. CLOISONNEMENT : la pharmacie ne voit jamais le fil cabinet.
SET LOCAL app.current_pharmacy_id = '33110000-0000-0000-0000-0000000000f1';
SELECT is(
  (SELECT count(*)::int FROM conversation WHERE id = '33110000-0000-0000-0000-000000000051'),
  0, '⭐ cloisonnement : la pharmacie ne voit pas la conversation cabinet');
SELECT is(
  (SELECT count(*)::int FROM message WHERE id = '33110000-0000-0000-0000-000000000061'),
  0, '⭐ cloisonnement : la pharmacie ne voit pas les messages cabinet');
SELECT is(
  (SELECT count(*)::int FROM conversation WHERE id = '33110000-0000-0000-0000-000000000052'),
  1, 'la pharmacie voit son propre fil');

-- 3. Isolation cross-pharmacie.
SET LOCAL app.current_pharmacy_id = '33110000-0000-0000-0000-0000000000f2';
SELECT is(
  (SELECT count(*)::int FROM conversation WHERE id = '33110000-0000-0000-0000-000000000052'),
  0, '⭐ non-fuite : une autre pharmacie ne voit rien');
RESET app.current_pharmacy_id;

-- 4. Le patient voit ses DEUX fils (cabinet + pharmacie).
SET LOCAL app.patient_account_id = '33110000-0000-0000-0000-0000000000b1';
SELECT is(
  (SELECT count(*)::int FROM conversation
   WHERE id IN ('33110000-0000-0000-0000-000000000051','33110000-0000-0000-0000-000000000052')),
  2, 'le patient voit ses fils cabinet ET pharmacie');
RESET app.patient_account_id;

-- 5. WITH CHECK : une pharmacie ne peut pas écrire dans le fil d'une autre.
SET LOCAL app.current_pharmacy_id = '33110000-0000-0000-0000-0000000000f2';
SELECT throws_ok(
  $$ INSERT INTO message (pharmacy_id, conversation_id, sender_kind, body_ciphertext, body_key_ref)
     VALUES ('33110000-0000-0000-0000-0000000000f1', '33110000-0000-0000-0000-000000000052',
             'pharmacist', '\x00', 'poc-stub') $$,
  '42501', NULL,
  '⭐ WITH CHECK : écrire pour une autre pharmacie refusé');
RESET app.current_pharmacy_id;

-- 6. Contrainte de scope : pharmacy_id sans scope patient_pharmacy refusé.
SET LOCAL app.current_pharmacy_id = '33110000-0000-0000-0000-0000000000f1';
SELECT throws_ok(
  $$ INSERT INTO conversation (pharmacy_id, patient_account_id, scope)
     VALUES ('33110000-0000-0000-0000-0000000000f1',
             '33110000-0000-0000-0000-0000000000b1', 'patient_cabinet') $$,
  '23514', NULL,
  '⭐ CHECK : pharmacy_id exige le scope patient_pharmacy');
RESET app.current_pharmacy_id;

SELECT * FROM finish();
ROLLBACK;
