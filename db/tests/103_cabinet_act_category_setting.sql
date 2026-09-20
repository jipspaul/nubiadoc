-- 103_cabinet_act_category_setting.sql
-- pgTAP : cabinet_act_category_setting — colonne ccam_act.category + RLS (#7187).
-- Vérifie la migration 0283 :
--   AC1. ccam_act.category renseignée (NOT NULL) sur tout le catalogue
--   AC2. ccam_act.category respecte la liste autorisée (CHECK)
--   AC3. Cabinet A voit son propre override de catégorie
--   AC4. Cabinet B ne voit pas l'override du cabinet A (cross-tenant)
--   AC5. Fail-closed : sans GUC app.current_cabinet_id positionné → 0 ligne visible
--   AC6. UNIQUE(cabinet_id, category) : un doublon est refusé
--   AC7. category hors liste autorisée refusée (CHECK)
-- Exécuté par pg_prove sous nubia_app (NOSUPERUSER, NOBYPASSRLS).
-- Fixtures auto-contenues (BEGIN…ROLLBACK). Préfixe UUID 71870000.
-- Issue : #7187

BEGIN;
SELECT plan(7);

-- ===========================================================================
-- AC1/AC2. Catalogue CCAM : category renseignée et valide sur tout le catalogue.
-- ===========================================================================
SELECT is(
  (SELECT count(*)::int FROM ccam_act WHERE category IS NULL),
  0,
  'AC1 ccam_act : aucune ligne du catalogue sans category (backfill 0283 complet)');

SELECT is(
  (SELECT count(*)::int FROM ccam_act WHERE category NOT IN (
     'consultation', 'soins_conservateurs', 'endo', 'paro', 'prothese',
     'ortho', 'chirurgie', 'implanto', 'imagerie', 'atm', 'esthetique',
     'appareillages')),
  0,
  'AC2 ccam_act : toutes les categories appartiennent à la liste autorisée');

-- ===========================================================================
-- Fixtures : 2 cabinets (A, B) avec un override de catégorie chacun.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '71870000-0000-0000-0000-000000000001';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('71870000-0000-0000-0000-000000000001', 'Cabinet Categorie-7187-A');

SET LOCAL app.current_cabinet_id = '71870000-0000-0000-0000-000000000002';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('71870000-0000-0000-0000-000000000002', 'Cabinet Categorie-7187-B');

SET LOCAL app.current_cabinet_id = '71870000-0000-0000-0000-000000000001';
INSERT INTO cabinet_act_category_setting (id, cabinet_id, category, enabled) VALUES
  ('71870000-0000-0000-0000-000000000030',
   '71870000-0000-0000-0000-000000000001', 'chirurgie', false);

-- ===========================================================================
-- AC3. Cabinet A voit son propre override.
-- ===========================================================================
SELECT is(
  (SELECT count(*)::int FROM cabinet_act_category_setting
   WHERE id = '71870000-0000-0000-0000-000000000030'),
  1,
  'AC3 cabinet_act_category_setting : cabinet A voit son propre override (tenant_isolation)');

-- ===========================================================================
-- AC4. Cabinet B ne voit pas l'override du cabinet A (cross-tenant).
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '71870000-0000-0000-0000-000000000002';
SELECT is(
  (SELECT count(*)::int FROM cabinet_act_category_setting
   WHERE id = '71870000-0000-0000-0000-000000000030'),
  0,
  'AC4 cabinet_act_category_setting : cabinet B ne voit PAS l''override du cabinet A (isolation cross-tenant)');

-- ===========================================================================
-- AC5. Fail-closed : sans GUC app.current_cabinet_id positionné → 0 ligne visible.
-- ===========================================================================
RESET app.current_cabinet_id;
SELECT is(
  (SELECT count(*)::int FROM cabinet_act_category_setting
   WHERE id = '71870000-0000-0000-0000-000000000030'),
  0,
  'AC5 cabinet_act_category_setting : fail-closed, 0 ligne visible sans GUC positionné');

-- ===========================================================================
-- AC6. UNIQUE(cabinet_id, category) : un doublon est refusé.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '71870000-0000-0000-0000-000000000001';
SELECT throws_ok(
  $$ INSERT INTO cabinet_act_category_setting (cabinet_id, category, enabled)
     VALUES ('71870000-0000-0000-0000-000000000001', 'chirurgie', true) $$,
  '23505', NULL,
  'AC6 cabinet_act_category_setting_unique : doublon (cabinet, category) refusé (23505)');

-- ===========================================================================
-- AC7. category hors liste autorisée refusée (CHECK).
-- ===========================================================================
SELECT throws_ok(
  $$ INSERT INTO cabinet_act_category_setting (cabinet_id, category, enabled)
     VALUES ('71870000-0000-0000-0000-000000000001', 'inconnu', true) $$,
  '23514', NULL,
  'AC7 cabinet_act_category_setting_category_check : categorie hors liste refusée (23514)');

SELECT * FROM finish();
ROLLBACK;
