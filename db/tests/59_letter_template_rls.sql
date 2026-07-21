-- 59_letter_template_rls.sql
-- pgTAP : RLS letter_template — isolation cabinet (#4166).
-- Vérifie la policy tenant_isolation ajoutée par la migration 0167 :
--   LT1. Cabinet A voit son propre modèle de courrier
--   LT2. Cabinet B ne voit pas le modèle du cabinet A (cross-tenant)
--   LT3. Fail-closed : sans GUC app.current_cabinet_id positionné → 0 ligne visible
--   LT4. Insertion réussie same-tenant (cabinet A insère et relit son modèle)
--   LT5. kind hors énum refusé par le CHECK letter_template_kind_check
-- Exécuté par pg_prove sous nubia_app (NOSUPERUSER, NOBYPASSRLS).
-- Fixtures auto-contenues (BEGIN…ROLLBACK). Préfixe UUID 41660000.
-- Issue : #4166

BEGIN;
SELECT plan(5);

-- ===========================================================================
-- Fixtures : 2 cabinets (A, B), 1 modèle de courrier dans le cabinet A.
-- ===========================================================================

SET LOCAL app.current_cabinet_id = '41660000-0000-0000-0000-000000000001';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('41660000-0000-0000-0000-000000000001', 'Cabinet LetterTemplate-4166-A');

SET LOCAL app.current_cabinet_id = '41660000-0000-0000-0000-000000000002';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('41660000-0000-0000-0000-000000000002', 'Cabinet LetterTemplate-4166-B');

SET LOCAL app.current_cabinet_id = '41660000-0000-0000-0000-000000000001';

INSERT INTO letter_template (id, cabinet_id, name, kind, body_template) VALUES
  ('41660000-0000-0000-0000-000000000030',
   '41660000-0000-0000-0000-000000000001',
   'Convocation RDV pose prothèse',
   'convocation',
   'Bonjour {{patient.prenom}}, votre RDV de pose est fixé au {{rdv.date}}.');

-- ===========================================================================
-- LT1. Cabinet A voit son propre modèle de courrier.
-- ===========================================================================
SELECT is(
  (SELECT count(*)::int FROM letter_template
   WHERE id = '41660000-0000-0000-0000-000000000030'),
  1,
  'LT1 letter_template : cabinet A voit son propre modèle (tenant_isolation)');

-- ===========================================================================
-- LT2. Cabinet B ne voit pas le modèle du cabinet A (cross-tenant).
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '41660000-0000-0000-0000-000000000002';
SELECT is(
  (SELECT count(*)::int FROM letter_template
   WHERE id = '41660000-0000-0000-0000-000000000030'),
  0,
  'LT2 letter_template : cabinet B ne voit PAS le modèle du cabinet A (isolation cross-tenant)');

-- ===========================================================================
-- LT3. Fail-closed : sans GUC app.current_cabinet_id positionné → 0 ligne visible.
-- ===========================================================================
RESET app.current_cabinet_id;
SELECT is(
  (SELECT count(*)::int FROM letter_template
   WHERE id = '41660000-0000-0000-0000-000000000030'),
  0,
  'LT3 letter_template : fail-closed, 0 ligne visible sans GUC positionné');

-- ===========================================================================
-- LT4. Insertion réussie same-tenant : cabinet A insère et relit un 2e modèle.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '41660000-0000-0000-0000-000000000001';
INSERT INTO letter_template (id, cabinet_id, name, kind, body_template) VALUES
  ('41660000-0000-0000-0000-000000000031',
   '41660000-0000-0000-0000-000000000001',
   'Relance devis impayé',
   'relance',
   'Bonjour {{patient.prenom}}, votre devis du {{devis.date}} reste sans réponse.');
SELECT is(
  (SELECT count(*)::int FROM letter_template
   WHERE id = '41660000-0000-0000-0000-000000000031'),
  1,
  'LT4 letter_template : insertion + relecture same-tenant réussies');

-- ===========================================================================
-- LT5. kind hors énum refusé par le CHECK.
-- ===========================================================================
SELECT throws_ok(
  $$ INSERT INTO letter_template (cabinet_id, name, kind, body_template)
     VALUES ('41660000-0000-0000-0000-000000000001',
             'Modèle invalide',
             'facture',
             'Corps du courrier') $$,
  '23514', NULL,
  'LT5 letter_template_kind_check : kind hors énum refusé (23514)');

SELECT * FROM finish();
ROLLBACK;
