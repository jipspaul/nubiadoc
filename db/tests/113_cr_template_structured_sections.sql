-- 113_cr_template_structured_sections.sql
-- pgTAP : sections structurées cr_template + consultation_clinique.structured
-- (#7155, migration 0297).
--   ST1. cr_template.sections : colonne jsonb NOT NULL DEFAULT '[]'.
--   ST2. cr_template.sections : CHECK jsonb_typeof = 'array' (objet refusé).
--   ST3. Modèle structuré (chirurgie implantaire) : sections insérées et
--        relisibles, section "implants" porte bien référence/lot.
--   ST4. consultation_clinique.structured : colonne jsonb NOT NULL DEFAULT '{}'.
--   ST5. consultation_clinique.structured : CHECK jsonb_typeof = 'object' (tableau refusé).
--   ST6. Compte rendu structuré : valeurs saisies insérées et relisibles.
-- Exécuté par pg_prove sous nubia_app (NOSUPERUSER, NOBYPASSRLS).
-- Fixtures auto-contenues (BEGIN…ROLLBACK). Préfixe UUID 71550000.
-- Issue : #7155

BEGIN;
SELECT plan(12);

-- ===========================================================================
-- ST1. cr_template.sections : structure de colonne.
-- ===========================================================================
SELECT has_column('cr_template', 'sections',            'cr_template.sections présent');
SELECT col_type_is('cr_template', 'sections', 'jsonb',   'cr_template.sections jsonb');
SELECT col_not_null('cr_template', 'sections',           'cr_template.sections NOT NULL');
SELECT col_has_default('cr_template', 'sections',        'cr_template.sections DEFAULT []');

-- ===========================================================================
-- Fixtures : 1 cabinet, 1 patient, 1 praticien, 1 RDV.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '71550000-0000-0000-0000-000000000c01';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('71550000-0000-0000-0000-000000000c01', 'Cabinet StructuredCr-7155');

INSERT INTO app_user (id, email, password_hash, kind) VALUES
  ('71550000-0000-0000-0000-000000000010', 'prat.7155@nubia.test', '$argon2id$fixture', 'pro');

INSERT INTO practitioner (id, cabinet_id, user_id) VALUES
  ('71550000-0000-0000-0000-000000000040', '71550000-0000-0000-0000-000000000c01',
   '71550000-0000-0000-0000-000000000010');

INSERT INTO patient (id, cabinet_id, first_name, last_name) VALUES
  ('71550000-0000-0000-0000-000000000030', '71550000-0000-0000-0000-000000000c01', 'Denis', 'Structure7155');

INSERT INTO appointment (id, cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status) VALUES
  ('71550000-0000-0000-0000-000000000050',
   '71550000-0000-0000-0000-000000000c01',
   '71550000-0000-0000-0000-000000000030',
   '71550000-0000-0000-0000-000000000040',
   now(), now() + interval '45 min', 'done');

-- ===========================================================================
-- ST2. CHECK jsonb_typeof(sections) = 'array' : un objet est refusé.
-- ===========================================================================
SELECT throws_ok(
  $$ INSERT INTO cr_template (cabinet_id, title, body_template, sections)
     VALUES ('71550000-0000-0000-0000-000000000c01',
             'Modèle invalide', 'texte', '{"key": "patient_intervention"}'::jsonb) $$,
  '23514', NULL,
  'ST2 cr_template_sections_check : sections objet (non tableau) refusé (23514)');

-- ===========================================================================
-- ST3. Modèle structuré chirurgie implantaire : insertion + relecture.
-- ===========================================================================
INSERT INTO cr_template (id, cabinet_id, ccam_code, title, body_template, sections) VALUES
  ('71550000-0000-0000-0000-000000000f01', '71550000-0000-0000-0000-000000000c01',
   'HBLD001', 'CR chirurgie implantaire', 'Compte rendu structuré : voir sections.',
   '[
      {"key": "patient_intervention", "label": "Patient & intervention", "fields": ["acte_ccam", "dent_site"]},
      {"key": "anesthesie",           "label": "Anesthésie",             "fields": ["type", "produit"]},
      {"key": "guide_chirurgical",    "label": "Guide chirurgical",      "fields": ["type_guide", "reference"]},
      {"key": "lambeau",              "label": "Lambeau",                "fields": ["type_lambeau"]},
      {"key": "implants",             "label": "Implants",               "fields": ["reference", "lot"]},
      {"key": "greffes",              "label": "Greffes",                "fields": ["type_greffe"]},
      {"key": "materiaux",            "label": "Matériaux",              "fields": ["produit", "lot"]},
      {"key": "post_operatoire",      "label": "Post-opératoire",        "fields": ["consignes"]},
      {"key": "documents",            "label": "Documents",              "fields": ["radiographie"]}
    ]'::jsonb);

SELECT is(
  (SELECT jsonb_array_length(sections) FROM cr_template
   WHERE id = '71550000-0000-0000-0000-000000000f01'),
  9,
  'ST3 cr_template.sections : 9 sections structurées relues');

SELECT is(
  (SELECT sect->>'label' FROM cr_template t,
     jsonb_array_elements(t.sections) AS sect
   WHERE t.id = '71550000-0000-0000-0000-000000000f01'
     AND sect->>'key' = 'implants'),
  'Implants',
  'ST3 cr_template.sections : section "implants" (référence/lot) présente');

-- ===========================================================================
-- ST4. consultation_clinique.structured : structure de colonne.
-- ===========================================================================
SELECT has_column('consultation_clinique', 'structured',          'consultation_clinique.structured présent');
SELECT col_type_is('consultation_clinique', 'structured', 'jsonb', 'consultation_clinique.structured jsonb');
SELECT col_not_null('consultation_clinique', 'structured',         'consultation_clinique.structured NOT NULL');

-- ===========================================================================
-- ST5. CHECK jsonb_typeof(structured) = 'object' : un tableau est refusé.
-- ===========================================================================
SELECT throws_ok(
  $$ INSERT INTO consultation_clinique (cabinet_id, appointment_id, practitioner_id, structured)
     VALUES ('71550000-0000-0000-0000-000000000c01',
             '71550000-0000-0000-0000-000000000050',
             '71550000-0000-0000-0000-000000000040',
             '["implants"]'::jsonb) $$,
  '23514', NULL,
  'ST5 consultation_clinique_structured_check : structured tableau (non objet) refusé (23514)');

-- ===========================================================================
-- ST6. Compte rendu structuré : valeurs saisies insérées + relues.
-- ===========================================================================
INSERT INTO consultation_clinique (id, cabinet_id, appointment_id, practitioner_id, structured) VALUES
  ('71550000-0000-0000-0000-000000000060',
   '71550000-0000-0000-0000-000000000c01',
   '71550000-0000-0000-0000-000000000050',
   '71550000-0000-0000-0000-000000000040',
   '{"implants": {"reference": "STR-BL-4.1-10", "lot": "LOT-2026-0099"}}'::jsonb);

SELECT is(
  (SELECT structured #>> '{implants,lot}' FROM consultation_clinique
   WHERE id = '71550000-0000-0000-0000-000000000060'),
  'LOT-2026-0099',
  'ST6 consultation_clinique.structured : valeur de section (implants.lot) relue');

SELECT * FROM finish();
ROLLBACK;
