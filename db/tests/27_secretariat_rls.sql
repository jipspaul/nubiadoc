-- 27_secretariat_rls.sql — Contrat RLS table secretariat (issue #1187 P10).
-- Vérifie : fail-closed · isolation cross-cabinet · WITH CHECK écriture cross-tenant refusée.
-- Exécuté par pg_prove sous nubia_app (NOSUPERUSER, NOBYPASSRLS).
-- Fixtures auto-containées (BEGIN…ROLLBACK). Préfixe UUID 11870000.

BEGIN;
SELECT * FROM no_plan();

-- ===========================================================================
-- Fixtures : deux cabinets A et B, chacun avec 1 secrétariat.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '11870000-0000-0000-0000-000000000001';
INSERT INTO cabinet (id, raison_sociale)
  VALUES ('11870000-0000-0000-0000-000000000001', 'Cabinet P10-A')
  ON CONFLICT DO NOTHING;
INSERT INTO secretariat (id, cabinet_id, name)
  VALUES ('11870000-0000-0000-0000-000000000011', '11870000-0000-0000-0000-000000000001', 'Secrétariat A')
  ON CONFLICT DO NOTHING;

SET LOCAL app.current_cabinet_id = '11870000-0000-0000-0000-000000000002';
INSERT INTO cabinet (id, raison_sociale)
  VALUES ('11870000-0000-0000-0000-000000000002', 'Cabinet P10-B')
  ON CONFLICT DO NOTHING;
INSERT INTO secretariat (id, cabinet_id, name)
  VALUES ('11870000-0000-0000-0000-000000000012', '11870000-0000-0000-0000-000000000002', 'Secrétariat B')
  ON CONFLICT DO NOTHING;

-- ===========================================================================
-- 1. FAIL-CLOSED : sans GUC positionné -> 0 ligne visible.
-- ===========================================================================
RESET app.current_cabinet_id;
SELECT is(
  (SELECT count(*)::int FROM secretariat
   WHERE id IN ('11870000-0000-0000-0000-000000000011','11870000-0000-0000-0000-000000000012')),
  0,
  '⭐ fail-closed : aucun secrétariat visible sans app.current_cabinet_id');

-- ===========================================================================
-- 2. ISOLATION : contexte A -> voit A seulement, pas B.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '11870000-0000-0000-0000-000000000001';
SELECT is(
  (SELECT count(*)::int FROM secretariat
   WHERE cabinet_id = '11870000-0000-0000-0000-000000000001'),
  1,
  'contexte A : 1 secrétariat visible');
SELECT is(
  (SELECT count(*)::int FROM secretariat
   WHERE cabinet_id = '11870000-0000-0000-0000-000000000002'),
  0,
  '⭐ non-fuite : contexte A ne voit PAS le secrétariat de B');

-- ===========================================================================
-- 3. ISOLATION : contexte B -> voit B seulement, pas A.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '11870000-0000-0000-0000-000000000002';
SELECT is(
  (SELECT count(*)::int FROM secretariat
   WHERE cabinet_id = '11870000-0000-0000-0000-000000000002'),
  1,
  'contexte B : 1 secrétariat visible');
SELECT is(
  (SELECT count(*)::int FROM secretariat
   WHERE cabinet_id = '11870000-0000-0000-0000-000000000001'),
  0,
  '⭐ non-fuite : contexte B ne voit PAS le secrétariat de A');

-- ===========================================================================
-- 4. WITH CHECK : écriture dans un AUTRE tenant refusée.
-- ===========================================================================
-- (contexte = B) tenter d'insérer une ligne marquée cabinet A
SELECT throws_ok(
  $$ INSERT INTO secretariat (cabinet_id, name)
     VALUES ('11870000-0000-0000-0000-000000000001', 'Intrus') $$,
  '42501', NULL,
  '⭐ WITH CHECK : insérer dans cabinet A depuis contexte B refusé');

SELECT * FROM finish();
ROLLBACK;
