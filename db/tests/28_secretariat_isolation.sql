-- 28_secretariat_isolation.sql — Contrat RLS provider_secretariat + secretariat_membership (issue #1233 P14).
-- Vérifie : fail-closed · isolation cross-cabinet · WITH CHECK écriture cross-tenant refusée.
-- Exécuté par pg_prove sous nubia_app (NOSUPERUSER, NOBYPASSRLS).
-- Fixtures auto-containées (BEGIN…ROLLBACK). Préfixe UUID 12330000.

BEGIN;
SELECT * FROM no_plan();

-- ===========================================================================
-- Fixtures : deux cabinets A et B, chacun avec 1 secrétariat, 1 provider,
-- 1 liaison provider_secretariat et 1 membre secretariat_membership.
-- ===========================================================================

-- Cabinet A
SET LOCAL app.current_cabinet_id = '12330000-0000-0000-0000-000000000001';
INSERT INTO cabinet (id, raison_sociale)
  VALUES ('12330000-0000-0000-0000-000000000001', 'Cabinet P14-A')
  ON CONFLICT DO NOTHING;

-- Secrétariat A
INSERT INTO secretariat (id, cabinet_id, name)
  VALUES ('12330000-0000-0000-0000-000000000011', '12330000-0000-0000-0000-000000000001', 'Secrétariat A')
  ON CONFLICT DO NOTHING;

-- app_user A (provider + membre)
INSERT INTO app_user (id, email, kind, status)
  VALUES ('12330000-0000-0000-0000-0000000000a1', 'membre-a@demo-1233.test', 'pro', 'active')
  ON CONFLICT DO NOTHING;

-- Provider A (cabinet-scoped, user_id requis)
INSERT INTO provider (id, cabinet_id, user_id, display_name, rpps_verified, is_listed)
  VALUES ('12330000-0000-0000-0000-000000000101', '12330000-0000-0000-0000-000000000001',
          '12330000-0000-0000-0000-0000000000a1', 'Dr A', false, false)
  ON CONFLICT DO NOTHING;

-- Lien provider_secretariat A
INSERT INTO provider_secretariat (id, provider_id, secretariat_id, active)
  VALUES ('12330000-0000-0000-0000-000000001001',
          '12330000-0000-0000-0000-000000000101',
          '12330000-0000-0000-0000-000000000011',
          true)
  ON CONFLICT DO NOTHING;

-- Membre secretariat_membership A
INSERT INTO secretariat_membership (id, cabinet_id, secretariat_id, user_id, role, active)
  VALUES ('12330000-0000-0000-0000-000000002001',
          '12330000-0000-0000-0000-000000000001',
          '12330000-0000-0000-0000-000000000011',
          '12330000-0000-0000-0000-0000000000a1',
          'secretary', true)
  ON CONFLICT DO NOTHING;

-- Cabinet B
SET LOCAL app.current_cabinet_id = '12330000-0000-0000-0000-000000000002';
INSERT INTO cabinet (id, raison_sociale)
  VALUES ('12330000-0000-0000-0000-000000000002', 'Cabinet P14-B')
  ON CONFLICT DO NOTHING;

-- Secrétariat B
INSERT INTO secretariat (id, cabinet_id, name)
  VALUES ('12330000-0000-0000-0000-000000000012', '12330000-0000-0000-0000-000000000002', 'Secrétariat B')
  ON CONFLICT DO NOTHING;

-- app_user B (provider + membre)
INSERT INTO app_user (id, email, kind, status)
  VALUES ('12330000-0000-0000-0000-0000000000a2', 'membre-b@demo-1233.test', 'pro', 'active')
  ON CONFLICT DO NOTHING;

-- Provider B (user_id requis)
INSERT INTO provider (id, cabinet_id, user_id, display_name, rpps_verified, is_listed)
  VALUES ('12330000-0000-0000-0000-000000000102', '12330000-0000-0000-0000-000000000002',
          '12330000-0000-0000-0000-0000000000a2', 'Dr B', false, false)
  ON CONFLICT DO NOTHING;

-- Lien provider_secretariat B
INSERT INTO provider_secretariat (id, provider_id, secretariat_id, active)
  VALUES ('12330000-0000-0000-0000-000000001002',
          '12330000-0000-0000-0000-000000000102',
          '12330000-0000-0000-0000-000000000012',
          true)
  ON CONFLICT DO NOTHING;

-- Membre secretariat_membership B
INSERT INTO secretariat_membership (id, cabinet_id, secretariat_id, user_id, role, active)
  VALUES ('12330000-0000-0000-0000-000000002002',
          '12330000-0000-0000-0000-000000000002',
          '12330000-0000-0000-0000-000000000012',
          '12330000-0000-0000-0000-0000000000a2',
          'secretary', true)
  ON CONFLICT DO NOTHING;

-- ===========================================================================
-- 1. provider_secretariat — FAIL-CLOSED : sans GUC -> 0 ligne visible.
-- ===========================================================================
RESET app.current_cabinet_id;
SELECT is(
  (SELECT count(*)::int FROM provider_secretariat
   WHERE id IN ('12330000-0000-0000-0000-000000001001','12330000-0000-0000-0000-000000001002')),
  0,
  '⭐ provider_secretariat fail-closed : 0 ligne sans app.current_cabinet_id');

-- ===========================================================================
-- 2. provider_secretariat — contexte A -> voit A seulement, pas B.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '12330000-0000-0000-0000-000000000001';
SELECT is(
  (SELECT count(*)::int FROM provider_secretariat
   WHERE id = '12330000-0000-0000-0000-000000001001'),
  1,
  'provider_secretariat contexte A : lien A visible');
SELECT is(
  (SELECT count(*)::int FROM provider_secretariat
   WHERE id = '12330000-0000-0000-0000-000000001002'),
  0,
  '⭐ provider_secretariat non-fuite : contexte A ne voit PAS le lien de B');

-- ===========================================================================
-- 3. provider_secretariat — contexte B -> voit B seulement, pas A.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '12330000-0000-0000-0000-000000000002';
SELECT is(
  (SELECT count(*)::int FROM provider_secretariat
   WHERE id = '12330000-0000-0000-0000-000000001002'),
  1,
  'provider_secretariat contexte B : lien B visible');
SELECT is(
  (SELECT count(*)::int FROM provider_secretariat
   WHERE id = '12330000-0000-0000-0000-000000001001'),
  0,
  '⭐ provider_secretariat non-fuite : contexte B ne voit PAS le lien de A');

-- ===========================================================================
-- 4. provider_secretariat — WITH CHECK : écriture dans un autre tenant refusée.
-- ===========================================================================
-- (contexte = B) tenter de lier le provider B au secrétariat A (autre cabinet)
SELECT throws_ok(
  $$ INSERT INTO provider_secretariat (provider_id, secretariat_id, active)
     VALUES ('12330000-0000-0000-0000-000000000102',
             '12330000-0000-0000-0000-000000000011',
             true) $$,
  '42501', NULL,
  '⭐ provider_secretariat WITH CHECK : lien vers secrétariat d''un autre cabinet refusé');

-- ===========================================================================
-- 5. secretariat_membership — FAIL-CLOSED : sans GUC -> 0 ligne visible.
-- ===========================================================================
RESET app.current_cabinet_id;
SELECT is(
  (SELECT count(*)::int FROM secretariat_membership
   WHERE id IN ('12330000-0000-0000-0000-000000002001','12330000-0000-0000-0000-000000002002')),
  0,
  '⭐ secretariat_membership fail-closed : 0 ligne sans app.current_cabinet_id');

-- ===========================================================================
-- 6. secretariat_membership — contexte A -> voit A seulement, pas B.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '12330000-0000-0000-0000-000000000001';
SELECT is(
  (SELECT count(*)::int FROM secretariat_membership
   WHERE id = '12330000-0000-0000-0000-000000002001'),
  1,
  'secretariat_membership contexte A : membre A visible');
SELECT is(
  (SELECT count(*)::int FROM secretariat_membership
   WHERE id = '12330000-0000-0000-0000-000000002002'),
  0,
  '⭐ secretariat_membership non-fuite : contexte A ne voit PAS le membre de B');

-- ===========================================================================
-- 7. secretariat_membership — contexte B -> voit B seulement, pas A.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '12330000-0000-0000-0000-000000000002';
SELECT is(
  (SELECT count(*)::int FROM secretariat_membership
   WHERE id = '12330000-0000-0000-0000-000000002002'),
  1,
  'secretariat_membership contexte B : membre B visible');
SELECT is(
  (SELECT count(*)::int FROM secretariat_membership
   WHERE id = '12330000-0000-0000-0000-000000002001'),
  0,
  '⭐ secretariat_membership non-fuite : contexte B ne voit PAS le membre de A');

-- ===========================================================================
-- 8. secretariat_membership — WITH CHECK : écriture dans un autre tenant refusée.
-- ===========================================================================
-- (contexte = B) tenter d'insérer un membre avec cabinet_id = A
SELECT throws_ok(
  $$ INSERT INTO secretariat_membership (cabinet_id, secretariat_id, user_id, role)
     VALUES ('12330000-0000-0000-0000-000000000001',
             '12330000-0000-0000-0000-000000000011',
             '12330000-0000-0000-0000-0000000000a2',
             'secretary') $$,
  '42501', NULL,
  '⭐ secretariat_membership WITH CHECK : insérer dans cabinet A depuis contexte B refusé');

SELECT * FROM finish();
ROLLBACK;
