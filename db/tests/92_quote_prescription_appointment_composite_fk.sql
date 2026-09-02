-- 92_quote_prescription_appointment_composite_fk.sql
-- pgTAP : FK composite tenant-scopée quote/prescription.appointment_id —
-- migration 0244, audit #4291 (issue #6204 : ajout du lien RDV -> facture/
-- ordonnance, même pattern anti-RLS-bypass que 0210-0215).
--   QA1/QA2. quote.appointment_id -> appointment(id, cabinet_id) :
--            légitime OK, exploit cross-cabinet refusé (23503).
--   PA1/PA2. prescription.appointment_id -> appointment(id, cabinet_id) :
--            légitime OK, exploit cross-cabinet refusé (23503).
--   FC. Fail-closed : sans GUC -> 0 ligne visible.
-- Exécuté par pg_prove sous nubia_app (NOSUPERUSER, NOBYPASSRLS).
-- Fixtures auto-contenues (BEGIN…ROLLBACK). Préfixe UUID 42910006-...
-- Issue : #6204

BEGIN;
SELECT plan(5);

-- ===========================================================================
-- Fixtures : 2 cabinets, chacun avec un patient + un practitioner + un rdv.
-- ===========================================================================
INSERT INTO app_user (id, email, kind, status) VALUES
  ('42910006-0000-0000-0000-0000000000a1', 'praticien-qpa-a@demo-42916.test', 'pro', 'active'),
  ('42910006-0000-0000-0000-0000000000a2', 'praticien-qpa-b@demo-42916.test', 'pro', 'active');

SET LOCAL app.current_cabinet_id = '42910006-0000-0000-0000-000000000c11';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('42910006-0000-0000-0000-000000000c11', 'Cabinet QPA-4291-A');
INSERT INTO patient (id, cabinet_id, first_name, last_name) VALUES
  ('42910006-0000-0000-0000-000000000e11', '42910006-0000-0000-0000-000000000c11',
   'Patient', 'A');
INSERT INTO practitioner (id, cabinet_id, user_id) VALUES
  ('42910006-0000-0000-0000-000000000d11', '42910006-0000-0000-0000-000000000c11',
   '42910006-0000-0000-0000-0000000000a1');
INSERT INTO appointment (id, cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status) VALUES
  ('42910006-0000-0000-0000-000000000f11', '42910006-0000-0000-0000-000000000c11',
   '42910006-0000-0000-0000-000000000e11', '42910006-0000-0000-0000-000000000d11',
   '2026-08-03 09:00+02', '2026-08-03 09:30+02', 'done');
RESET app.current_cabinet_id;

SET LOCAL app.current_cabinet_id = '42910006-0000-0000-0000-000000000c12';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('42910006-0000-0000-0000-000000000c12', 'Cabinet QPA-4291-B');
INSERT INTO patient (id, cabinet_id, first_name, last_name) VALUES
  ('42910006-0000-0000-0000-000000000e12', '42910006-0000-0000-0000-000000000c12',
   'Patient', 'B');
INSERT INTO practitioner (id, cabinet_id, user_id) VALUES
  ('42910006-0000-0000-0000-000000000d12', '42910006-0000-0000-0000-000000000c12',
   '42910006-0000-0000-0000-0000000000a2');
RESET app.current_cabinet_id;

-- ===========================================================================
-- QA1/QA2. quote.appointment_id
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '42910006-0000-0000-0000-000000000c11';
INSERT INTO quote (id, cabinet_id, patient_id, appointment_id, status) VALUES
  ('42910006-0000-0000-0000-000000000f21', '42910006-0000-0000-0000-000000000c11',
   '42910006-0000-0000-0000-000000000e11', '42910006-0000-0000-0000-000000000f11', 'sent');
SELECT lives_ok(
  $$ SELECT 1 $$,
  'QA1 quote : fixture légitime cabinet A / rdv A insérée sans erreur');
RESET app.current_cabinet_id;
SET LOCAL app.current_cabinet_id = '42910006-0000-0000-0000-000000000c12';
SELECT throws_ok(
  $$ INSERT INTO quote (cabinet_id, patient_id, appointment_id, status)
     VALUES ('42910006-0000-0000-0000-000000000c12',
             '42910006-0000-0000-0000-000000000e12',
             '42910006-0000-0000-0000-000000000f11', 'sent') $$,
  '23503', NULL,
  '⭐ QA2 quote : rattacher le rdv d''un autre cabinet refusé (23503, RLS FK)');
RESET app.current_cabinet_id;

-- ===========================================================================
-- PA1/PA2. prescription.appointment_id
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '42910006-0000-0000-0000-000000000c11';
INSERT INTO prescription (id, cabinet_id, patient_id, practitioner_id, appointment_id, status) VALUES
  ('42910006-0000-0000-0000-000000000f31', '42910006-0000-0000-0000-000000000c11',
   '42910006-0000-0000-0000-000000000e11', '42910006-0000-0000-0000-000000000d11',
   '42910006-0000-0000-0000-000000000f11', 'signed');
SELECT lives_ok(
  $$ SELECT 1 $$,
  'PA1 prescription : fixture légitime cabinet A / rdv A insérée sans erreur');
RESET app.current_cabinet_id;
SET LOCAL app.current_cabinet_id = '42910006-0000-0000-0000-000000000c12';
SELECT throws_ok(
  $$ INSERT INTO prescription (cabinet_id, patient_id, practitioner_id, appointment_id, status)
     VALUES ('42910006-0000-0000-0000-000000000c12',
             '42910006-0000-0000-0000-000000000e12', '42910006-0000-0000-0000-000000000d12',
             '42910006-0000-0000-0000-000000000f11', 'signed') $$,
  '23503', NULL,
  '⭐ PA2 prescription : rattacher le rdv d''un autre cabinet refusé (23503, RLS FK)');
RESET app.current_cabinet_id;

-- ===========================================================================
-- FC. Fail-closed : sans GUC -> 0 ligne visible.
-- ===========================================================================
SELECT is(
  (SELECT count(*)::int FROM quote WHERE id = '42910006-0000-0000-0000-000000000f21')
    + (SELECT count(*)::int FROM prescription WHERE id = '42910006-0000-0000-0000-000000000f31'),
  0,
  '⭐ FC fail-closed : 0 ligne visible (quote/prescription) sans GUC positionné');

SELECT * FROM finish();
ROLLBACK;
