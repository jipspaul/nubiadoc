-- 78_orthodontic_treatment.sql
-- pgTAP : orthodontic_treatment / orthodontic_step (#4134, migration 0189).
--   OT1. Cabinet A crée un traitement + une étape.
--   OT2. Étape avec kind hors énum refusée (CHECK).
--   OT3. semester_count <= 0 refusé (CHECK).
--   OT4. RLS orthodontic_treatment : cabinet B ne voit PAS le traitement de A.
--   OT5. RLS orthodontic_step : cabinet B ne voit PAS l'étape de A.
--   OT6. Fail-closed : sans GUC → 0 ligne sur les deux tables.
-- Exécuté par pg_prove sous nubia_app (NOSUPERUSER, NOBYPASSRLS).
-- Fixtures auto-contenues (BEGIN…ROLLBACK). Préfixe UUID 41340000.
-- Issue : #4134

BEGIN;
SELECT plan(6);

-- ===========================================================================
-- Fixtures : 2 cabinets + patients.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '41340000-0000-0000-0000-000000000c01';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('41340000-0000-0000-0000-000000000c01', 'Cabinet Ortho-4134-A');
INSERT INTO patient (id, cabinet_id, first_name, last_name) VALUES
  ('41340000-0000-0000-0000-0000000000e1', '41340000-0000-0000-0000-000000000c01',
   'Patient', 'OrthoA');
RESET app.current_cabinet_id;

SET LOCAL app.current_cabinet_id = '41340000-0000-0000-0000-000000000c02';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('41340000-0000-0000-0000-000000000c02', 'Cabinet Ortho-4134-B');
RESET app.current_cabinet_id;

-- ===========================================================================
-- OT1. Le cabinet A crée un traitement + une étape.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '41340000-0000-0000-0000-000000000c01';
INSERT INTO orthodontic_treatment
  (id, cabinet_id, patient_id, type, semester_count, status) VALUES
  ('41340000-0000-0000-0000-000000000d01', '41340000-0000-0000-0000-000000000c01',
   '41340000-0000-0000-0000-0000000000e1', 'multi-attache', 4, 'in_progress');
INSERT INTO orthodontic_step
  (id, cabinet_id, treatment_id, step_number, kind) VALUES
  ('41340000-0000-0000-0000-000000000f01', '41340000-0000-0000-0000-000000000c01',
   '41340000-0000-0000-0000-000000000d01', 1, 'bague');
SELECT is(
  (SELECT count(*)::int FROM orthodontic_step
   WHERE treatment_id = '41340000-0000-0000-0000-000000000d01'),
  1,
  'OT1 orthodontic_treatment/orthodontic_step : création cabinet A OK');

-- ===========================================================================
-- OT2. kind hors énum refusé (CHECK).
-- ===========================================================================
SELECT throws_ok(
  $$ INSERT INTO orthodontic_step (cabinet_id, treatment_id, step_number, kind)
     VALUES ('41340000-0000-0000-0000-000000000c01',
             '41340000-0000-0000-0000-000000000d01', 2, 'bracket_invalide') $$,
  '23514', NULL,
  'OT2 orthodontic_step_kind_check : kind hors énum refusé (23514)');

-- ===========================================================================
-- OT3. semester_count <= 0 refusé (CHECK).
-- ===========================================================================
SELECT throws_ok(
  $$ INSERT INTO orthodontic_treatment (cabinet_id, patient_id, type, semester_count)
     VALUES ('41340000-0000-0000-0000-000000000c01',
             '41340000-0000-0000-0000-0000000000e1', 'gouttières', 0) $$,
  '23514', NULL,
  'OT3 orthodontic_treatment_semester_count_check : semester_count <= 0 refusé (23514)');

-- ===========================================================================
-- OT4. RLS orthodontic_treatment : cabinet B ne voit PAS le traitement de A.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '41340000-0000-0000-0000-000000000c02';
SELECT is(
  (SELECT count(*)::int FROM orthodontic_treatment
   WHERE id = '41340000-0000-0000-0000-000000000d01'),
  0,
  '⭐ OT4 tenant_isolation orthodontic_treatment : cabinet B ne voit PAS le traitement de A');

-- ===========================================================================
-- OT5. RLS orthodontic_step : cabinet B ne voit PAS l'étape de A.
-- ===========================================================================
SELECT is(
  (SELECT count(*)::int FROM orthodontic_step
   WHERE id = '41340000-0000-0000-0000-000000000f01'),
  0,
  '⭐ OT5 tenant_isolation orthodontic_step : cabinet B ne voit PAS l''étape de A');

-- ===========================================================================
-- OT6. Fail-closed : sans GUC → 0 ligne sur les deux tables.
-- ===========================================================================
RESET app.current_cabinet_id;
SELECT is(
  (SELECT count(*)::int FROM orthodontic_treatment) +
  (SELECT count(*)::int FROM orthodontic_step),
  0,
  '⭐ OT6 fail-closed : 0 ligne sans GUC positionné (orthodontic_treatment + orthodontic_step)');

SELECT * FROM finish();
ROLLBACK;
