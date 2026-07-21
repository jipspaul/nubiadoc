-- 64_appointment_motif_rls.sql
-- pgTAP : RLS appointment_motif — isolation cabinet (#4084).
-- Vérifie la policy tenant_isolation ajoutée par la migration 0172 :
--   AM1. Cabinet A voit son propre motif
--   AM2. Cabinet B ne voit pas le motif du cabinet A (cross-tenant)
--   AM3. Fail-closed : sans GUC app.current_cabinet_id positionné → 0 ligne visible
--   AM4. Insertion réussie same-tenant (cabinet A insère et relit un motif)
--   AM5. default_duration_minutes <= 0 refusé par le CHECK
-- Exécuté par pg_prove sous nubia_app (NOSUPERUSER, NOBYPASSRLS).
-- Fixtures auto-contenues (BEGIN…ROLLBACK). Préfixe UUID 40840000.
-- Issue : #4084

BEGIN;
SELECT plan(5);

-- ===========================================================================
-- Fixtures : 2 cabinets (A, B), 1 motif dans le cabinet A.
-- ===========================================================================

SET LOCAL app.current_cabinet_id = '40840000-0000-0000-0000-000000000001';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('40840000-0000-0000-0000-000000000001', 'Cabinet AppointmentMotif-4084-A');

SET LOCAL app.current_cabinet_id = '40840000-0000-0000-0000-000000000002';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('40840000-0000-0000-0000-000000000002', 'Cabinet AppointmentMotif-4084-B');

SET LOCAL app.current_cabinet_id = '40840000-0000-0000-0000-000000000001';

INSERT INTO appointment_motif (id, cabinet_id, label, default_duration_minutes) VALUES
  ('40840000-0000-0000-0000-000000000030',
   '40840000-0000-0000-0000-000000000001',
   'Détartrage',
   30);

-- ===========================================================================
-- AM1. Cabinet A voit son propre motif.
-- ===========================================================================
SELECT is(
  (SELECT count(*)::int FROM appointment_motif
   WHERE id = '40840000-0000-0000-0000-000000000030'),
  1,
  'AM1 appointment_motif : cabinet A voit son propre motif (tenant_isolation)');

-- ===========================================================================
-- AM2. Cabinet B ne voit pas le motif du cabinet A (cross-tenant).
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '40840000-0000-0000-0000-000000000002';
SELECT is(
  (SELECT count(*)::int FROM appointment_motif
   WHERE id = '40840000-0000-0000-0000-000000000030'),
  0,
  'AM2 appointment_motif : cabinet B ne voit PAS le motif du cabinet A (isolation cross-tenant)');

-- ===========================================================================
-- AM3. Fail-closed : sans GUC app.current_cabinet_id positionné → 0 ligne visible.
-- ===========================================================================
RESET app.current_cabinet_id;
SELECT is(
  (SELECT count(*)::int FROM appointment_motif
   WHERE id = '40840000-0000-0000-0000-000000000030'),
  0,
  'AM3 appointment_motif : fail-closed, 0 ligne visible sans GUC positionné');

-- ===========================================================================
-- AM4. Insertion réussie same-tenant : cabinet A insère et relit un 2e motif.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '40840000-0000-0000-0000-000000000001';
INSERT INTO appointment_motif (id, cabinet_id, label, default_duration_minutes) VALUES
  ('40840000-0000-0000-0000-000000000031',
   '40840000-0000-0000-0000-000000000001',
   'Urgence douleur',
   NULL);
SELECT is(
  (SELECT count(*)::int FROM appointment_motif
   WHERE id = '40840000-0000-0000-0000-000000000031'),
  1,
  'AM4 appointment_motif : insertion + relecture same-tenant réussies (durée NULL acceptée)');

-- ===========================================================================
-- AM5. default_duration_minutes <= 0 refusé par le CHECK.
-- ===========================================================================
SELECT throws_ok(
  $$ INSERT INTO appointment_motif (cabinet_id, label, default_duration_minutes)
     VALUES ('40840000-0000-0000-0000-000000000001',
             'Motif invalide',
             0) $$,
  '23514', NULL,
  'AM5 appointment_motif_duration_positive : durée <= 0 refusée (23514)');

SELECT * FROM finish();
ROLLBACK;
