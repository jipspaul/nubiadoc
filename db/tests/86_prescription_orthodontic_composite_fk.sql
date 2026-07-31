-- 86_prescription_orthodontic_composite_fk.sql
-- pgTAP : FK composite tenant-scopée prescription.consultation_id ->
-- consultation_session(id, cabinet_id) et orthodontic_treatment.
-- treatment_plan_id -> treatment_plan(id, cabinet_id) — migration 0211,
-- audit #4291.
--   PR1. Cabinet A crée une prescription liée à sa propre consultation_session.
--   PR2. Rattacher une consultation_session d'un AUTRE cabinet refusé (23503).
--   OR1. Cabinet A crée un traitement ortho lié à son propre treatment_plan.
--   OR2. Rattacher un treatment_plan d'un AUTRE cabinet refusé (23503).
--   FC.  Fail-closed : sans GUC -> 0 ligne sur les deux tables.
-- Exécuté par pg_prove sous nubia_app (NOSUPERUSER, NOBYPASSRLS).
-- Fixtures auto-contenues (BEGIN…ROLLBACK). Préfixe UUID 42910001-...
-- Issue : #4291

BEGIN;
SELECT plan(5);

-- ===========================================================================
-- Fixtures : 2 cabinets, chacun avec un patient + practitioner ; cabinet A
-- a en plus un appointment/consultation_session et un treatment_plan.
-- ===========================================================================
INSERT INTO app_user (id, email, kind, status) VALUES
  ('42910001-0000-0000-0000-0000000000a1', 'praticien-po-a@demo-42911.test', 'pro', 'active'),
  ('42910001-0000-0000-0000-0000000000a2', 'praticien-po-b@demo-42911.test', 'pro', 'active');

SET LOCAL app.current_cabinet_id = '42910001-0000-0000-0000-000000000c11';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('42910001-0000-0000-0000-000000000c11', 'Cabinet PO2-4291-A');
INSERT INTO patient (id, cabinet_id, first_name, last_name) VALUES
  ('42910001-0000-0000-0000-000000000e11', '42910001-0000-0000-0000-000000000c11',
   'Patient', 'A');
INSERT INTO practitioner (id, cabinet_id, user_id) VALUES
  ('42910001-0000-0000-0000-000000000d11', '42910001-0000-0000-0000-000000000c11',
   '42910001-0000-0000-0000-0000000000a1');
INSERT INTO appointment (id, cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status) VALUES
  ('42910001-0000-0000-0000-0000000006a1', '42910001-0000-0000-0000-000000000c11',
   '42910001-0000-0000-0000-000000000e11', '42910001-0000-0000-0000-000000000d11',
   now(), now() + interval '30 min', 'confirmed');
INSERT INTO consultation_session (id, cabinet_id, appointment_id, practitioner_id) VALUES
  ('42910001-0000-0000-0000-0000000007a1', '42910001-0000-0000-0000-000000000c11',
   '42910001-0000-0000-0000-0000000006a1', '42910001-0000-0000-0000-000000000d11');
INSERT INTO treatment_plan (id, cabinet_id, patient_id, title) VALUES
  ('42910001-0000-0000-0000-0000000008a1', '42910001-0000-0000-0000-000000000c11',
   '42910001-0000-0000-0000-000000000e11', 'Plan ortho A');
RESET app.current_cabinet_id;

SET LOCAL app.current_cabinet_id = '42910001-0000-0000-0000-000000000c12';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('42910001-0000-0000-0000-000000000c12', 'Cabinet PO2-4291-B');
INSERT INTO patient (id, cabinet_id, first_name, last_name) VALUES
  ('42910001-0000-0000-0000-000000000e12', '42910001-0000-0000-0000-000000000c12',
   'Patient', 'B');
INSERT INTO practitioner (id, cabinet_id, user_id) VALUES
  ('42910001-0000-0000-0000-000000000d12', '42910001-0000-0000-0000-000000000c12',
   '42910001-0000-0000-0000-0000000000a2');
RESET app.current_cabinet_id;

-- ===========================================================================
-- PR1. Cas légitime : cabinet A crée une prescription liée à sa propre
-- consultation_session.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '42910001-0000-0000-0000-000000000c11';
INSERT INTO prescription (id, cabinet_id, patient_id, practitioner_id, consultation_id, status) VALUES
  ('42910001-0000-0000-0000-0000000009a1', '42910001-0000-0000-0000-000000000c11',
   '42910001-0000-0000-0000-000000000e11', '42910001-0000-0000-0000-000000000d11',
   '42910001-0000-0000-0000-0000000007a1', 'draft');
SELECT is(
  (SELECT count(*)::int FROM prescription WHERE id = '42910001-0000-0000-0000-0000000009a1'),
  1,
  'PR1 prescription : création cabinet A référençant sa propre consultation_session OK');

-- ===========================================================================
-- PR2. Rattacher une consultation_session d'un AUTRE cabinet refusé (23503)
-- — consultation_session a RLS+FORCE RLS (loop générique 0011) : la ligne
-- du cabinet A est invisible sous le GUC B, la FK échoue avant toute policy.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '42910001-0000-0000-0000-000000000c12';
SELECT throws_ok(
  $$ INSERT INTO prescription (cabinet_id, patient_id, practitioner_id, consultation_id, status)
     VALUES ('42910001-0000-0000-0000-000000000c12',
             '42910001-0000-0000-0000-000000000e12', '42910001-0000-0000-0000-000000000d12',
             '42910001-0000-0000-0000-0000000007a1', 'draft') $$,
  '23503', NULL,
  '⭐ PR2 prescription : rattacher une consultation_session d''un autre cabinet refusé (23503, RLS FK)');

-- ===========================================================================
-- OR1. Cas légitime : cabinet A crée un traitement ortho lié à son propre
-- treatment_plan.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '42910001-0000-0000-0000-000000000c11';
INSERT INTO orthodontic_treatment (id, cabinet_id, patient_id, treatment_plan_id, type, semester_count) VALUES
  ('42910001-0000-0000-0000-000000000aa1', '42910001-0000-0000-0000-000000000c11',
   '42910001-0000-0000-0000-000000000e11', '42910001-0000-0000-0000-0000000008a1',
   'multi_bagues', 4);
SELECT is(
  (SELECT count(*)::int FROM orthodontic_treatment WHERE id = '42910001-0000-0000-0000-000000000aa1'),
  1,
  'OR1 orthodontic_treatment : création cabinet A référençant son propre treatment_plan OK');

-- ===========================================================================
-- OR2. Rattacher un treatment_plan d'un AUTRE cabinet refusé (23503) —
-- treatment_plan a RLS+FORCE RLS (0011) : la ligne du cabinet A est
-- invisible sous le GUC B, la FK échoue avant toute policy.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '42910001-0000-0000-0000-000000000c12';
SELECT throws_ok(
  $$ INSERT INTO orthodontic_treatment (cabinet_id, patient_id, treatment_plan_id, type, semester_count)
     VALUES ('42910001-0000-0000-0000-000000000c12',
             '42910001-0000-0000-0000-000000000e12', '42910001-0000-0000-0000-0000000008a1',
             'multi_bagues', 4) $$,
  '23503', NULL,
  '⭐ OR2 orthodontic_treatment : rattacher un treatment_plan d''un autre cabinet refusé (23503, RLS FK)');

-- ===========================================================================
-- FC. Fail-closed : sans GUC -> 0 ligne sur les deux tables.
-- ===========================================================================
RESET app.current_cabinet_id;
SELECT is(
  (SELECT count(*)::int FROM prescription) + (SELECT count(*)::int FROM orthodontic_treatment)
    + (SELECT count(*)::int FROM consultation_session) + (SELECT count(*)::int FROM treatment_plan),
  0,
  '⭐ FC fail-closed : 0 ligne visible (prescription/orthodontic_treatment/consultation_session/treatment_plan) sans GUC positionné');

SELECT * FROM finish();
ROLLBACK;
