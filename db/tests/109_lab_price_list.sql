-- 109_lab_price_list.sql
-- pgTAP : lab_price_list + lab_work_order.price_list_item_id
-- (migration 0292, #7165, DP-F19.a).
--   LPL1. Cabinet A crée une ligne de grille tarifaire OK.
--   LPL2. lab_name vide (après trim) refusé (23514).
--   LPL3. price_cents négatif refusé (23514).
--   LPL4. Doublon (cabinet_id, lab_name, item_code, valid_from) refusé (23505).
--   LPL5. lab_work_order.price_list_item_id : rattachement même cabinet OK.
--   LPL6. price_list_item_id d'un AUTRE cabinet refusé (23503, FK composite).
--   LPL7. RLS : cabinet B ne voit PAS la ligne de grille de A.
--   LPL8. Fail-closed : sans GUC → 0 ligne.
-- Exécuté par pg_prove sous nubia_app (NOSUPERUSER, NOBYPASSRLS).
-- Fixtures auto-contenues (BEGIN…ROLLBACK). Préfixe UUID 71650000.
-- Issue : #7165

BEGIN;
SELECT plan(8);

-- ===========================================================================
-- Fixtures : 2 cabinets, chacun avec un patient (requis par lab_work_order).
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '71650000-0000-0000-0000-000000000c01';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('71650000-0000-0000-0000-000000000c01', 'Cabinet PriceList-7165-A');
INSERT INTO patient (id, cabinet_id, first_name, last_name) VALUES
  ('71650000-0000-0000-0000-0000000000e1', '71650000-0000-0000-0000-000000000c01',
   'Patient', 'PriceListA');
RESET app.current_cabinet_id;

SET LOCAL app.current_cabinet_id = '71650000-0000-0000-0000-000000000c02';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('71650000-0000-0000-0000-000000000c02', 'Cabinet PriceList-7165-B');
INSERT INTO patient (id, cabinet_id, first_name, last_name) VALUES
  ('71650000-0000-0000-0000-0000000000e2', '71650000-0000-0000-0000-000000000c02',
   'Patient', 'PriceListB');
RESET app.current_cabinet_id;

-- ===========================================================================
-- LPL1. Cabinet A crée une ligne de grille tarifaire OK.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '71650000-0000-0000-0000-000000000c01';
INSERT INTO lab_price_list
    (id, cabinet_id, lab_name, item_label, item_code, price_cents, valid_from) VALUES
  ('71650000-0000-0000-0000-000000005101', '71650000-0000-0000-0000-000000000c01',
   'Labo Dentaire Alpha', 'Couronne céramique', 'CC-01', 12000, '2026-01-01');
SELECT is(
  (SELECT count(*)::int FROM lab_price_list
   WHERE id = '71650000-0000-0000-0000-000000005101'),
  1,
  'LPL1 lab_price_list : création cabinet A OK');

-- ===========================================================================
-- LPL2. lab_name vide (après trim) refusé (23514).
-- ===========================================================================
SELECT throws_ok(
  $$ INSERT INTO lab_price_list (cabinet_id, lab_name, item_label, item_code, price_cents)
     VALUES ('71650000-0000-0000-0000-000000000c01',
             '   ', 'Bridge zircone', 'BZ-01', 20000) $$,
  '23514', NULL,
  'LPL2 lab_price_list_lab_name_not_blank : lab_name vide refusé (23514)');

-- ===========================================================================
-- LPL3. price_cents négatif refusé (23514).
-- ===========================================================================
SELECT throws_ok(
  $$ INSERT INTO lab_price_list (cabinet_id, lab_name, item_label, item_code, price_cents)
     VALUES ('71650000-0000-0000-0000-000000000c01',
             'Labo Dentaire Alpha', 'Bridge zircone', 'BZ-01', -1) $$,
  '23514', NULL,
  'LPL3 lab_price_list_price_cents_check : prix négatif refusé (23514)');

-- ===========================================================================
-- LPL4. Doublon (cabinet_id, lab_name, item_code, valid_from) refusé (23505).
-- ===========================================================================
SELECT throws_ok(
  $$ INSERT INTO lab_price_list (cabinet_id, lab_name, item_label, item_code, price_cents, valid_from)
     VALUES ('71650000-0000-0000-0000-000000000c01',
             'Labo Dentaire Alpha', 'Couronne céramique (autre libellé)', 'CC-01', 12500, '2026-01-01') $$,
  '23505', NULL,
  'LPL4 lab_price_list_lab_item_valid_from_uniq : doublon (labo, code, date) refusé (23505)');

-- ===========================================================================
-- LPL5. lab_work_order.price_list_item_id : rattachement même cabinet OK.
-- ===========================================================================
INSERT INTO lab_work_order
    (id, cabinet_id, patient_id, lab_name, purchase_price_cents, price_list_item_id) VALUES
  ('71650000-0000-0000-0000-000000006101', '71650000-0000-0000-0000-000000000c01',
   '71650000-0000-0000-0000-0000000000e1', 'Labo Dentaire Alpha', 12000,
   '71650000-0000-0000-0000-000000005101');
SELECT is(
  (SELECT price_list_item_id FROM lab_work_order
   WHERE id = '71650000-0000-0000-0000-000000006101'),
  '71650000-0000-0000-0000-000000005101'::uuid,
  'LPL5 lab_work_order.price_list_item_id : rattachement même cabinet OK');

-- ===========================================================================
-- LPL6. price_list_item_id d'un AUTRE cabinet refusé (23503, FK composite).
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '71650000-0000-0000-0000-000000000c02';
SELECT throws_ok(
  $$ INSERT INTO lab_work_order (cabinet_id, patient_id, lab_name, purchase_price_cents, price_list_item_id)
     VALUES ('71650000-0000-0000-0000-000000000c02',
             '71650000-0000-0000-0000-0000000000e2', 'Labo Dentaire Alpha', 12000,
             '71650000-0000-0000-0000-000000005101') $$,
  '23503', NULL,
  '⭐ LPL6 lab_work_order : price_list_item_id d''un autre cabinet refusé (23503, FK composite)');

-- ===========================================================================
-- LPL7. RLS : cabinet B ne voit PAS la ligne de grille de A.
-- ===========================================================================
SELECT is(
  (SELECT count(*)::int FROM lab_price_list
   WHERE id = '71650000-0000-0000-0000-000000005101'),
  0,
  '⭐ LPL7 tenant_isolation : cabinet B ne voit PAS la ligne de grille de A');

-- ===========================================================================
-- LPL8. Fail-closed : sans GUC → 0 ligne.
-- ===========================================================================
RESET app.current_cabinet_id;
SELECT is(
  (SELECT count(*)::int FROM lab_price_list),
  0,
  '⭐ LPL8 fail-closed : 0 ligne sans GUC positionné');

SELECT * FROM finish();
ROLLBACK;
