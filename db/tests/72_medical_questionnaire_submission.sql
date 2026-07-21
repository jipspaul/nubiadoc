-- 72_medical_questionnaire_submission.sql
-- pgTAP : medical_questionnaire_submission (#4107, migration 0180).
--   MQ1. Le patient peut créer/modifier son propre brouillon.
--   MQ2. RLS patient-scoped : compte B ne voit pas le brouillon de A.
--   MQ3. Fail-closed patient : sans GUC app.patient_account_id → 0 ligne.
--   MQ4. Le cabinet ne voit PAS un brouillon (status = 'draft').
--   MQ5. Le cabinet voit une soumission une fois status = 'submitted'.
--   MQ6. Fail-closed cabinet : sans GUC app.current_cabinet_id → 0 ligne.
--   MQ7. CHECK submitted_at : 'submitted' sans submitted_at refusé.
-- Exécuté par pg_prove sous nubia_app (NOSUPERUSER, NOBYPASSRLS).
-- Fixtures auto-contenues (BEGIN…ROLLBACK). Préfixe UUID 41070000.
-- Issue : #4107

BEGIN;
SELECT plan(7);

-- ===========================================================================
-- Fixtures : 2 comptes patient (A, B) + 1 cabinet.
-- ===========================================================================
INSERT INTO app_user (id, email, password_hash, kind) VALUES
  ('41070000-0000-0000-0000-0000000000a1', 'mq.a@nubia.test', '$argon2id$fixture', 'patient');
INSERT INTO app_user (id, email, password_hash, kind) VALUES
  ('41070000-0000-0000-0000-0000000000a2', 'mq.b@nubia.test', '$argon2id$fixture', 'patient');

INSERT INTO patient_account (id, app_user_id, first_name, last_name) VALUES
  ('41070000-0000-0000-0000-0000000000e1', '41070000-0000-0000-0000-0000000000a1', 'Patient', 'MqA');
INSERT INTO patient_account (id, app_user_id, first_name, last_name) VALUES
  ('41070000-0000-0000-0000-0000000000e2', '41070000-0000-0000-0000-0000000000a2', 'Patient', 'MqB');

SET LOCAL app.current_cabinet_id = '41070000-0000-0000-0000-000000000c01';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('41070000-0000-0000-0000-000000000c01', 'Cabinet MedicalQuestionnaire-4107');
RESET app.current_cabinet_id;

-- ===========================================================================
-- MQ1. Le patient A crée puis modifie son propre brouillon.
-- ===========================================================================
SET LOCAL app.patient_account_id = '41070000-0000-0000-0000-0000000000e1';
INSERT INTO medical_questionnaire_submission (id, cabinet_id, patient_account_id, payload) VALUES
  ('41070000-0000-0000-0000-000000000010',
   '41070000-0000-0000-0000-000000000c01',
   '41070000-0000-0000-0000-0000000000e1',
   '{"allergies": "aucune"}'::jsonb);
UPDATE medical_questionnaire_submission
  SET payload = '{"allergies": "penicilline"}'::jsonb
  WHERE id = '41070000-0000-0000-0000-000000000010';
SELECT is(
  (SELECT payload->>'allergies' FROM medical_questionnaire_submission
   WHERE id = '41070000-0000-0000-0000-000000000010'),
  'penicilline',
  'MQ1 medical_questionnaire_submission_patient_owner : le patient modifie son propre brouillon');

-- ===========================================================================
-- MQ2. RLS : compte B ne voit PAS le brouillon de A.
-- ===========================================================================
SET LOCAL app.patient_account_id = '41070000-0000-0000-0000-0000000000e2';
SELECT is(
  (SELECT count(*)::int FROM medical_questionnaire_submission
   WHERE id = '41070000-0000-0000-0000-000000000010'),
  0,
  '⭐ MQ2 medical_questionnaire_submission_patient_owner : compte B ne voit PAS le brouillon de A');

-- ===========================================================================
-- MQ3. Fail-closed patient : sans GUC → 0 ligne (côté policy patient).
-- ===========================================================================
RESET app.patient_account_id;
SELECT is(
  (SELECT count(*)::int FROM medical_questionnaire_submission
   WHERE id = '41070000-0000-0000-0000-000000000010'),
  0,
  '⭐ MQ3 medical_questionnaire_submission : fail-closed, 0 ligne sans aucun GUC positionné');

-- ===========================================================================
-- MQ4. Le cabinet ne voit PAS un brouillon (status = 'draft').
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '41070000-0000-0000-0000-000000000c01';
SELECT is(
  (SELECT count(*)::int FROM medical_questionnaire_submission
   WHERE id = '41070000-0000-0000-0000-000000000010'),
  0,
  '⭐ MQ4 medical_questionnaire_submission_cabinet_read : brouillon invisible au cabinet');
RESET app.current_cabinet_id;

-- ===========================================================================
-- MQ5. Le cabinet voit la soumission une fois status = 'submitted'.
-- ===========================================================================
SET LOCAL app.patient_account_id = '41070000-0000-0000-0000-0000000000e1';
UPDATE medical_questionnaire_submission
  SET status = 'submitted', submitted_at = now()
  WHERE id = '41070000-0000-0000-0000-000000000010';
RESET app.patient_account_id;

SET LOCAL app.current_cabinet_id = '41070000-0000-0000-0000-000000000c01';
SELECT is(
  (SELECT count(*)::int FROM medical_questionnaire_submission
   WHERE id = '41070000-0000-0000-0000-000000000010'),
  1,
  'MQ5 medical_questionnaire_submission_cabinet_read : soumission visible une fois submitted');
RESET app.current_cabinet_id;

-- ===========================================================================
-- MQ6. Fail-closed cabinet : sans GUC app.current_cabinet_id → 0 ligne.
-- ===========================================================================
SELECT is(
  (SELECT count(*)::int FROM medical_questionnaire_submission
   WHERE id = '41070000-0000-0000-0000-000000000010'),
  0,
  '⭐ MQ6 medical_questionnaire_submission_cabinet_read : fail-closed sans GUC cabinet');

-- ===========================================================================
-- MQ7. CHECK submitted_at : 'submitted' sans submitted_at refusé.
-- ===========================================================================
SET LOCAL app.patient_account_id = '41070000-0000-0000-0000-0000000000e1';
SELECT throws_ok(
  $$ INSERT INTO medical_questionnaire_submission
       (cabinet_id, patient_account_id, status, submitted_at)
     VALUES ('41070000-0000-0000-0000-000000000c01',
             '41070000-0000-0000-0000-0000000000e1', 'submitted', NULL) $$,
  '23514', NULL,
  'MQ7 medical_questionnaire_submission_submitted_at_check : submitted sans submitted_at refusé (23514)');

SELECT * FROM finish();
ROLLBACK;
