-- 29_conversation_create.sql — Contrat DB pour POST /v1/conversations (issue #1669).
-- Tests :
--   1. INSERT happy path patient : conversation créée avec subject dans le bon cabinet.
--   2. subject nullable : INSERT sans subject accepté.
--   3. 403 unrelated cabinet : WITH CHECK bloque l'INSERT cross-cabinet.
--   4. Schema : colonne subject présente et nullable.
-- Exécuté par pg_prove sous nubia_app (NOSUPERUSER, NOBYPASSRLS).
BEGIN;
SELECT * FROM no_plan();

-- ===========================================================================
-- Fixtures : cabinet C1, patient_account PA1, patient P1.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '16690000-0000-0000-0000-000000000001';

INSERT INTO cabinet (id, raison_sociale) VALUES
  ('16690000-0000-0000-0000-000000000001', 'Cabinet Create-Conv C1');

INSERT INTO app_user (id, email, password_hash, kind) VALUES
  ('16690000-0000-0000-0000-000000000010', 'patient1@1669.test', '$argon2id$fixture', 'patient');

INSERT INTO patient_account (id, app_user_id, first_name, last_name) VALUES
  ('16690000-0000-0000-0000-000000000020',
   '16690000-0000-0000-0000-000000000010', 'Alice', '1669');

INSERT INTO patient (id, cabinet_id, patient_account_id, first_name, last_name) VALUES
  ('16690000-0000-0000-0000-000000000030',
   '16690000-0000-0000-0000-000000000001',
   '16690000-0000-0000-0000-000000000020', 'Alice', '1669');

-- Cabinet C2 (cabinet non lié au patient — pour le test 403).
SET LOCAL app.current_cabinet_id = '16690000-0000-0000-0000-000000000002';

INSERT INTO cabinet (id, raison_sociale) VALUES
  ('16690000-0000-0000-0000-000000000002', 'Cabinet Create-Conv C2');

-- ===========================================================================
-- 1. Happy path : INSERT conversation avec subject dans C1.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '16690000-0000-0000-0000-000000000001';

INSERT INTO conversation (id, cabinet_id, patient_account_id, scope, status, subject)
VALUES (
  '16690000-0000-0000-0000-00000000ff01',
  '16690000-0000-0000-0000-000000000001',
  '16690000-0000-0000-0000-000000000020',
  'patient_cabinet', 'open',
  'Question prothèse'
);

SELECT is(
  (SELECT subject FROM conversation WHERE id = '16690000-0000-0000-0000-00000000ff01'),
  'Question prothèse',
  '⭐ POST /v1/conversations : subject inséré et relu correctement');

SELECT is(
  (SELECT cabinet_id FROM conversation WHERE id = '16690000-0000-0000-0000-00000000ff01'),
  '16690000-0000-0000-0000-000000000001'::uuid,
  '⭐ POST /v1/conversations : cabinet_id correct');

-- ===========================================================================
-- 2. Subject nullable : INSERT sans subject (subject? est optionnel).
-- Utilise patient_account_id NULL pour éviter la contrainte d'unicité
-- (patient_account × cabinet) tout en restant dans C1.
-- ===========================================================================
INSERT INTO conversation (id, cabinet_id, scope, status)
VALUES (
  '16690000-0000-0000-0000-00000000ff02',
  '16690000-0000-0000-0000-000000000001',
  'patient_cabinet', 'open'
);

SELECT is(
  (SELECT subject FROM conversation WHERE id = '16690000-0000-0000-0000-00000000ff02'),
  NULL::text,
  '⭐ POST /v1/conversations : subject NULL accepté (champ optionnel)');

-- ===========================================================================
-- 3. 403 unrelated cabinet : WITH CHECK bloque l'INSERT cross-cabinet.
-- Contexte C2 : tenter de créer une conversation dans C1 → erreur 42501.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '16690000-0000-0000-0000-000000000002';

SELECT throws_ok(
  $$ INSERT INTO conversation (cabinet_id, scope, status, subject)
     VALUES (
       '16690000-0000-0000-0000-000000000001',
       'patient_cabinet', 'open',
       'Tentative pirate'
     ) $$,
  '42501', NULL,
  '⭐ POST /v1/conversations : WITH CHECK bloque création dans cabinet non lié (403)');

-- ===========================================================================
-- 4. Schema : colonne subject présente et nullable.
-- ===========================================================================
SELECT has_column('conversation', 'subject',
  'conversation.subject présente (migration 0097)');

SELECT col_type_is('conversation', 'subject', 'text',
  'conversation.subject est de type text');

SELECT col_is_null('conversation', 'subject',
  'conversation.subject est nullable');

SELECT * FROM finish();
ROLLBACK;
