-- 71_periodontal_chart_rls.sql
-- pgTAP : RLS periodontal_chart (#4104, migration 0179).
--   PC1. Cabinet A voit son propre bilan parodontal.
--   PC2. Cabinet B ne voit pas le bilan du cabinet A (isolation cross-tenant).
--   PC3. Fail-closed : sans GUC app.current_cabinet_id → 0 ligne visible.
--   PC4. Plusieurs bilans pour le même patient (série de mesures, pas
--        d'unicité contrairement à dental_chart).
-- Exécuté par pg_prove sous nubia_app (NOSUPERUSER, NOBYPASSRLS).
-- Fixtures auto-contenues (BEGIN…ROLLBACK). Préfixe UUID 41040000.
-- Issue : #4104

BEGIN;
SELECT plan(4);

-- ===========================================================================
-- Fixtures : cabinet A + B, 1 patient dans A avec un premier bilan.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '41040000-0000-0000-0000-000000000001';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('41040000-0000-0000-0000-000000000001', 'Cabinet PeriodontalChart-4104-A');
INSERT INTO patient (id, cabinet_id, first_name, last_name) VALUES
  ('41040000-0000-0000-0000-000000000010', '41040000-0000-0000-0000-000000000001',
   'Serge', 'Parodonte');
INSERT INTO periodontal_chart (id, cabinet_id, patient_id, measured_at, sites, indices) VALUES
  ('41040000-0000-0000-0000-000000000020', '41040000-0000-0000-0000-000000000001',
   '41040000-0000-0000-0000-000000000010', '2026-01-15 09:00+00',
   '{"11": {"depth_mm": 3}}', '{"plaque_index": 0.2}');

SET LOCAL app.current_cabinet_id = '41040000-0000-0000-0000-000000000002';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('41040000-0000-0000-0000-000000000002', 'Cabinet PeriodontalChart-4104-B');

-- ===========================================================================
-- PC1. Cabinet A voit son propre bilan parodontal.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '41040000-0000-0000-0000-000000000001';
SELECT is(
  (SELECT count(*)::int FROM periodontal_chart
   WHERE id = '41040000-0000-0000-0000-000000000020'),
  1,
  'PC1 periodontal_chart : cabinet A voit son propre bilan (tenant_isolation)');

-- ===========================================================================
-- PC2. Cabinet B ne voit pas le bilan du cabinet A.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '41040000-0000-0000-0000-000000000002';
SELECT is(
  (SELECT count(*)::int FROM periodontal_chart
   WHERE id = '41040000-0000-0000-0000-000000000020'),
  0,
  '⭐ PC2 periodontal_chart : cabinet B ne voit PAS le bilan du cabinet A (isolation cross-tenant)');

-- ===========================================================================
-- PC3. Fail-closed : sans GUC → 0 ligne visible.
-- ===========================================================================
RESET app.current_cabinet_id;
SELECT is(
  (SELECT count(*)::int FROM periodontal_chart),
  0,
  '⭐ PC3 periodontal_chart : fail-closed, 0 ligne visible sans GUC positionné');

-- ===========================================================================
-- PC4. Plusieurs bilans pour le même patient : pas d'unicité.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '41040000-0000-0000-0000-000000000001';
INSERT INTO periodontal_chart (id, cabinet_id, patient_id, measured_at, sites, indices) VALUES
  ('41040000-0000-0000-0000-000000000021', '41040000-0000-0000-0000-000000000001',
   '41040000-0000-0000-0000-000000000010', '2026-07-15 09:00+00',
   '{"11": {"depth_mm": 2}}', '{"plaque_index": 0.1}');
SELECT is(
  (SELECT count(*)::int FROM periodontal_chart
   WHERE patient_id = '41040000-0000-0000-0000-000000000010'),
  2,
  'PC4 periodontal_chart : plusieurs bilans pour le même patient acceptés (série de mesures)');

SELECT * FROM finish();
ROLLBACK;
