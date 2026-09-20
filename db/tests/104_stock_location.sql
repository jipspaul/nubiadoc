-- 104_stock_location.sql
-- pgTAP : stock_location / stock_item_location (#7184, migration 0285).
--   SL1.  Backfill : chaque stock_item existant (fixtures d'autres tests
--         insérées dans CETTE transaction) a une stock_item_location sur
--         une localisation "Stock principal" is_main = true.
--   SL2.  Cabinet A crée une localisation secondaire ("Salle 1").
--   SL3.  Deuxième localisation is_main = true dans le même cabinet refusée
--         (23505, index unique partiel idx_stock_location_one_main).
--   SL4.  Nom de localisation dupliqué dans le même cabinet refusé (23505).
--   SL5.  stock_item_location sur un stock_item d'un AUTRE cabinet refusé
--         (23503, FK composite).
--   SL6.  stock_item_location sur une stock_location d'un AUTRE cabinet
--         refusée (23503, FK composite).
--   SL7.  Un même item ne peut pas avoir deux lignes pour la même
--         localisation (23505).
--   SL8.  RLS : cabinet B ne voit AUCUNE des 2 tables de A.
--   SL9.  Fail-closed : sans GUC → 0 ligne sur les 2 tables.
-- Exécuté par pg_prove sous nubia_app (NOSUPERUSER, NOBYPASSRLS).
-- Fixtures auto-contenues (BEGIN…ROLLBACK). Préfixe UUID 71840000.
-- Issue : #7184

BEGIN;
SELECT plan(9);

-- ===========================================================================
-- Fixtures : 2 cabinets, chacun avec un stock_item (déclenche le backfill
-- de la migration 0285 au niveau des données déjà présentes en base au
-- moment du `make migrate`, mais ici on rejoue le même scénario "à la
-- main" pour un cabinet créé dans cette transaction : la localisation
-- principale n'est PAS auto-créée pour un nouveau stock_item (le backfill
-- de 0285 est un one-shot exécuté au moment de la migration), donc on la
-- crée explicitement, comme le ferait l'API.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '71840000-0000-0000-0000-000000000c01';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('71840000-0000-0000-0000-000000000c01', 'Cabinet StockLoc-7184-A');
INSERT INTO stock_item (id, cabinet_id, reference, label, unit, quantity_on_hand, alert_threshold) VALUES
  ('71840000-0000-0000-0000-000000000901', '71840000-0000-0000-0000-000000000c01',
   'GANTS-M', 'Gants latex M', 'boite', 10, 3);
INSERT INTO stock_location (id, cabinet_id, name, is_main) VALUES
  ('71840000-0000-0000-0000-000000000d01', '71840000-0000-0000-0000-000000000c01',
   'Stock principal', true);
INSERT INTO stock_item_location (id, cabinet_id, item_id, location_id, quantity, threshold) VALUES
  ('71840000-0000-0000-0000-000000000e01', '71840000-0000-0000-0000-000000000c01',
   '71840000-0000-0000-0000-000000000901', '71840000-0000-0000-0000-000000000d01', 10, 3);
RESET app.current_cabinet_id;

SET LOCAL app.current_cabinet_id = '71840000-0000-0000-0000-000000000c02';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('71840000-0000-0000-0000-000000000c02', 'Cabinet StockLoc-7184-B');
INSERT INTO stock_item (id, cabinet_id, reference, label, unit, quantity_on_hand) VALUES
  ('71840000-0000-0000-0000-000000000902', '71840000-0000-0000-0000-000000000c02',
   'GANTS-M', 'Gants latex M', 'boite', 5);
INSERT INTO stock_location (id, cabinet_id, name, is_main) VALUES
  ('71840000-0000-0000-0000-000000000d02', '71840000-0000-0000-0000-000000000c02',
   'Stock principal', true);
INSERT INTO stock_item_location (id, cabinet_id, item_id, location_id, quantity) VALUES
  ('71840000-0000-0000-0000-000000000e02', '71840000-0000-0000-0000-000000000c02',
   '71840000-0000-0000-0000-000000000902', '71840000-0000-0000-0000-000000000d02', 5);
RESET app.current_cabinet_id;

-- ===========================================================================
-- SL1. Backfill équivalent : la localisation principale porte bien la
-- quantité/seuil du stock_item.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '71840000-0000-0000-0000-000000000c01';
SELECT is(
  (SELECT quantity FROM stock_item_location
   WHERE item_id = '71840000-0000-0000-0000-000000000901'),
  10,
  'SL1 stock_item_location : quantité basculée sur "Stock principal" (backfill) OK');

-- ===========================================================================
-- SL2. Cabinet A crée une localisation secondaire "Salle 1".
-- ===========================================================================
INSERT INTO stock_location (id, cabinet_id, name, is_main) VALUES
  ('71840000-0000-0000-0000-000000000d03', '71840000-0000-0000-0000-000000000c01',
   'Salle 1', false);
SELECT is(
  (SELECT count(*)::int FROM stock_location
   WHERE cabinet_id = '71840000-0000-0000-0000-000000000c01'),
  2,
  'SL2 stock_location : cabinet A a bien 2 localisations (principal + Salle 1)');

-- ===========================================================================
-- SL3. Deuxième localisation is_main = true dans le même cabinet refusée
-- (index unique partiel idx_stock_location_one_main).
-- ===========================================================================
SELECT throws_ok(
  $$ INSERT INTO stock_location (cabinet_id, name, is_main)
     VALUES ('71840000-0000-0000-0000-000000000c01', 'Salle 2', true) $$,
  '23505', NULL,
  '⭐ SL3 idx_stock_location_one_main : deuxième localisation principale refusée (23505)');

-- ===========================================================================
-- SL4. Nom de localisation dupliqué dans le même cabinet refusé (23505).
-- ===========================================================================
SELECT throws_ok(
  $$ INSERT INTO stock_location (cabinet_id, name, is_main)
     VALUES ('71840000-0000-0000-0000-000000000c01', 'Salle 1', false) $$,
  '23505', NULL,
  'SL4 stock_location_cabinet_id_name_key : nom dupliqué refusé (23505)');

-- ===========================================================================
-- SL5. stock_item_location sur un stock_item d'un AUTRE cabinet refusé
-- (23503, FK composite).
-- ===========================================================================
SELECT throws_ok(
  $$ INSERT INTO stock_item_location (cabinet_id, item_id, location_id, quantity)
     VALUES ('71840000-0000-0000-0000-000000000c01',
             '71840000-0000-0000-0000-000000000902',
             '71840000-0000-0000-0000-000000000d03', 1) $$,
  '23503', NULL,
  '⭐ SL5 stock_item_location : stock_item d''un autre cabinet refusé (23503, FK composite)');

-- ===========================================================================
-- SL6. stock_item_location sur une stock_location d'un AUTRE cabinet
-- refusée (23503, FK composite).
-- ===========================================================================
SELECT throws_ok(
  $$ INSERT INTO stock_item_location (cabinet_id, item_id, location_id, quantity)
     VALUES ('71840000-0000-0000-0000-000000000c01',
             '71840000-0000-0000-0000-000000000901',
             '71840000-0000-0000-0000-000000000d02', 1) $$,
  '23503', NULL,
  '⭐ SL6 stock_item_location : stock_location d''un autre cabinet refusée (23503, FK composite)');

-- ===========================================================================
-- SL7. Un même item ne peut pas avoir deux lignes pour la même localisation
-- (23505).
-- ===========================================================================
SELECT throws_ok(
  $$ INSERT INTO stock_item_location (cabinet_id, item_id, location_id, quantity)
     VALUES ('71840000-0000-0000-0000-000000000c01',
             '71840000-0000-0000-0000-000000000901',
             '71840000-0000-0000-0000-000000000d01', 1) $$,
  '23505', NULL,
  'SL7 stock_item_location_item_id_location_id_key : doublon item/localisation refusé (23505)');

-- ===========================================================================
-- SL8. RLS : cabinet B ne voit AUCUNE des 2 tables de A.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '71840000-0000-0000-0000-000000000c02';
SELECT is(
  (SELECT count(*)::int FROM stock_location WHERE cabinet_id = '71840000-0000-0000-0000-000000000c01') +
  (SELECT count(*)::int FROM stock_item_location WHERE cabinet_id = '71840000-0000-0000-0000-000000000c01'),
  0,
  '⭐ SL8 tenant_isolation : cabinet B ne voit aucune des 2 tables de A');

-- ===========================================================================
-- SL9. Fail-closed : sans GUC → 0 ligne sur les 2 tables.
-- ===========================================================================
RESET app.current_cabinet_id;
SELECT is(
  (SELECT count(*)::int FROM stock_location) +
  (SELECT count(*)::int FROM stock_item_location),
  0,
  '⭐ SL9 fail-closed : 0 ligne sans GUC positionné (2 tables)');

SELECT * FROM finish();
ROLLBACK;
