-- 76_cr_template.sql
-- pgTAP : cr_template (#4123, migration 0186).
--   CT1. Un cabinet peut créer un modèle générique (ccam_code NULL).
--   CT2. Un cabinet peut créer un modèle rattaché à un acte CCAM.
--   CT3. RLS tenant : cabinet B ne voit PAS les modèles de A.
--   CT4. Fail-closed : sans GUC app.current_cabinet_id → 0 ligne.
--   CT5. ccam_code doit référencer un code du catalogue ccam_act (FK).
-- Exécuté par pg_prove sous nubia_app (NOSUPERUSER, NOBYPASSRLS).
-- Fixtures auto-contenues (BEGIN…ROLLBACK). Préfixe UUID 41230000.
-- Issue : #4123

BEGIN;
SELECT plan(5);

-- ===========================================================================
-- Fixtures : 2 cabinets.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '41230000-0000-0000-0000-000000000c01';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('41230000-0000-0000-0000-000000000c01', 'Cabinet CrTemplate-4123-A');
RESET app.current_cabinet_id;

SET LOCAL app.current_cabinet_id = '41230000-0000-0000-0000-000000000c02';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('41230000-0000-0000-0000-000000000c02', 'Cabinet CrTemplate-4123-B');
RESET app.current_cabinet_id;

-- ===========================================================================
-- CT1. Le cabinet A crée un modèle générique (ccam_code NULL).
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '41230000-0000-0000-0000-000000000c01';
INSERT INTO cr_template (id, cabinet_id, title, body_template) VALUES
  ('41230000-0000-0000-0000-000000000f01', '41230000-0000-0000-0000-000000000c01',
   'CR standard', 'Compte rendu de séance : {{notes}}');
SELECT is(
  (SELECT count(*)::int FROM cr_template
   WHERE cabinet_id = '41230000-0000-0000-0000-000000000c01' AND ccam_code IS NULL),
  1,
  'CT1 cr_template : modèle générique (ccam_code NULL) créé');

-- ===========================================================================
-- CT2. Le cabinet A crée un modèle rattaché à un acte CCAM.
-- ===========================================================================
INSERT INTO cr_template (id, cabinet_id, ccam_code, title, body_template) VALUES
  ('41230000-0000-0000-0000-000000000f02', '41230000-0000-0000-0000-000000000c01',
   'HBLD001', 'CR pose implant', 'Pose d''implant dentaire {{tooth}} : {{notes}}');
SELECT is(
  (SELECT ccam_code FROM cr_template
   WHERE id = '41230000-0000-0000-0000-000000000f02'),
  'HBLD001',
  'CT2 cr_template : modèle rattaché à un acte CCAM créé');

-- ===========================================================================
-- CT3. RLS : cabinet B ne voit PAS les modèles de A.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '41230000-0000-0000-0000-000000000c02';
SELECT is(
  (SELECT count(*)::int FROM cr_template
   WHERE cabinet_id = '41230000-0000-0000-0000-000000000c01'),
  0,
  '⭐ CT3 tenant_isolation : cabinet B ne voit PAS les modèles de A');

-- ===========================================================================
-- CT4. Fail-closed : sans GUC → 0 ligne visible.
-- ===========================================================================
RESET app.current_cabinet_id;
SELECT is(
  (SELECT count(*)::int FROM cr_template),
  0,
  '⭐ CT4 cr_template : fail-closed, 0 ligne sans GUC positionné');

-- ===========================================================================
-- CT5. ccam_code doit exister dans le catalogue ccam_act (FK).
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '41230000-0000-0000-0000-000000000c01';
SELECT throws_ok(
  $$ INSERT INTO cr_template (cabinet_id, ccam_code, title, body_template)
     VALUES ('41230000-0000-0000-0000-000000000c01',
             'CODE_INEXISTANT', 'Modèle invalide', '{{notes}}') $$,
  '23503', NULL,
  'CT5 cr_template_ccam_code_fkey : code CCAM inexistant refusé (23503)');

SELECT * FROM finish();
ROLLBACK;
