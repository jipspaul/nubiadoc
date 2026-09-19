-- 100_consent_template_rls.sql
-- pgTAP : RLS consent_template — catalogue global + variantes cabinet
-- (#7200). Vérifie les policies ajoutées par la migration 0279 :
--   CT1. Le catalogue seedé (10 modèles, cabinet_id NULL) est lisible par
--        le cabinet A (policy global_template_read)
--   CT2. … et par le cabinet B (tout cabinet, pas seulement celui qui l'a
--        créé)
--   CT3. Cabinet A voit son propre modèle privé (tenant_isolation)
--   CT4. Cabinet B ne voit PAS le modèle privé du cabinet A (cross-tenant)
--   CT5. Un cabinet ne peut PAS modifier un modèle global (0 ligne
--        affectée : tenant_isolation ne couvre pas cabinet_id NULL en
--        UPDATE, global_template_read est SELECT seul)
--   CT6. Un cabinet ne peut PAS créer un modèle global (WITH CHECK
--        tenant_isolation refuse cabinet_id NULL → 42501)
--   CT7. act_category hors catalogue → rejeté (consent_template_act_
--        category_check)
--   CT8. Fail-closed : sans GUC app.current_cabinet_id positionné → aucun
--        modèle privé visible
-- Exécuté par pg_prove sous nubia_app (NOSUPERUSER, NOBYPASSRLS).
-- Fixtures auto-contenues (BEGIN…ROLLBACK). Préfixe UUID 72000000.
-- Issue : #7200

BEGIN;
SELECT plan(8);

-- ===========================================================================
-- Fixtures : 2 cabinets (A, B), 1 modèle privé pour le cabinet A.
-- ===========================================================================

SET LOCAL app.current_cabinet_id = '72000000-0000-0000-0000-000000000001';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('72000000-0000-0000-0000-000000000001', 'Cabinet ConsentTemplate-7200-A');

SET LOCAL app.current_cabinet_id = '72000000-0000-0000-0000-000000000002';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('72000000-0000-0000-0000-000000000002', 'Cabinet ConsentTemplate-7200-B');

SET LOCAL app.current_cabinet_id = '72000000-0000-0000-0000-000000000001';

INSERT INTO consent_template (id, cabinet_id, act_category, title, body_markdown) VALUES
  ('72000000-0000-0000-0000-000000000010',
   '72000000-0000-0000-0000-000000000001',
   'chirurgie_orale',
   'Modèle privé Cabinet A 7200',
   'Corps du consentement privé.');

-- ===========================================================================
-- CT1/CT2. Le catalogue seedé (10 modèles) est lisible par tout cabinet.
-- ===========================================================================
SELECT is(
  (SELECT count(*)::int FROM consent_template
   WHERE cabinet_id IS NULL AND id::text LIKE '02790000-%'),
  10,
  'CT1 consent_template : cabinet A voit les 10 modèles du catalogue seedé (global_template_read)');

SET LOCAL app.current_cabinet_id = '72000000-0000-0000-0000-000000000002';
SELECT is(
  (SELECT count(*)::int FROM consent_template
   WHERE cabinet_id IS NULL AND id::text LIKE '02790000-%'),
  10,
  'CT2 consent_template : cabinet B voit aussi les 10 modèles du catalogue seedé');

-- ===========================================================================
-- CT3. Cabinet A voit son propre modèle privé.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '72000000-0000-0000-0000-000000000001';
SELECT is(
  (SELECT count(*)::int FROM consent_template
   WHERE id = '72000000-0000-0000-0000-000000000010'),
  1,
  'CT3 consent_template : cabinet A voit son propre modèle privé (tenant_isolation)');

-- ===========================================================================
-- CT4. Cabinet B ne voit PAS le modèle privé du cabinet A (cross-tenant).
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '72000000-0000-0000-0000-000000000002';
SELECT is(
  (SELECT count(*)::int FROM consent_template
   WHERE id = '72000000-0000-0000-0000-000000000010'),
  0,
  'CT4 consent_template : cabinet B ne voit PAS le modèle privé du cabinet A (isolation cross-tenant)');

-- ===========================================================================
-- CT5. UPDATE d'un modèle global par un cabinet → 0 ligne affectée.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '72000000-0000-0000-0000-000000000001';
WITH upd AS (
  UPDATE consent_template SET title = 'Piraté'
  WHERE id = '02790000-0000-0000-0000-000000000001'
  RETURNING id
)
SELECT is((SELECT count(*)::int FROM upd), 0,
  'CT5 consent_template : un cabinet ne peut pas modifier un modèle global (0 ligne)');

-- ===========================================================================
-- CT6. INSERT cabinet_id NULL par un cabinet → refusé (42501).
-- ===========================================================================
SELECT throws_ok(
  $$ INSERT INTO consent_template (cabinet_id, act_category, title, body_markdown)
     VALUES (NULL, 'endodontie', 'Faux global', 'Corps') $$,
  '42501', NULL,
  'CT6 consent_template : un cabinet ne peut pas créer un modèle global (42501)');

-- ===========================================================================
-- CT7. act_category hors catalogue → rejeté.
-- ===========================================================================
SELECT throws_ok(
  $$ INSERT INTO consent_template (cabinet_id, act_category, title, body_markdown)
     VALUES ('72000000-0000-0000-0000-000000000001', 'blanchiment', 'Modèle invalide', 'Corps') $$,
  '23514', NULL,
  'CT7 consent_template_act_category_check : catégorie hors catalogue rejetée');

-- ===========================================================================
-- CT8. Fail-closed sur le modèle privé : sans GUC positionné, invisible.
-- ===========================================================================
RESET app.current_cabinet_id;
SELECT is(
  (SELECT count(*)::int FROM consent_template
   WHERE id = '72000000-0000-0000-0000-000000000010'),
  0,
  'CT8 consent_template : fail-closed, modèle privé invisible sans GUC positionné');

SELECT * FROM finish();
ROLLBACK;
