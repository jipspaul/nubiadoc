-- 44_stock_request_rls.sql — Contrat RLS stock_request (issue #3310, lot B5).
-- Vérifie : fail-closed · isolation des deux ancres (cabinet émetteur /
-- pharmacie destinataire) · WITH CHECK (le cabinet ne forge pas une réponse,
-- la pharmacie ne forge pas une annulation) · pas de DELETE.
-- Exécuté par pg_prove sous nubia_app. Fixtures BEGIN…ROLLBACK. Préfixe 33100000.

BEGIN;
SELECT * FROM no_plan();

-- Fixtures : cabinet A → pharmacie X ; cabinet B et pharmacie Y témoins.
SET LOCAL app.current_cabinet_id = '33100000-0000-0000-0000-000000000001';
INSERT INTO cabinet (id, raison_sociale)
  VALUES ('33100000-0000-0000-0000-000000000001', 'Cabinet B5-A')
  ON CONFLICT DO NOTHING;
RESET app.current_cabinet_id;
SET LOCAL app.current_pharmacy_id = '33100000-0000-0000-0000-0000000000f1';
INSERT INTO pharmacy (id, raison_sociale, is_listed)
  VALUES ('33100000-0000-0000-0000-0000000000f1', 'Pharmacie B5-X', true)
  ON CONFLICT DO NOTHING;
RESET app.current_pharmacy_id;

SET LOCAL app.current_cabinet_id = '33100000-0000-0000-0000-000000000001';
INSERT INTO stock_request (id, cabinet_id, pharmacy_id, created_by, cabinet_name, items)
  VALUES ('33100000-0000-0000-0000-000000000051',
          '33100000-0000-0000-0000-000000000001',
          '33100000-0000-0000-0000-0000000000f1',
          '33100000-0000-0000-0000-0000000000a1',
          'Cabinet B5-A',
          '[{"label": "Compresses stériles", "qty": 10}]')
  ON CONFLICT DO NOTHING;
RESET app.current_cabinet_id;

-- 1. Fail-closed sans GUC.
SELECT is(
  (SELECT count(*)::int FROM stock_request WHERE id = '33100000-0000-0000-0000-000000000051'),
  0, '⭐ fail-closed : demande invisible sans GUC');

-- 2. Isolation cabinet.
SET LOCAL app.current_cabinet_id = '33100000-0000-0000-0000-000000000001';
SELECT is(
  (SELECT count(*)::int FROM stock_request WHERE id = '33100000-0000-0000-0000-000000000051'),
  1, 'cabinet émetteur : voit sa demande');
SET LOCAL app.current_cabinet_id = '33100000-0000-0000-0000-000000000002';
SELECT is(
  (SELECT count(*)::int FROM stock_request WHERE id = '33100000-0000-0000-0000-000000000051'),
  0, '⭐ non-fuite : autre cabinet ne voit rien');
RESET app.current_cabinet_id;

-- 3. Isolation pharmacie.
SET LOCAL app.current_pharmacy_id = '33100000-0000-0000-0000-0000000000f1';
SELECT is(
  (SELECT count(*)::int FROM stock_request WHERE id = '33100000-0000-0000-0000-000000000051'),
  1, 'pharmacie destinataire : voit la demande');
SET LOCAL app.current_pharmacy_id = '33100000-0000-0000-0000-0000000000f2';
SELECT is(
  (SELECT count(*)::int FROM stock_request WHERE id = '33100000-0000-0000-0000-000000000051'),
  0, '⭐ non-fuite : autre pharmacie ne voit rien');
RESET app.current_pharmacy_id;

-- 4. WITH CHECK : le cabinet ne forge pas une réponse pharmacie.
SET LOCAL app.current_cabinet_id = '33100000-0000-0000-0000-000000000001';
SELECT throws_ok(
  $$ UPDATE stock_request SET status = 'accepted'
     WHERE id = '33100000-0000-0000-0000-000000000051' $$,
  '42501', NULL,
  '⭐ WITH CHECK : le cabinet ne peut pas accepter sa propre demande');
RESET app.current_cabinet_id;

-- 5. WITH CHECK : la pharmacie ne forge pas une annulation.
SET LOCAL app.current_pharmacy_id = '33100000-0000-0000-0000-0000000000f1';
SELECT throws_ok(
  $$ UPDATE stock_request SET status = 'cancelled'
     WHERE id = '33100000-0000-0000-0000-000000000051' $$,
  '42501', NULL,
  '⭐ WITH CHECK : la pharmacie ne peut pas annuler la demande');

-- 6. Pas de DELETE pour nubia_app.
SELECT throws_ok(
  $$ DELETE FROM stock_request WHERE id = '33100000-0000-0000-0000-000000000051' $$,
  '42501', NULL,
  '⭐ pas de DELETE sur stock_request pour nubia_app');
RESET app.current_pharmacy_id;

SELECT * FROM finish();
ROLLBACK;
