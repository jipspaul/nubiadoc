-- 39_prescription_line_rls.sql
-- pgTAP : RLS prescription_item — isolation cabinet + accès patient titulaire.
-- Vérifie les policies ajoutées par la migration 0108 (DB-T026) :
--   PL1. Patient titulaire (Alice) voit sa ligne       [prescription_line_patient_read]
--   PL2. Autre patient (Bob) ne voit pas la ligne      [isolation inter-patient]
--   PL3. Praticien du cabinet A voit la ligne          [prescription_line_cabinet_isolation]
--   PL4. Praticien du cabinet B ne voit pas la ligne   [isolation inter-cabinet]
-- Exécuté par pg_prove sous nubia_app (NOSUPERUSER, NOBYPASSRLS).
-- Fixtures auto-contenues (BEGIN…ROLLBACK). Préfixe UUID 24480000.
-- Issue : #2448

BEGIN;
SELECT plan(4);

-- ===========================================================================
-- Fixtures : 2 cabinets (A, B), 2 patients avec comptes plateforme,
-- 1 praticien, 1 prescription + 1 ligne dans le cabinet A.
-- ===========================================================================

SET LOCAL app.current_cabinet_id = '24480000-0000-0000-0000-000000000001';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('24480000-0000-0000-0000-000000000001', 'Cabinet RLS-2448-A');

SET LOCAL app.current_cabinet_id = '24480000-0000-0000-0000-000000000002';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('24480000-0000-0000-0000-000000000002', 'Cabinet RLS-2448-B');

SET LOCAL app.current_cabinet_id = '24480000-0000-0000-0000-000000000001';

INSERT INTO app_user (id, email, password_hash, kind) VALUES
  ('24480000-0000-0000-0000-000000000010', 'prat.2448@nubia.test',    '$argon2id$fixture', 'pro'),
  ('24480000-0000-0000-0000-000000000011', 'alice.2448@nubia.test',   '$argon2id$fixture', 'patient'),
  ('24480000-0000-0000-0000-000000000012', 'bob.2448@nubia.test',     '$argon2id$fixture', 'patient');

INSERT INTO patient_account (id, app_user_id, first_name, last_name) VALUES
  ('24480000-0000-0000-0000-000000000020', '24480000-0000-0000-0000-000000000011', 'Alice', 'RLS2448'),
  ('24480000-0000-0000-0000-000000000021', '24480000-0000-0000-0000-000000000012', 'Bob',   'RLS2448');

INSERT INTO patient (id, cabinet_id, patient_account_id, first_name, last_name) VALUES
  ('24480000-0000-0000-0000-000000000030',
   '24480000-0000-0000-0000-000000000001',
   '24480000-0000-0000-0000-000000000020', 'Alice', 'RLS2448'),
  ('24480000-0000-0000-0000-000000000031',
   '24480000-0000-0000-0000-000000000001',
   '24480000-0000-0000-0000-000000000021', 'Bob', 'RLS2448');

INSERT INTO practitioner (id, cabinet_id, user_id) VALUES
  ('24480000-0000-0000-0000-000000000040',
   '24480000-0000-0000-0000-000000000001',
   '24480000-0000-0000-0000-000000000010');

INSERT INTO prescription (id, cabinet_id, patient_id, practitioner_id, status) VALUES
  ('24480000-0000-0000-0000-000000000050',
   '24480000-0000-0000-0000-000000000001',
   '24480000-0000-0000-0000-000000000030',
   '24480000-0000-0000-0000-000000000040',
   'draft');

INSERT INTO prescription_item (id, cabinet_id, prescription_id, label) VALUES
  ('24480000-0000-0000-0000-000000000060',
   '24480000-0000-0000-0000-000000000001',
   '24480000-0000-0000-0000-000000000050',
   'Amoxicilline 500 mg — 1 cp x 3/j pendant 7 jours');

-- ===========================================================================
-- PL1. Patient titulaire (Alice) voit sa ligne
-- Contexte : patient_account_id seul positionné (cabinet GUC réinitialisé).
-- ===========================================================================
RESET app.current_cabinet_id;
SELECT set_config('app.patient_account_id', '24480000-0000-0000-0000-000000000020', true);

SELECT is(
  (SELECT count(*)::int FROM prescription_item
   WHERE id = '24480000-0000-0000-0000-000000000060'),
  1,
  'PL1 prescription_item : patient titulaire voit sa ligne (prescription_line_patient_read)');

-- ===========================================================================
-- PL2. Autre patient (Bob) ne voit pas la ligne d''Alice
-- ===========================================================================
SELECT set_config('app.patient_account_id', '24480000-0000-0000-0000-000000000021', true);

SELECT is(
  (SELECT count(*)::int FROM prescription_item
   WHERE id = '24480000-0000-0000-0000-000000000060'),
  0,
  'PL2 prescription_item : autre patient ne voit pas la ligne (isolation inter-patient)');

-- ===========================================================================
-- PL3. Praticien du cabinet A voit la ligne
-- Contexte : cabinet_id seul positionné (patient GUC réinitialisé).
-- ===========================================================================
SELECT set_config('app.patient_account_id', '', true);
SET LOCAL app.current_cabinet_id = '24480000-0000-0000-0000-000000000001';

SELECT is(
  (SELECT count(*)::int FROM prescription_item
   WHERE id = '24480000-0000-0000-0000-000000000060'),
  1,
  'PL3 prescription_item : praticien du cabinet voit la ligne (prescription_line_cabinet_isolation)');

-- ===========================================================================
-- PL4. Praticien du cabinet B ne voit pas la ligne du cabinet A
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '24480000-0000-0000-0000-000000000002';

SELECT is(
  (SELECT count(*)::int FROM prescription_item
   WHERE id = '24480000-0000-0000-0000-000000000060'),
  0,
  'PL4 prescription_item : autre cabinet ne voit pas la ligne (isolation inter-cabinet)');

SELECT * FROM finish();
ROLLBACK;
