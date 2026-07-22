-- 81_lab_work_order.sql
-- pgTAP : lab_work_order (#4147, migration 0193).
--   LWO1. Cabinet A crée un bon de travail complet.
--   LWO2. purchase_price_cents absent refusé (23502, NOT NULL).
--   LWO3. status hors énum refusé (23514).
--   LWO4. patient_id d'un AUTRE cabinet refusé (23503, FK composite).
--   LWO5. quote_item_id d'un AUTRE cabinet refusé (23503, FK composite).
--   LWO6. appointment_id d'un AUTRE cabinet refusé (23503, FK composite).
--   LWO7. RLS : cabinet B ne voit PAS le bon de A.
--   LWO8. Fail-closed : sans GUC → 0 ligne.
-- Exécuté par pg_prove sous nubia_app (NOSUPERUSER, NOBYPASSRLS).
-- Fixtures auto-contenues (BEGIN…ROLLBACK). Préfixe UUID 41470000.
-- Issue : #4147

BEGIN;
SELECT plan(8);

-- ===========================================================================
-- Fixtures : 2 cabinets, cabinet A avec patient/practitioner/appointment/
-- quote/quote_item (nécessaires pour tester les FK composites).
-- ===========================================================================
INSERT INTO app_user (id, email, password_hash, kind) VALUES
  ('41470000-0000-0000-0000-0000000000a1', 'labwork.4147@nubia.test', '$argon2id$fixture', 'pro');

SET LOCAL app.current_cabinet_id = '41470000-0000-0000-0000-000000000c01';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('41470000-0000-0000-0000-000000000c01', 'Cabinet LabWork-4147-A');
INSERT INTO patient (id, cabinet_id, first_name, last_name) VALUES
  ('41470000-0000-0000-0000-0000000000e1', '41470000-0000-0000-0000-000000000c01',
   'Patient', 'LabWorkA');
INSERT INTO practitioner (id, cabinet_id, user_id) VALUES
  ('41470000-0000-0000-0000-0000000000f1', '41470000-0000-0000-0000-000000000c01',
   '41470000-0000-0000-0000-0000000000a1');
INSERT INTO appointment (id, cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status) VALUES
  ('41470000-0000-0000-0000-000000000b01', '41470000-0000-0000-0000-000000000c01',
   '41470000-0000-0000-0000-0000000000e1', '41470000-0000-0000-0000-0000000000f1',
   '2026-01-01 09:00:00+00', '2026-01-01 10:00:00+00', 'confirmed');
INSERT INTO quote (id, cabinet_id, patient_id) VALUES
  ('41470000-0000-0000-0000-000000000901', '41470000-0000-0000-0000-000000000c01',
   '41470000-0000-0000-0000-0000000000e1');
INSERT INTO quote_item (id, cabinet_id, quote_id, label, unit_amount) VALUES
  ('41470000-0000-0000-0000-000000000902', '41470000-0000-0000-0000-000000000c01',
   '41470000-0000-0000-0000-000000000901', 'Couronne céramique', 60000);
RESET app.current_cabinet_id;

SET LOCAL app.current_cabinet_id = '41470000-0000-0000-0000-000000000c02';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('41470000-0000-0000-0000-000000000c02', 'Cabinet LabWork-4147-B');
RESET app.current_cabinet_id;

-- ===========================================================================
-- LWO1. Cabinet A crée un bon de travail complet.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '41470000-0000-0000-0000-000000000c01';
INSERT INTO lab_work_order
    (id, cabinet_id, patient_id, quote_item_id, appointment_id, lab_name, purchase_price_cents, status) VALUES
  ('41470000-0000-0000-0000-000000000d01', '41470000-0000-0000-0000-000000000c01',
   '41470000-0000-0000-0000-0000000000e1', '41470000-0000-0000-0000-000000000902',
   '41470000-0000-0000-0000-000000000b01', 'Labo Dentaire Alpha', 15000, 'sent');
SELECT is(
  (SELECT count(*)::int FROM lab_work_order
   WHERE id = '41470000-0000-0000-0000-000000000d01'),
  1,
  'LWO1 lab_work_order : création cabinet A avec quote_item + appointment OK');

-- ===========================================================================
-- LWO2. purchase_price_cents absent refusé (23502, NOT NULL).
-- ===========================================================================
SELECT throws_ok(
  $$ INSERT INTO lab_work_order (cabinet_id, patient_id, lab_name)
     VALUES ('41470000-0000-0000-0000-000000000c01',
             '41470000-0000-0000-0000-0000000000e1', 'Labo sans prix') $$,
  '23502', NULL,
  'LWO2 lab_work_order_purchase_price_cents_not_null : prix d''achat obligatoire (23502)');

-- ===========================================================================
-- LWO3. status hors énum refusé (23514).
-- ===========================================================================
SELECT throws_ok(
  $$ INSERT INTO lab_work_order (cabinet_id, patient_id, lab_name, purchase_price_cents, status)
     VALUES ('41470000-0000-0000-0000-000000000c01',
             '41470000-0000-0000-0000-0000000000e1', 'Labo Beta', 10000, 'invalide') $$,
  '23514', NULL,
  'LWO3 lab_work_order_status_check : status hors énum refusé (23514)');

-- ===========================================================================
-- LWO4. patient_id d'un AUTRE cabinet refusé (23503, FK composite).
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '41470000-0000-0000-0000-000000000c02';
SELECT throws_ok(
  $$ INSERT INTO lab_work_order (cabinet_id, patient_id, lab_name, purchase_price_cents)
     VALUES ('41470000-0000-0000-0000-000000000c02',
             '41470000-0000-0000-0000-0000000000e1', 'Labo Gamma', 10000) $$,
  '23503', NULL,
  '⭐ LWO4 lab_work_order : patient d''un autre cabinet refusé (23503, FK composite)');

-- ===========================================================================
-- LWO5. quote_item_id d'un AUTRE cabinet refusé (23503, FK composite).
-- Un patient du cabinet B est requis pour isoler la cause de l'échec.
-- ===========================================================================
INSERT INTO patient (id, cabinet_id, first_name, last_name) VALUES
  ('41470000-0000-0000-0000-0000000000e2', '41470000-0000-0000-0000-000000000c02',
   'Patient', 'LabWorkB');
SELECT throws_ok(
  $$ INSERT INTO lab_work_order (cabinet_id, patient_id, quote_item_id, lab_name, purchase_price_cents)
     VALUES ('41470000-0000-0000-0000-000000000c02',
             '41470000-0000-0000-0000-0000000000e2', '41470000-0000-0000-0000-000000000902',
             'Labo Delta', 10000) $$,
  '23503', NULL,
  '⭐ LWO5 lab_work_order : quote_item d''un autre cabinet refusé (23503, FK composite)');

-- ===========================================================================
-- LWO6. appointment_id d'un AUTRE cabinet refusé (23503, FK composite).
-- ===========================================================================
SELECT throws_ok(
  $$ INSERT INTO lab_work_order (cabinet_id, patient_id, appointment_id, lab_name, purchase_price_cents)
     VALUES ('41470000-0000-0000-0000-000000000c02',
             '41470000-0000-0000-0000-0000000000e2', '41470000-0000-0000-0000-000000000b01',
             'Labo Epsilon', 10000) $$,
  '23503', NULL,
  '⭐ LWO6 lab_work_order : appointment d''un autre cabinet refusé (23503, FK composite)');

-- ===========================================================================
-- LWO7. RLS : cabinet B ne voit PAS le bon de A.
-- ===========================================================================
SELECT is(
  (SELECT count(*)::int FROM lab_work_order
   WHERE id = '41470000-0000-0000-0000-000000000d01'),
  0,
  '⭐ LWO7 tenant_isolation : cabinet B ne voit PAS le bon de travail de A');

-- ===========================================================================
-- LWO8. Fail-closed : sans GUC → 0 ligne.
-- ===========================================================================
RESET app.current_cabinet_id;
SELECT is(
  (SELECT count(*)::int FROM lab_work_order),
  0,
  '⭐ LWO8 fail-closed : 0 ligne sans GUC positionné');

SELECT * FROM finish();
ROLLBACK;
