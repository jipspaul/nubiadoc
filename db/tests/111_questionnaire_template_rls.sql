-- 111_questionnaire_template_rls.sql
-- pgTAP : RLS questionnaire_template — standard global + variantes cabinet,
-- et backfill template_id/version sur medical_questionnaire_submission
-- (#7160, migration 0294).
--   QT1. Le standard seedé (cabinet_id NULL, v1) est lisible par le cabinet A
--        (policy global_template_read)
--   QT2. … et par le cabinet B (tout cabinet, pas seulement celui qui l'a créé)
--   QT3. Cabinet A voit son propre modèle privé (tenant_isolation)
--   QT4. Cabinet B ne voit PAS le modèle privé du cabinet A (cross-tenant)
--   QT5. Un cabinet ne peut PAS modifier le standard (0 ligne affectée :
--        tenant_isolation ne couvre pas cabinet_id NULL en UPDATE,
--        global_template_read est SELECT seul)
--   QT6. Un cabinet ne peut PAS créer un modèle "standard" (WITH CHECK
--        tenant_isolation refuse cabinet_id NULL → 42501)
--   QT7. Fail-closed : sans GUC app.current_cabinet_id positionné → aucun
--        modèle privé visible
--   QT8. Une soumission référence explicitement le standard v1
--        (template_id/version) et le join vers questionnaire_template
--        retrouve bien le schéma de cette version.
--   QT9. template_id doit référencer un questionnaire_template existant
--        (contrainte FK, id inconnu rejeté).
-- Exécuté par pg_prove sous nubia_app (NOSUPERUSER, NOBYPASSRLS).
-- Fixtures auto-contenues (BEGIN…ROLLBACK). Préfixe UUID 71600000.
-- Issue : #7160

BEGIN;
SELECT plan(9);

-- ===========================================================================
-- Fixtures : 2 cabinets (A, B), 1 modèle privé pour le cabinet A.
-- ===========================================================================

SET LOCAL app.current_cabinet_id = '71600000-0000-0000-0000-000000000001';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('71600000-0000-0000-0000-000000000001', 'Cabinet QuestionnaireTemplate-7160-A');

SET LOCAL app.current_cabinet_id = '71600000-0000-0000-0000-000000000002';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('71600000-0000-0000-0000-000000000002', 'Cabinet QuestionnaireTemplate-7160-B');

SET LOCAL app.current_cabinet_id = '71600000-0000-0000-0000-000000000001';

INSERT INTO questionnaire_template (id, cabinet_id, version, title, schema) VALUES
  ('71600000-0000-0000-0000-000000000010',
   '71600000-0000-0000-0000-000000000001',
   1,
   'Modèle privé Cabinet A 7160',
   '[{"key": "test", "type": "text", "label": "Question test", "options": null, "condition": null, "safety_flag": false}]'::jsonb);

-- ===========================================================================
-- QT1/QT2. Le standard seedé (v1) est lisible par tout cabinet.
-- ===========================================================================
SELECT is(
  (SELECT count(*)::int FROM questionnaire_template
   WHERE cabinet_id IS NULL AND id = '02940000-0000-0000-0000-000000000001'),
  1,
  'QT1 questionnaire_template : cabinet A voit le standard seedé (global_template_read)');

SET LOCAL app.current_cabinet_id = '71600000-0000-0000-0000-000000000002';
SELECT is(
  (SELECT count(*)::int FROM questionnaire_template
   WHERE cabinet_id IS NULL AND id = '02940000-0000-0000-0000-000000000001'),
  1,
  'QT2 questionnaire_template : cabinet B voit aussi le standard seedé');

-- ===========================================================================
-- QT3. Cabinet A voit son propre modèle privé.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '71600000-0000-0000-0000-000000000001';
SELECT is(
  (SELECT count(*)::int FROM questionnaire_template
   WHERE id = '71600000-0000-0000-0000-000000000010'),
  1,
  'QT3 questionnaire_template : cabinet A voit son propre modèle privé (tenant_isolation)');

-- ===========================================================================
-- QT4. Cabinet B ne voit PAS le modèle privé du cabinet A (cross-tenant).
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '71600000-0000-0000-0000-000000000002';
SELECT is(
  (SELECT count(*)::int FROM questionnaire_template
   WHERE id = '71600000-0000-0000-0000-000000000010'),
  0,
  'QT4 questionnaire_template : cabinet B ne voit PAS le modèle privé du cabinet A (isolation cross-tenant)');

-- ===========================================================================
-- QT5. UPDATE du standard par un cabinet → 0 ligne affectée.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '71600000-0000-0000-0000-000000000001';
WITH upd AS (
  UPDATE questionnaire_template SET title = 'Piraté'
  WHERE id = '02940000-0000-0000-0000-000000000001'
  RETURNING id
)
SELECT is((SELECT count(*)::int FROM upd), 0,
  'QT5 questionnaire_template : un cabinet ne peut pas modifier le standard (0 ligne)');

-- ===========================================================================
-- QT6. INSERT cabinet_id NULL par un cabinet → refusé (42501).
-- ===========================================================================
SELECT throws_ok(
  $$ INSERT INTO questionnaire_template (cabinet_id, version, title, schema)
     VALUES (NULL, 99, 'Faux standard', '[]'::jsonb) $$,
  '42501', NULL,
  'QT6 questionnaire_template : un cabinet ne peut pas créer un modèle "standard" (42501)');

-- ===========================================================================
-- QT7. Fail-closed sur le modèle privé : sans GUC positionné, invisible.
-- ===========================================================================
RESET app.current_cabinet_id;
SELECT is(
  (SELECT count(*)::int FROM questionnaire_template
   WHERE id = '71600000-0000-0000-0000-000000000010'),
  0,
  'QT7 questionnaire_template : fail-closed, modèle privé invisible sans GUC positionné');

-- ===========================================================================
-- QT8. Une soumission référence explicitement le standard v1 et le join
-- vers questionnaire_template retrouve le schéma de cette version.
-- ===========================================================================
INSERT INTO app_user (id, email, password_hash, kind) VALUES
  ('71600000-0000-0000-0000-0000000000a1', 'qt.a@nubia.test', '$argon2id$fixture', 'patient');
INSERT INTO patient_account (id, app_user_id, first_name, last_name) VALUES
  ('71600000-0000-0000-0000-0000000000e1', '71600000-0000-0000-0000-0000000000a1', 'Patient', 'QtA');

SET LOCAL app.patient_account_id = '71600000-0000-0000-0000-0000000000e1';
INSERT INTO medical_questionnaire_submission
  (id, cabinet_id, patient_account_id, payload, template_id, version) VALUES
  ('71600000-0000-0000-0000-000000000020',
   '71600000-0000-0000-0000-000000000001',
   '71600000-0000-0000-0000-0000000000e1',
   '{"allergies": "aucune"}'::jsonb,
   '02940000-0000-0000-0000-000000000001',
   1);

SELECT is(
  (SELECT qt.title FROM medical_questionnaire_submission mqs
   JOIN questionnaire_template qt ON qt.id = mqs.template_id AND qt.version = mqs.version
   WHERE mqs.id = '71600000-0000-0000-0000-000000000020'),
  'Questionnaire médical standard',
  'QT8 medical_questionnaire_submission : le join template_id/version retrouve le standard v1');
RESET app.patient_account_id;

-- ===========================================================================
-- QT9. template_id doit référencer un questionnaire_template existant.
-- ===========================================================================
-- status 'submitted' (pas 'draft') pour ne pas heurter l'index unique
-- medical_questionnaire_submission_one_draft_uidx (migration 0235) : la
-- ligne QT8 ci-dessus est déjà LE brouillon actif de ce couple patient/cabinet.
SET LOCAL app.patient_account_id = '71600000-0000-0000-0000-0000000000e1';
SELECT throws_ok(
  $$ INSERT INTO medical_questionnaire_submission
       (cabinet_id, patient_account_id, status, submitted_at, template_id, version)
     VALUES ('71600000-0000-0000-0000-000000000001',
             '71600000-0000-0000-0000-0000000000e1',
             'submitted', now(),
             '00000000-0000-0000-0000-000000000000', 1) $$,
  '23503', NULL,
  'QT9 medical_questionnaire_submission_template_id_fkey : template_id inconnu rejeté (23503)');
RESET app.patient_account_id;

SELECT * FROM finish();
ROLLBACK;
