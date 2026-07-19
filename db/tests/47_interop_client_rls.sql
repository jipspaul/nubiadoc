-- 052_interop_client_rls.sql — Contrat RLS interop_client / interop_client_secret
-- (lot A1, socle auth partenaire OAuth2). Vérifie : fail-closed · isolation
-- cross-cabinet SELECT/INSERT · la RLS de interop_client_secret remonte via
-- jointure sur interop_client (pas de cabinet_id direct, migration 0148) ·
-- les lookups SECURITY DEFINER fonctionnent hors contexte tenant.
-- Exécuté par pg_prove sous nubia_app. Fixtures BEGIN…ROLLBACK. Préfixe 52000000.

BEGIN;
SELECT * FROM no_plan();

-- Fixtures : cabinet A (propriétaire) et cabinet B (témoin cross-tenant).
SET LOCAL app.current_cabinet_id = '52000000-0000-0000-0000-000000000001';
INSERT INTO cabinet (id, raison_sociale)
  VALUES ('52000000-0000-0000-0000-000000000001', 'Cabinet A1-A')
  ON CONFLICT DO NOTHING;
RESET app.current_cabinet_id;

SET LOCAL app.current_cabinet_id = '52000000-0000-0000-0000-000000000002';
INSERT INTO cabinet (id, raison_sociale)
  VALUES ('52000000-0000-0000-0000-000000000002', 'Cabinet A1-B')
  ON CONFLICT DO NOTHING;
RESET app.current_cabinet_id;

SET LOCAL app.current_cabinet_id = '52000000-0000-0000-0000-000000000001';
INSERT INTO interop_client (id, client_id, cabinet_id, display_name, scopes)
  VALUES ('52000000-0000-0000-0000-000000000051',
          'client-a1-test',
          '52000000-0000-0000-0000-000000000001',
          'Cabinet A1-A — PMS externe',
          ARRAY['appointments:read', 'directory:read'])
  ON CONFLICT DO NOTHING;
INSERT INTO interop_client_secret (id, client_id_ref, secret_hash)
  VALUES ('52000000-0000-0000-0000-000000000061',
          '52000000-0000-0000-0000-000000000051',
          '$argon2id$fake-hash-for-test')
  ON CONFLICT DO NOTHING;
RESET app.current_cabinet_id;

-- 1. Fail-closed sans GUC.
SELECT is(
  (SELECT count(*)::int FROM interop_client WHERE id = '52000000-0000-0000-0000-000000000051'),
  0, '⭐ fail-closed : interop_client invisible sans GUC');
SELECT is(
  (SELECT count(*)::int FROM interop_client_secret WHERE id = '52000000-0000-0000-0000-000000000061'),
  0, '⭐ fail-closed : interop_client_secret invisible sans GUC');

-- 2. Isolation cabinet — interop_client.
SET LOCAL app.current_cabinet_id = '52000000-0000-0000-0000-000000000001';
SELECT is(
  (SELECT count(*)::int FROM interop_client WHERE id = '52000000-0000-0000-0000-000000000051'),
  1, 'cabinet propriétaire : voit son interop_client');
RESET app.current_cabinet_id;

SET LOCAL app.current_cabinet_id = '52000000-0000-0000-0000-000000000002';
SELECT is(
  (SELECT count(*)::int FROM interop_client WHERE id = '52000000-0000-0000-0000-000000000051'),
  0, '⭐ non-fuite : un autre cabinet ne voit pas l''interop_client');
RESET app.current_cabinet_id;

-- 3. Isolation cabinet — interop_client_secret (RLS via jointure interop_client).
SET LOCAL app.current_cabinet_id = '52000000-0000-0000-0000-000000000001';
SELECT is(
  (SELECT count(*)::int FROM interop_client_secret WHERE id = '52000000-0000-0000-0000-000000000061'),
  1, 'cabinet propriétaire : voit le secret de son interop_client');
RESET app.current_cabinet_id;

SET LOCAL app.current_cabinet_id = '52000000-0000-0000-0000-000000000002';
SELECT is(
  (SELECT count(*)::int FROM interop_client_secret WHERE id = '52000000-0000-0000-0000-000000000061'),
  0, '⭐ non-fuite : un autre cabinet ne voit pas le secret (jointure)');
SELECT throws_ok(
  $$ INSERT INTO interop_client_secret (id, client_id_ref, secret_hash)
     VALUES ('52000000-0000-0000-0000-000000000062',
             '52000000-0000-0000-0000-000000000051',
             '$argon2id$forged') $$,
  '42501', NULL,
  '⭐ WITH CHECK : impossible de forger un secret pour l''interop_client d''un autre cabinet');
RESET app.current_cabinet_id;

-- 4. WITH CHECK : impossible de créer un interop_client pour un autre cabinet.
SET LOCAL app.current_cabinet_id = '52000000-0000-0000-0000-000000000002';
SELECT throws_ok(
  $$ INSERT INTO interop_client (id, client_id, cabinet_id, display_name, scopes)
     VALUES ('52000000-0000-0000-0000-000000000052',
             'client-a1-forged',
             '52000000-0000-0000-0000-000000000001',
             'Forgé', ARRAY['appointments:read']) $$,
  '42501', NULL,
  '⭐ WITH CHECK : impossible de créer un interop_client pour un autre cabinet');
RESET app.current_cabinet_id;

-- 5. SECURITY DEFINER : lookups fonctionnent hors contexte tenant (aucun GUC).
SELECT is(
  (SELECT cabinet_id FROM interop_client_find_by_client_id('client-a1-test')),
  '52000000-0000-0000-0000-000000000001'::uuid,
  'interop_client_find_by_client_id() résout le cabinet sans GUC (SECURITY DEFINER)');
SELECT is(
  (SELECT count(*)::int FROM interop_client_secret_find_active('52000000-0000-0000-0000-000000000051')),
  1, 'interop_client_secret_find_active() renvoie le secret actif sans GUC (SECURITY DEFINER)');

SELECT * FROM finish();
ROLLBACK;
