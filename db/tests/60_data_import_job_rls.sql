-- 60_data_import_job_rls.sql
-- pgTAP : RLS data_import_job — isolation cabinet (#4167).
-- Vérifie la policy tenant_isolation ajoutée par la migration 0168 :
--   DIJ1. Cabinet A voit son propre job d'import
--   DIJ2. Cabinet B ne voit pas le job du cabinet A (cross-tenant)
--   DIJ3. Fail-closed : sans GUC app.current_cabinet_id positionné → 0 ligne visible
--   DIJ4. Insertion réussie same-tenant (cabinet A insère et relit son job)
--   DIJ5. status hors énum refusé par le CHECK
-- Exécuté par pg_prove sous nubia_app (NOSUPERUSER, NOBYPASSRLS).
-- Fixtures auto-contenues (BEGIN…ROLLBACK). Préfixe UUID 41670000.
-- Issue : #4167

BEGIN;
SELECT plan(5);

-- ===========================================================================
-- Fixtures : 2 cabinets (A, B), 1 job d'import dans le cabinet A.
-- ===========================================================================

SET LOCAL app.current_cabinet_id = '41670000-0000-0000-0000-000000000001';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('41670000-0000-0000-0000-000000000001', 'Cabinet DataImportJob-4167-A');

SET LOCAL app.current_cabinet_id = '41670000-0000-0000-0000-000000000002';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('41670000-0000-0000-0000-000000000002', 'Cabinet DataImportJob-4167-B');

SET LOCAL app.current_cabinet_id = '41670000-0000-0000-0000-000000000001';

INSERT INTO data_import_job (id, cabinet_id, source_system, status, started_at) VALUES
  ('41670000-0000-0000-0000-000000000030',
   '41670000-0000-0000-0000-000000000001',
   'Logos', 'running', now());

-- ===========================================================================
-- DIJ1. Cabinet A voit son propre job d'import.
-- ===========================================================================
SELECT is(
  (SELECT count(*)::int FROM data_import_job
   WHERE id = '41670000-0000-0000-0000-000000000030'),
  1,
  'DIJ1 data_import_job : cabinet A voit son propre job (tenant_isolation)');

-- ===========================================================================
-- DIJ2. Cabinet B ne voit pas le job du cabinet A (cross-tenant).
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '41670000-0000-0000-0000-000000000002';
SELECT is(
  (SELECT count(*)::int FROM data_import_job
   WHERE id = '41670000-0000-0000-0000-000000000030'),
  0,
  'DIJ2 data_import_job : cabinet B ne voit PAS le job du cabinet A (isolation cross-tenant)');

-- ===========================================================================
-- DIJ3. Fail-closed : sans GUC app.current_cabinet_id positionné → 0 ligne visible.
-- ===========================================================================
RESET app.current_cabinet_id;
SELECT is(
  (SELECT count(*)::int FROM data_import_job
   WHERE id = '41670000-0000-0000-0000-000000000030'),
  0,
  'DIJ3 data_import_job : fail-closed, 0 ligne visible sans GUC positionné');

-- ===========================================================================
-- DIJ4. Insertion réussie same-tenant : cabinet A insère et relit un 2e job.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '41670000-0000-0000-0000-000000000001';
INSERT INTO data_import_job
  (id, cabinet_id, source_system, status, imported_count, error_count, started_at, finished_at)
VALUES
  ('41670000-0000-0000-0000-000000000031',
   '41670000-0000-0000-0000-000000000001',
   'Doctolib Export', 'completed', 150, 3, now() - interval '1 hour', now());
SELECT is(
  (SELECT count(*)::int FROM data_import_job
   WHERE id = '41670000-0000-0000-0000-000000000031'),
  1,
  'DIJ4 data_import_job : insertion + relecture same-tenant réussies');

-- ===========================================================================
-- DIJ5. status hors énum refusé par le CHECK.
-- ===========================================================================
SELECT throws_ok(
  $$ INSERT INTO data_import_job (cabinet_id, source_system, status)
     VALUES ('41670000-0000-0000-0000-000000000001',
             'Logos',
             'archived') $$,
  '23514', NULL,
  'DIJ5 data_import_job_status_check : status hors énum refusé (23514)');

SELECT * FROM finish();
ROLLBACK;
