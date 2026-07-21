-- 58_prescription_template_rls.sql
-- pgTAP : RLS prescription_template — isolation cabinet + lecture globale
-- permissive (#4073). Vérifie les policies ajoutées par la migration 0166 :
--   PT1. Cabinet A voit son propre modèle privé
--   PT2. Cabinet B ne voit PAS le modèle privé du cabinet A (cross-tenant)
--   PT3. Un modèle seedé (cabinet_id NULL) est lisible par le cabinet A
--   PT4. Un modèle seedé (cabinet_id NULL) est lisible par le cabinet B
--        (tout cabinet, pas seulement celui qui l'a créé)
--   PT5. Fail-closed : sans GUC app.current_cabinet_id positionné →
--        aucun modèle privé visible (seuls les modèles globaux le
--        resteraient via global_template_read, qui ne dépend pas du GUC —
--        vérifié séparément du modèle privé pour ne pas mélanger les deux
--        comportements dans une même assertion)
-- Exécuté par pg_prove sous nubia_app (NOSUPERUSER, NOBYPASSRLS).
-- Fixtures auto-contenues (BEGIN…ROLLBACK). Préfixe UUID 40730000.
-- Issue : #4073

BEGIN;
SELECT plan(5);

-- ===========================================================================
-- Fixtures : 2 cabinets (A, B), 1 modèle privé pour le cabinet A.
-- ===========================================================================

SET LOCAL app.current_cabinet_id = '40730000-0000-0000-0000-000000000001';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('40730000-0000-0000-0000-000000000001', 'Cabinet PrescTemplate-4073-A');

SET LOCAL app.current_cabinet_id = '40730000-0000-0000-0000-000000000002';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('40730000-0000-0000-0000-000000000002', 'Cabinet PrescTemplate-4073-B');

SET LOCAL app.current_cabinet_id = '40730000-0000-0000-0000-000000000001';

INSERT INTO prescription_template (id, cabinet_id, label, items) VALUES
  ('40730000-0000-0000-0000-000000000010',
   '40730000-0000-0000-0000-000000000001',
   'Modèle privé Cabinet A 4073',
   '[]');

-- ===========================================================================
-- PT1. Cabinet A voit son propre modèle privé.
-- ===========================================================================
SELECT is(
  (SELECT count(*)::int FROM prescription_template
   WHERE id = '40730000-0000-0000-0000-000000000010'),
  1,
  'PT1 prescription_template : cabinet A voit son propre modèle privé (tenant_isolation)');

-- ===========================================================================
-- PT2. Cabinet B ne voit PAS le modèle privé du cabinet A (cross-tenant).
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '40730000-0000-0000-0000-000000000002';
SELECT is(
  (SELECT count(*)::int FROM prescription_template
   WHERE id = '40730000-0000-0000-0000-000000000010'),
  0,
  'PT2 prescription_template : cabinet B ne voit PAS le modèle privé du cabinet A (isolation cross-tenant)');

-- ===========================================================================
-- PT3/PT4. Un modèle seedé (cabinet_id NULL) est lisible par tout cabinet.
-- ===========================================================================
SELECT ok(
  (SELECT count(*)::int FROM prescription_template WHERE cabinet_id IS NULL) >= 1,
  'PT3 prescription_template : cabinet B voit au moins un modèle global (seed)');

SET LOCAL app.current_cabinet_id = '40730000-0000-0000-0000-000000000001';
SELECT ok(
  (SELECT count(*)::int FROM prescription_template WHERE cabinet_id IS NULL) >= 1,
  'PT4 prescription_template : cabinet A voit aussi au moins un modèle global (seed)');

-- ===========================================================================
-- PT5. Fail-closed sur le modèle privé : sans GUC positionné, invisible.
-- ===========================================================================
RESET app.current_cabinet_id;
SELECT is(
  (SELECT count(*)::int FROM prescription_template
   WHERE id = '40730000-0000-0000-0000-000000000010'),
  0,
  'PT5 prescription_template : fail-closed, modèle privé invisible sans GUC positionné');

SELECT * FROM finish();
ROLLBACK;
