-- 97_lab_work_order_shipping_status.sql
-- pgTAP : statut d'expédition/réception sur lab_work_order (#7209, migration 0274).
--   LWOS1. shipped_at/received_at/tracking_ref insérables et lisibles.
--   LWOS2. Transition vers les nouveaux statuts ('in_progress','shipped','received') acceptée.
--   LWOS3. Anciens statuts ('try_in','returned') toujours acceptés (rétro-compat, aucune ligne cassée).
--   LWOS4. status hors énum étendue toujours refusé (23514).
--   LWOS5. Index (cabinet_id, expected_return_at) présent pour la vue du jour.
-- Exécuté par pg_prove sous nubia_app (NOSUPERUSER, NOBYPASSRLS).
-- Fixtures auto-contenues (BEGIN…ROLLBACK). Préfixe UUID 72090000.
-- Issue : #7209

BEGIN;
SELECT plan(5);

-- ===========================================================================
-- Fixtures : 1 cabinet + patient (FK composite requise par lab_work_order).
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '72090000-0000-0000-0000-000000000c01';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('72090000-0000-0000-0000-000000000c01', 'Cabinet LabWork-7209');
INSERT INTO patient (id, cabinet_id, first_name, last_name) VALUES
  ('72090000-0000-0000-0000-0000000000e1', '72090000-0000-0000-0000-000000000c01',
   'Patient', 'LabWork7209');

-- ===========================================================================
-- LWOS1. shipped_at/received_at/tracking_ref insérables et lisibles.
-- ===========================================================================
INSERT INTO lab_work_order
    (id, cabinet_id, patient_id, lab_name, purchase_price_cents, status,
     shipped_at, received_at, tracking_ref) VALUES
  ('72090000-0000-0000-0000-000000000d01', '72090000-0000-0000-0000-000000000c01',
   '72090000-0000-0000-0000-0000000000e1', 'Labo Dentaire 7209', 15000, 'received',
   '2026-01-05 08:00:00+00', '2026-01-08 10:00:00+00', 'COLISSIMO-7209XYZ');
SELECT is(
  (SELECT tracking_ref FROM lab_work_order
   WHERE id = '72090000-0000-0000-0000-000000000d01'),
  'COLISSIMO-7209XYZ',
  'LWOS1 lab_work_order : shipped_at/received_at/tracking_ref enregistrés');

-- ===========================================================================
-- LWOS2. Transition vers les nouveaux statuts acceptée.
-- ===========================================================================
INSERT INTO lab_work_order
    (id, cabinet_id, patient_id, lab_name, purchase_price_cents, status) VALUES
  ('72090000-0000-0000-0000-000000000d02', '72090000-0000-0000-0000-000000000c01',
   '72090000-0000-0000-0000-0000000000e1', 'Labo Dentaire 7209', 12000, 'in_progress');
UPDATE lab_work_order SET status = 'shipped'
  WHERE id = '72090000-0000-0000-0000-000000000d02';
SELECT is(
  (SELECT status FROM lab_work_order
   WHERE id = '72090000-0000-0000-0000-000000000d02'),
  'shipped',
  'LWOS2 lab_work_order : transition in_progress -> shipped acceptée');

-- ===========================================================================
-- LWOS3. Anciens statuts toujours acceptés (rétro-compat).
-- ===========================================================================
INSERT INTO lab_work_order
    (id, cabinet_id, patient_id, lab_name, purchase_price_cents, status) VALUES
  ('72090000-0000-0000-0000-000000000d03', '72090000-0000-0000-0000-000000000c01',
   '72090000-0000-0000-0000-0000000000e1', 'Labo Dentaire 7209', 8000, 'try_in');
UPDATE lab_work_order SET status = 'returned'
  WHERE id = '72090000-0000-0000-0000-000000000d03';
SELECT is(
  (SELECT status FROM lab_work_order
   WHERE id = '72090000-0000-0000-0000-000000000d03'),
  'returned',
  '⭐ LWOS3 lab_work_order : anciens statuts try_in/returned toujours acceptés');

-- ===========================================================================
-- LWOS4. status hors énum étendue toujours refusé (23514).
-- ===========================================================================
SELECT throws_ok(
  $$ INSERT INTO lab_work_order (cabinet_id, patient_id, lab_name, purchase_price_cents, status)
     VALUES ('72090000-0000-0000-0000-000000000c01',
             '72090000-0000-0000-0000-0000000000e1', 'Labo Zeta', 9000, 'invalide') $$,
  '23514', NULL,
  'LWOS4 lab_work_order_status_check : status hors énum étendue refusé (23514)');

-- ===========================================================================
-- LWOS5. Index (cabinet_id, expected_return_at) présent pour la vue du jour.
-- ===========================================================================
SELECT is(
  (SELECT count(*)::int FROM pg_indexes
   WHERE tablename = 'lab_work_order'
     AND indexname = 'idx_lab_work_order_cabinet_expected_return'),
  1,
  'LWOS5 idx_lab_work_order_cabinet_expected_return : index présent');

SELECT * FROM finish();
ROLLBACK;
