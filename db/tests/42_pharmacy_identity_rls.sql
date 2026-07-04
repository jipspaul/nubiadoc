-- 42_pharmacy_identity_rls.sql — Contrat RLS tables pharmacy + pharmacy_membership (issue #3306, lot B1).
-- Vérifie : fail-closed · annuaire public is_listed · isolation cross-pharmacie ·
-- cloisonnement vis-à-vis du GUC cabinet · WITH CHECK écriture cross-tenant refusée ·
-- user_pharmacy_memberships() (SECURITY DEFINER) ne retourne que les memberships actifs.
-- Exécuté par pg_prove sous nubia_app (NOSUPERUSER, NOBYPASSRLS).
-- Fixtures auto-containées (BEGIN…ROLLBACK). Préfixe UUID 33060000.

BEGIN;
SELECT * FROM no_plan();

-- ===========================================================================
-- Fixtures : pharmacie A (listée) et pharmacie B (non listée), un user membre
-- actif de A, un user avec membership inactif de B.
-- ===========================================================================
SET LOCAL app.current_pharmacy_id = '33060000-0000-0000-0000-000000000001';
INSERT INTO pharmacy (id, raison_sociale, is_listed)
  VALUES ('33060000-0000-0000-0000-000000000001', 'Pharmacie B1-A', true)
  ON CONFLICT DO NOTHING;

INSERT INTO app_user (id, email, kind, status)
  VALUES ('33060000-0000-0000-0000-0000000000a1', 'pharmacien-a@demo-3306.test', 'pro', 'active')
  ON CONFLICT DO NOTHING;
INSERT INTO app_user (id, email, kind, status)
  VALUES ('33060000-0000-0000-0000-0000000000a2', 'ancien-b@demo-3306.test', 'pro', 'active')
  ON CONFLICT DO NOTHING;

INSERT INTO pharmacy_membership (id, pharmacy_id, user_id, role, active)
  VALUES ('33060000-0000-0000-0000-000000000011',
          '33060000-0000-0000-0000-000000000001',
          '33060000-0000-0000-0000-0000000000a1',
          'pharmacist', true)
  ON CONFLICT DO NOTHING;

SET LOCAL app.current_pharmacy_id = '33060000-0000-0000-0000-000000000002';
INSERT INTO pharmacy (id, raison_sociale, is_listed)
  VALUES ('33060000-0000-0000-0000-000000000002', 'Pharmacie B1-B', false)
  ON CONFLICT DO NOTHING;
INSERT INTO pharmacy_membership (id, pharmacy_id, user_id, role, active)
  VALUES ('33060000-0000-0000-0000-000000000012',
          '33060000-0000-0000-0000-000000000002',
          '33060000-0000-0000-0000-0000000000a2',
          'preparator', false)
  ON CONFLICT DO NOTHING;

-- ===========================================================================
-- 1. ANNUAIRE PUBLIC : sans GUC, seule la pharmacie listée est visible.
-- ===========================================================================
RESET app.current_pharmacy_id;
SELECT is(
  (SELECT count(*)::int FROM pharmacy
   WHERE id = '33060000-0000-0000-0000-000000000001'),
  1,
  'annuaire public : la pharmacie listée est visible sans GUC');
SELECT is(
  (SELECT count(*)::int FROM pharmacy
   WHERE id = '33060000-0000-0000-0000-000000000002'),
  0,
  '⭐ fail-closed : la pharmacie NON listée est invisible sans GUC');

-- ===========================================================================
-- 2. FAIL-CLOSED memberships : sans GUC -> 0 ligne.
-- ===========================================================================
SELECT is(
  (SELECT count(*)::int FROM pharmacy_membership
   WHERE id IN ('33060000-0000-0000-0000-000000000011','33060000-0000-0000-0000-000000000012')),
  0,
  '⭐ fail-closed : aucun membership visible sans app.current_pharmacy_id');

-- ===========================================================================
-- 3. ISOLATION : contexte A -> voit A et ses memberships, pas ceux de B.
-- ===========================================================================
SET LOCAL app.current_pharmacy_id = '33060000-0000-0000-0000-000000000001';
SELECT is(
  (SELECT count(*)::int FROM pharmacy_membership
   WHERE pharmacy_id = '33060000-0000-0000-0000-000000000001'),
  1,
  'contexte A : 1 membership visible');
SELECT is(
  (SELECT count(*)::int FROM pharmacy_membership
   WHERE pharmacy_id = '33060000-0000-0000-0000-000000000002'),
  0,
  '⭐ non-fuite : contexte A ne voit PAS les memberships de B');

-- ===========================================================================
-- 4. CONTEXTE B : la pharmacie B (non listée) se voit elle-même.
-- ===========================================================================
SET LOCAL app.current_pharmacy_id = '33060000-0000-0000-0000-000000000002';
SELECT is(
  (SELECT count(*)::int FROM pharmacy
   WHERE id = '33060000-0000-0000-0000-000000000002'),
  1,
  'contexte B : la pharmacie non listée se voit elle-même');

-- ===========================================================================
-- 5. CLOISONNEMENT : le GUC cabinet n'ouvre PAS le tenant pharmacie.
-- ===========================================================================
RESET app.current_pharmacy_id;
SET LOCAL app.current_cabinet_id = '33060000-0000-0000-0000-000000000001';
SELECT is(
  (SELECT count(*)::int FROM pharmacy
   WHERE id = '33060000-0000-0000-0000-000000000002'),
  0,
  '⭐ cloisonnement : app.current_cabinet_id ne donne aucun accès pharmacie');
RESET app.current_cabinet_id;

-- ===========================================================================
-- 6. WITH CHECK : écritures cross-tenant refusées.
-- ===========================================================================
SET LOCAL app.current_pharmacy_id = '33060000-0000-0000-0000-000000000002';
SELECT throws_ok(
  $$ INSERT INTO pharmacy (id, raison_sociale)
     VALUES ('33060000-0000-0000-0000-000000000003', 'Intrus') $$,
  '42501', NULL,
  '⭐ WITH CHECK : insérer une pharmacie avec un id ≠ GUC refusé');
SELECT throws_ok(
  $$ INSERT INTO pharmacy_membership (pharmacy_id, user_id, role)
     VALUES ('33060000-0000-0000-0000-000000000001',
             '33060000-0000-0000-0000-0000000000a2', 'admin') $$,
  '42501', NULL,
  '⭐ WITH CHECK : insérer un membership pour la pharmacie A depuis contexte B refusé');

-- ===========================================================================
-- 7. user_pharmacy_memberships() : SECURITY DEFINER, memberships actifs seulement.
-- ===========================================================================
RESET app.current_pharmacy_id;
SELECT is(
  (SELECT count(*)::int FROM user_pharmacy_memberships('33060000-0000-0000-0000-0000000000a1')),
  1,
  'user_pharmacy_memberships : retourne le membership actif sans GUC (SECURITY DEFINER)');
SELECT is(
  (SELECT role FROM user_pharmacy_memberships('33060000-0000-0000-0000-0000000000a1')),
  'pharmacist',
  'user_pharmacy_memberships : rôle correct');
SELECT is(
  (SELECT count(*)::int FROM user_pharmacy_memberships('33060000-0000-0000-0000-0000000000a2')),
  0,
  '⭐ user_pharmacy_memberships : membership inactif exclu');

SELECT * FROM finish();
ROLLBACK;
