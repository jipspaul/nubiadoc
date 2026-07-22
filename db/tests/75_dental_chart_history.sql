-- 75_dental_chart_history.sql
-- pgTAP : dental_chart_history (#4121, migration 0185).
--   DH1. Un praticien peut insérer un snapshot pour son cabinet.
--   DH2. RLS tenant : cabinet B ne voit PAS les snapshots de A.
--   DH3. Fail-closed : sans GUC app.current_cabinet_id → 0 ligne.
--   DH4. Append-only : UPDATE refusé (permission denied, nubia_app n'a pas
--        le privilège UPDATE — pas une histoire de RLS).
--   DH5. Append-only : DELETE refusé (idem).
-- Exécuté par pg_prove sous nubia_app (NOSUPERUSER, NOBYPASSRLS).
-- Fixtures auto-contenues (BEGIN…ROLLBACK). Préfixe UUID 41210000.
-- Issue : #4121

BEGIN;
SELECT plan(5);

-- ===========================================================================
-- Fixtures : 2 cabinets + 1 patient chacun.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '41210000-0000-0000-0000-000000000c01';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('41210000-0000-0000-0000-000000000c01', 'Cabinet DentalHistory-4121-A');
INSERT INTO patient (id, cabinet_id, first_name, last_name) VALUES
  ('41210000-0000-0000-0000-0000000000e1', '41210000-0000-0000-0000-000000000c01',
   'Patient', 'HistoryA');
RESET app.current_cabinet_id;

SET LOCAL app.current_cabinet_id = '41210000-0000-0000-0000-000000000c02';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('41210000-0000-0000-0000-000000000c02', 'Cabinet DentalHistory-4121-B');
RESET app.current_cabinet_id;

-- ===========================================================================
-- DH1. Le cabinet A insère un snapshot.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '41210000-0000-0000-0000-000000000c01';
INSERT INTO dental_chart_history (id, cabinet_id, patient_id, teeth_status) VALUES
  ('41210000-0000-0000-0000-000000000f01',
   '41210000-0000-0000-0000-000000000c01',
   '41210000-0000-0000-0000-0000000000e1',
   '{"11": {"status": "carie"}}'::jsonb);
SELECT is(
  (SELECT count(*)::int FROM dental_chart_history
   WHERE patient_id = '41210000-0000-0000-0000-0000000000e1'),
  1,
  'DH1 dental_chart_history : le cabinet A insère un snapshot');

-- ===========================================================================
-- DH2. RLS : cabinet B ne voit PAS les snapshots de A.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '41210000-0000-0000-0000-000000000c02';
SELECT is(
  (SELECT count(*)::int FROM dental_chart_history
   WHERE patient_id = '41210000-0000-0000-0000-0000000000e1'),
  0,
  '⭐ DH2 tenant_isolation : cabinet B ne voit PAS les snapshots de A');

-- ===========================================================================
-- DH3. Fail-closed : sans GUC → 0 ligne visible.
-- ===========================================================================
RESET app.current_cabinet_id;
SELECT is(
  (SELECT count(*)::int FROM dental_chart_history),
  0,
  '⭐ DH3 dental_chart_history : fail-closed, 0 ligne sans GUC positionné');

-- ===========================================================================
-- DH4/DH5. Append-only : UPDATE et DELETE refusés (privilège manquant).
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '41210000-0000-0000-0000-000000000c01';
SELECT throws_ok(
  $$ UPDATE dental_chart_history SET teeth_status = '{}'::jsonb
     WHERE id = '41210000-0000-0000-0000-000000000f01' $$,
  '42501', NULL,
  'DH4 dental_chart_history : UPDATE refusé (append-only, permission denied)');

SELECT throws_ok(
  $$ DELETE FROM dental_chart_history
     WHERE id = '41210000-0000-0000-0000-000000000f01' $$,
  '42501', NULL,
  'DH5 dental_chart_history : DELETE refusé (append-only, permission denied)');

SELECT * FROM finish();
ROLLBACK;
