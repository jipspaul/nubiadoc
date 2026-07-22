-- 80_stock_inventory.sql
-- pgTAP : stock_item / stock_movement / ccam_act_stock_consumption
-- (#4143, migration 0192).
--   SI1.  Cabinet A crée un stock_item.
--   SI2.  Cabinet A crée un mouvement (réception) sur son propre stock_item.
--   SI3.  reason hors énum refusé (CHECK 23514).
--   SI4.  delta = 0 refusé (CHECK 23514).
--   SI5.  Mouvement sur un stock_item d'un AUTRE cabinet refusé (23503, FK composite).
--   SI6.  Mouvement rattaché à un consultation_act d'un AUTRE cabinet refusé (23503, FK composite).
--   SI7.  Référence stock_item dupliquée dans le même cabinet refusée (23505).
--   SI8.  ccam_act_stock_consumption : mapping valide créé.
--   SI9.  ccam_act_stock_consumption : ccam_code inexistant refusé (23503).
--   SI10. ccam_act_stock_consumption : stock_item d'un AUTRE cabinet refusé (23503, FK composite).
--   SI11. RLS : cabinet B ne voit AUCUNE des 3 tables de A.
--   SI12. Fail-closed : sans GUC → 0 ligne sur les 3 tables.
-- Exécuté par pg_prove sous nubia_app (NOSUPERUSER, NOBYPASSRLS).
-- Fixtures auto-contenues (BEGIN…ROLLBACK). Préfixe UUID 41430000.
-- Issue : #4143

BEGIN;
SELECT plan(12);

-- ===========================================================================
-- Fixtures : 2 cabinets, cabinet A avec patient/practitioner/appointment/acte
-- (nécessaire pour tester la FK composite stock_movement→consultation_act).
-- ===========================================================================
INSERT INTO app_user (id, email, password_hash, kind) VALUES
  ('41430000-0000-0000-0000-0000000000a1', 'stock.4143@nubia.test', '$argon2id$fixture', 'pro');

SET LOCAL app.current_cabinet_id = '41430000-0000-0000-0000-000000000c01';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('41430000-0000-0000-0000-000000000c01', 'Cabinet Stock-4143-A');
INSERT INTO patient (id, cabinet_id, first_name, last_name) VALUES
  ('41430000-0000-0000-0000-0000000000e1', '41430000-0000-0000-0000-000000000c01',
   'Patient', 'StockA');
INSERT INTO practitioner (id, cabinet_id, user_id) VALUES
  ('41430000-0000-0000-0000-0000000000f1', '41430000-0000-0000-0000-000000000c01',
   '41430000-0000-0000-0000-0000000000a1');
INSERT INTO appointment (id, cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status) VALUES
  ('41430000-0000-0000-0000-000000000b01', '41430000-0000-0000-0000-000000000c01',
   '41430000-0000-0000-0000-0000000000e1', '41430000-0000-0000-0000-0000000000f1',
   '2026-01-01 09:00:00+00', '2026-01-01 10:00:00+00', 'in_progress');
INSERT INTO consultation_act
    (id, cabinet_id, appointment_id, patient_id, practitioner_id, ccam_code, label, amount_cents) VALUES
  ('41430000-0000-0000-0000-000000000ac1', '41430000-0000-0000-0000-000000000c01',
   '41430000-0000-0000-0000-000000000b01', '41430000-0000-0000-0000-0000000000e1',
   '41430000-0000-0000-0000-0000000000f1', 'HBLD001', 'Détartrage', 7500);
INSERT INTO stock_item (id, cabinet_id, reference, label, unit, quantity_on_hand, alert_threshold) VALUES
  ('41430000-0000-0000-0000-000000000901', '41430000-0000-0000-0000-000000000c01',
   'GANTS-M', 'Gants latex M', 'boite', 10, 3);
RESET app.current_cabinet_id;

SET LOCAL app.current_cabinet_id = '41430000-0000-0000-0000-000000000c02';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('41430000-0000-0000-0000-000000000c02', 'Cabinet Stock-4143-B');
INSERT INTO stock_item (id, cabinet_id, reference, label, unit, quantity_on_hand) VALUES
  ('41430000-0000-0000-0000-000000000902', '41430000-0000-0000-0000-000000000c02',
   'GANTS-M', 'Gants latex M', 'boite', 5);
RESET app.current_cabinet_id;

-- ===========================================================================
-- SI1. Cabinet A crée un stock_item (déjà fait en fixture) — vérifié ici.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '41430000-0000-0000-0000-000000000c01';
SELECT is(
  (SELECT quantity_on_hand FROM stock_item
   WHERE id = '41430000-0000-0000-0000-000000000901'),
  10,
  'SI1 stock_item : création cabinet A OK (quantity_on_hand = 10)');

-- ===========================================================================
-- SI2. Cabinet A crée un mouvement de réception sur son propre stock_item.
-- ===========================================================================
INSERT INTO stock_movement (id, cabinet_id, stock_item_id, delta, reason, consultation_act_id) VALUES
  ('41430000-0000-0000-0000-000000000a01', '41430000-0000-0000-0000-000000000c01',
   '41430000-0000-0000-0000-000000000901', 20, 'reception', NULL);
SELECT is(
  (SELECT count(*)::int FROM stock_movement
   WHERE id = '41430000-0000-0000-0000-000000000a01'),
  1,
  'SI2 stock_movement : réception cabinet A sur son propre stock_item OK');

-- ===========================================================================
-- SI3. reason hors énum refusé (CHECK).
-- ===========================================================================
SELECT throws_ok(
  $$ INSERT INTO stock_movement (cabinet_id, stock_item_id, delta, reason)
     VALUES ('41430000-0000-0000-0000-000000000c01',
             '41430000-0000-0000-0000-000000000901', 1, 'invalide') $$,
  '23514', NULL,
  'SI3 stock_movement_reason_check : reason hors énum refusé (23514)');

-- ===========================================================================
-- SI4. delta = 0 refusé (CHECK).
-- ===========================================================================
SELECT throws_ok(
  $$ INSERT INTO stock_movement (cabinet_id, stock_item_id, delta, reason)
     VALUES ('41430000-0000-0000-0000-000000000c01',
             '41430000-0000-0000-0000-000000000901', 0, 'adjustment') $$,
  '23514', NULL,
  'SI4 stock_movement_delta_check : delta = 0 refusé (23514)');

-- ===========================================================================
-- SI5. Mouvement sur un stock_item d'un AUTRE cabinet refusé (23503) —
-- FK composite (stock_item_id, cabinet_id), le mismatch cabinet_id ne
-- correspond à aucune ligne de l'index unique de stock_item.
-- ===========================================================================
SELECT throws_ok(
  $$ INSERT INTO stock_movement (cabinet_id, stock_item_id, delta, reason)
     VALUES ('41430000-0000-0000-0000-000000000c01',
             '41430000-0000-0000-0000-000000000902', 1, 'adjustment') $$,
  '23503', NULL,
  '⭐ SI5 stock_movement : mouvement sur un stock_item d''un autre cabinet refusé (23503, FK composite)');

-- ===========================================================================
-- SI6. Mouvement rattaché à un consultation_act d'un AUTRE cabinet refusé
-- (23503) — même logique FK composite que #4137/migration 0190.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '41430000-0000-0000-0000-000000000c02';
SELECT throws_ok(
  $$ INSERT INTO stock_movement (cabinet_id, stock_item_id, delta, reason, consultation_act_id)
     VALUES ('41430000-0000-0000-0000-000000000c02',
             '41430000-0000-0000-0000-000000000902', -1, 'consumption',
             '41430000-0000-0000-0000-000000000ac1') $$,
  '23503', NULL,
  '⭐ SI6 stock_movement : rattachement à un acte d''un autre cabinet refusé (23503, FK composite)');

-- ===========================================================================
-- SI7. Référence stock_item dupliquée dans le même cabinet refusée (23505).
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '41430000-0000-0000-0000-000000000c01';
SELECT throws_ok(
  $$ INSERT INTO stock_item (cabinet_id, reference, label, unit)
     VALUES ('41430000-0000-0000-0000-000000000c01', 'GANTS-M', 'Doublon', 'boite') $$,
  '23505', NULL,
  'SI7 stock_item_cabinet_id_reference_key : référence dupliquée refusée (23505)');

-- ===========================================================================
-- SI8. ccam_act_stock_consumption : mapping valide créé (ccam_code HBLD001,
-- déjà seedé dans le catalogue ccam_act — cf. 76_cr_template.sql).
-- ===========================================================================
INSERT INTO ccam_act_stock_consumption (id, cabinet_id, ccam_code, stock_item_id, quantity) VALUES
  ('41430000-0000-0000-0000-000000000b01', '41430000-0000-0000-0000-000000000c01',
   'HBLD001', '41430000-0000-0000-0000-000000000901', 2);
SELECT is(
  (SELECT quantity FROM ccam_act_stock_consumption
   WHERE id = '41430000-0000-0000-0000-000000000b01'),
  2,
  'SI8 ccam_act_stock_consumption : mapping HBLD001 → GANTS-M (x2) créé');

-- ===========================================================================
-- SI9. ccam_code inexistant dans le catalogue ccam_act refusé (23503).
-- ===========================================================================
SELECT throws_ok(
  $$ INSERT INTO ccam_act_stock_consumption (cabinet_id, ccam_code, stock_item_id, quantity)
     VALUES ('41430000-0000-0000-0000-000000000c01',
             'CODE_INEXISTANT', '41430000-0000-0000-0000-000000000901', 1) $$,
  '23503', NULL,
  'SI9 ccam_act_stock_consumption_ccam_code_fkey : code CCAM inexistant refusé (23503)');

-- ===========================================================================
-- SI10. stock_item d'un AUTRE cabinet refusé (23503, FK composite).
-- ===========================================================================
SELECT throws_ok(
  $$ INSERT INTO ccam_act_stock_consumption (cabinet_id, ccam_code, stock_item_id, quantity)
     VALUES ('41430000-0000-0000-0000-000000000c01',
             'HBLD001', '41430000-0000-0000-0000-000000000902', 1) $$,
  '23503', NULL,
  '⭐ SI10 ccam_act_stock_consumption : stock_item d''un autre cabinet refusé (23503, FK composite)');

-- ===========================================================================
-- SI11. RLS : cabinet B ne voit AUCUNE des 3 tables de A.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '41430000-0000-0000-0000-000000000c02';
SELECT is(
  (SELECT count(*)::int FROM stock_item WHERE cabinet_id = '41430000-0000-0000-0000-000000000c01') +
  (SELECT count(*)::int FROM stock_movement WHERE cabinet_id = '41430000-0000-0000-0000-000000000c01') +
  (SELECT count(*)::int FROM ccam_act_stock_consumption WHERE cabinet_id = '41430000-0000-0000-0000-000000000c01'),
  0,
  '⭐ SI11 tenant_isolation : cabinet B ne voit aucune des 3 tables de A');

-- ===========================================================================
-- SI12. Fail-closed : sans GUC → 0 ligne sur les 3 tables.
-- ===========================================================================
RESET app.current_cabinet_id;
SELECT is(
  (SELECT count(*)::int FROM stock_item) +
  (SELECT count(*)::int FROM stock_movement) +
  (SELECT count(*)::int FROM ccam_act_stock_consumption),
  0,
  '⭐ SI12 fail-closed : 0 ligne sans GUC positionné (3 tables)');

SELECT * FROM finish();
ROLLBACK;
