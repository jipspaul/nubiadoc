-- 48_interop_subscription_rls.sql — Contrat RLS interop_subscription /
-- interop_delivery (lot A7, sync sortante FHIR). Vérifie : fail-closed ·
-- isolation cross-cabinet SELECT sur interop_subscription · la RLS de
-- interop_delivery remonte via jointure sur interop_subscription (pas de
-- cabinet_id direct, migration 0149) · WITH CHECK anti-forgerie sur les deux
-- tables.
-- Exécuté par pg_prove sous nubia_app. Fixtures BEGIN…ROLLBACK. Préfixe 53000000.

BEGIN;
SELECT * FROM no_plan();

-- Fixtures : cabinet A (propriétaire) et cabinet B (témoin cross-tenant).
SET LOCAL app.current_cabinet_id = '53000000-0000-0000-0000-000000000001';
INSERT INTO cabinet (id, raison_sociale)
  VALUES ('53000000-0000-0000-0000-000000000001', 'Cabinet A7-A')
  ON CONFLICT DO NOTHING;
RESET app.current_cabinet_id;

SET LOCAL app.current_cabinet_id = '53000000-0000-0000-0000-000000000002';
INSERT INTO cabinet (id, raison_sociale)
  VALUES ('53000000-0000-0000-0000-000000000002', 'Cabinet A7-B')
  ON CONFLICT DO NOTHING;
RESET app.current_cabinet_id;

SET LOCAL app.current_cabinet_id = '53000000-0000-0000-0000-000000000001';
INSERT INTO interop_subscription (id, cabinet_id, criteria, endpoint_url, secret_hash)
  VALUES ('53000000-0000-0000-0000-000000000051',
          '53000000-0000-0000-0000-000000000001',
          'Appointment',
          'https://partner.example/hook',
          '$argon2id$fake-hash-for-test')
  ON CONFLICT DO NOTHING;
INSERT INTO interop_delivery (id, subscription_id, resource_type, resource_id)
  VALUES ('53000000-0000-0000-0000-000000000061',
          '53000000-0000-0000-0000-000000000051',
          'Appointment',
          '53000000-0000-0000-0000-000000000071')
  ON CONFLICT DO NOTHING;
RESET app.current_cabinet_id;

-- 1. Fail-closed sans GUC.
SELECT is(
  (SELECT count(*)::int FROM interop_subscription WHERE id = '53000000-0000-0000-0000-000000000051'),
  0, '⭐ fail-closed : interop_subscription invisible sans GUC');
SELECT is(
  (SELECT count(*)::int FROM interop_delivery WHERE id = '53000000-0000-0000-0000-000000000061'),
  0, '⭐ fail-closed : interop_delivery invisible sans GUC');

-- 2. Isolation cabinet — interop_subscription.
SET LOCAL app.current_cabinet_id = '53000000-0000-0000-0000-000000000001';
SELECT is(
  (SELECT count(*)::int FROM interop_subscription WHERE id = '53000000-0000-0000-0000-000000000051'),
  1, 'cabinet propriétaire : voit son interop_subscription');
RESET app.current_cabinet_id;

SET LOCAL app.current_cabinet_id = '53000000-0000-0000-0000-000000000002';
SELECT is(
  (SELECT count(*)::int FROM interop_subscription WHERE id = '53000000-0000-0000-0000-000000000051'),
  0, '⭐ non-fuite : un autre cabinet ne voit pas l''interop_subscription');
RESET app.current_cabinet_id;

-- 3. Isolation cabinet — interop_delivery (RLS via jointure interop_subscription).
SET LOCAL app.current_cabinet_id = '53000000-0000-0000-0000-000000000001';
SELECT is(
  (SELECT count(*)::int FROM interop_delivery WHERE id = '53000000-0000-0000-0000-000000000061'),
  1, 'cabinet propriétaire : voit la livraison de son abonnement');
RESET app.current_cabinet_id;

SET LOCAL app.current_cabinet_id = '53000000-0000-0000-0000-000000000002';
SELECT is(
  (SELECT count(*)::int FROM interop_delivery WHERE id = '53000000-0000-0000-0000-000000000061'),
  0, '⭐ non-fuite : un autre cabinet ne voit pas la livraison (jointure)');
SELECT throws_ok(
  $$ INSERT INTO interop_delivery (id, subscription_id, resource_type, resource_id)
     VALUES ('53000000-0000-0000-0000-000000000062',
             '53000000-0000-0000-0000-000000000051',
             'Appointment',
             '53000000-0000-0000-0000-000000000072') $$,
  '42501', NULL,
  '⭐ WITH CHECK : impossible de forger une livraison pour l''abonnement d''un autre cabinet');
RESET app.current_cabinet_id;

-- 4. WITH CHECK : impossible de créer un interop_subscription pour un autre cabinet.
SET LOCAL app.current_cabinet_id = '53000000-0000-0000-0000-000000000002';
SELECT throws_ok(
  $$ INSERT INTO interop_subscription (id, cabinet_id, criteria, endpoint_url, secret_hash)
     VALUES ('53000000-0000-0000-0000-000000000052',
             '53000000-0000-0000-0000-000000000001',
             'Appointment', 'https://forged.example/hook', '$argon2id$forged') $$,
  '42501', NULL,
  '⭐ WITH CHECK : impossible de créer un interop_subscription pour un autre cabinet');
RESET app.current_cabinet_id;

-- 5. status check constraint : une valeur hors ('active','disabled') est rejetée.
SET LOCAL app.current_cabinet_id = '53000000-0000-0000-0000-000000000001';
SELECT throws_ok(
  $$ INSERT INTO interop_subscription (id, cabinet_id, criteria, endpoint_url, secret_hash, status)
     VALUES ('53000000-0000-0000-0000-000000000053',
             '53000000-0000-0000-0000-000000000001',
             'Appointment', 'https://partner.example/hook2', '$argon2id$x', 'bogus') $$,
  '23514', NULL,
  '⭐ CHECK : status invalide rejeté sur interop_subscription');
RESET app.current_cabinet_id;

SELECT * FROM finish();
ROLLBACK;
