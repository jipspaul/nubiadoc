-- 93_letter_template_global.sql
-- pgTAP : letter_template — modèles globaux + moteur de courriers (#7197).
-- Vérifie la migration 0267 :
--   LG1. Les 4 courriers types seedés (cabinet_id NULL) sont lisibles par
--        le cabinet A (policy global_template_read)
--   LG2. … et par le cabinet B (tout cabinet, pas un seul)
--   LG3. Un cabinet ne peut PAS modifier un modèle global (0 ligne
--        affectée : la policy tenant_isolation ne couvre pas cabinet_id NULL
--        en UPDATE, global_template_read est SELECT seul)
--   LG4. Un cabinet ne peut PAS créer un modèle global (WITH CHECK
--        tenant_isolation refuse cabinet_id NULL → 42501)
--   LG5. kind = 'attestation' accepté par letter_template_kind_check
--   LG6. document.category = 'courrier' accepté par document_category_check
--   LG7. Le modèle privé du cabinet A reste invisible du cabinet B
--        (l'ouverture globale n'a pas relâché l'isolation tenant)
-- Exécuté par pg_prove sous nubia_app (NOSUPERUSER, NOBYPASSRLS).
-- Fixtures auto-contenues (BEGIN…ROLLBACK). Préfixe UUID 71970000.
-- Issue : #7197

BEGIN;
SELECT plan(7);

-- ===========================================================================
-- Fixtures : 2 cabinets (A, B), 1 patient + 1 modèle privé dans A.
-- ===========================================================================

SET LOCAL app.current_cabinet_id = '71970000-0000-0000-0000-000000000001';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('71970000-0000-0000-0000-000000000001', 'Cabinet Letters-7197-A');
INSERT INTO patient (id, cabinet_id, first_name, last_name) VALUES
  ('71970000-0000-0000-0000-000000000010',
   '71970000-0000-0000-0000-000000000001', 'Léa', 'Courrier');
INSERT INTO letter_template (id, cabinet_id, name, kind, body_template) VALUES
  ('71970000-0000-0000-0000-000000000030',
   '71970000-0000-0000-0000-000000000001',
   'Modèle privé A 7197', 'autre', 'Bonjour {{patient.prenom}}.');

SET LOCAL app.current_cabinet_id = '71970000-0000-0000-0000-000000000002';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('71970000-0000-0000-0000-000000000002', 'Cabinet Letters-7197-B');

-- ===========================================================================
-- LG1/LG2. Les 4 modèles seedés sont lisibles par tout cabinet.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '71970000-0000-0000-0000-000000000001';
SELECT is(
  (SELECT count(*)::int FROM letter_template
   WHERE cabinet_id IS NULL AND id::text LIKE '02670000-%'),
  4,
  'LG1 letter_template : cabinet A voit les 4 courriers types seedés (global_template_read)');

SET LOCAL app.current_cabinet_id = '71970000-0000-0000-0000-000000000002';
SELECT is(
  (SELECT count(*)::int FROM letter_template
   WHERE cabinet_id IS NULL AND id::text LIKE '02670000-%'),
  4,
  'LG2 letter_template : cabinet B voit aussi les 4 courriers types seedés');

-- ===========================================================================
-- LG3. UPDATE d'un modèle global par un cabinet → 0 ligne affectée.
-- ===========================================================================
WITH upd AS (
  UPDATE letter_template SET name = 'Piraté'
  WHERE id = '02670000-0000-0000-0000-000000000001'
  RETURNING id
)
SELECT is((SELECT count(*)::int FROM upd), 0,
  'LG3 letter_template : un cabinet ne peut pas modifier un modèle global (0 ligne)');

-- ===========================================================================
-- LG4. INSERT cabinet_id NULL par un cabinet → refusé (42501).
-- ===========================================================================
SELECT throws_ok(
  $$ INSERT INTO letter_template (cabinet_id, name, kind, body_template)
     VALUES (NULL, 'Faux global', 'autre', 'Corps') $$,
  '42501', NULL,
  'LG4 letter_template : un cabinet ne peut pas créer un modèle global (42501)');

-- ===========================================================================
-- LG5. kind = attestation accepté.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '71970000-0000-0000-0000-000000000001';
SELECT lives_ok(
  $$ INSERT INTO letter_template (cabinet_id, name, kind, body_template)
     VALUES ('71970000-0000-0000-0000-000000000001',
             'Attestation A', 'attestation', 'Je soussigné {{praticien.nom}}.') $$,
  'LG5 letter_template_kind_check : kind attestation accepté');

-- ===========================================================================
-- LG6. document.category = courrier accepté.
-- ===========================================================================
SELECT lives_ok(
  $$ INSERT INTO document (cabinet_id, patient_id, category, storage_key, filename,
                           mime_type, sha256, scan_status, size_bytes)
     VALUES ('71970000-0000-0000-0000-000000000001',
             '71970000-0000-0000-0000-000000000010',
             'courrier', 'courriers/7197.pdf', 'courrier-7197.pdf',
             'application/pdf', repeat('a', 64), 'clean', 42) $$,
  'LG6 document_category_check : catégorie courrier acceptée');

-- ===========================================================================
-- LG7. Isolation tenant intacte : B ne voit pas le modèle privé de A.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '71970000-0000-0000-0000-000000000002';
SELECT is(
  (SELECT count(*)::int FROM letter_template
   WHERE id = '71970000-0000-0000-0000-000000000030'),
  0,
  'LG7 letter_template : cabinet B ne voit pas le modèle privé du cabinet A');

SELECT * FROM finish();
ROLLBACK;
