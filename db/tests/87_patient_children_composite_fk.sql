-- 87_patient_children_composite_fk.sql
-- pgTAP : FK composite tenant-scopée <table>.patient_id -> patient(id,
-- cabinet_id) — migration 0212, audit #4291, groupe "patient" (19 tables).
--
-- Vu l'ampleur (19 tables enfants, toutes le même mécanisme mécanique de
-- conversion), ce fichier exerce le comportement (insert légitime + exploit
-- cross-cabinet bloqué) sur un échantillon représentatif de 6 tables
-- couvrant des profils différents : document (patient_id NULLABLE,
-- contrairement aux 18 autres NOT NULL), quote (financier), appointment
-- (planification, la plus utilisée), medical_record (clinique/PII),
-- conversation (messagerie), patient_tag (le plus simple, colonnes
-- additionnelles requises). La couverture structurelle des 13 tables
-- restantes est assurée par les fk_ok() de tests/00_schema.sql (schéma
-- composite vérifié pour les 19), sans dupliquer 19x ce même test
-- comportemental mécanique.
--
-- Exécuté par pg_prove sous nubia_app (NOSUPERUSER, NOBYPASSRLS).
-- Fixtures auto-contenues (BEGIN…ROLLBACK). Préfixe UUID 42910002-...
-- Issue : #4291

BEGIN;
SELECT plan(12);

-- ===========================================================================
-- Fixtures : 2 cabinets, chacun avec un patient. Le patient A sert de cible
-- à l'exploit cross-cabinet depuis le cabinet B.
-- ===========================================================================
INSERT INTO app_user (id, email, kind, status) VALUES
  ('42910002-0000-0000-0000-0000000000a1', 'staff-po3-a@demo-42912.test', 'pro', 'active');

SET LOCAL app.current_cabinet_id = '42910002-0000-0000-0000-000000000c11';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('42910002-0000-0000-0000-000000000c11', 'Cabinet PO3-4291-A');
INSERT INTO patient (id, cabinet_id, first_name, last_name) VALUES
  ('42910002-0000-0000-0000-000000000e11', '42910002-0000-0000-0000-000000000c11',
   'Patient', 'A');
RESET app.current_cabinet_id;

SET LOCAL app.current_cabinet_id = '42910002-0000-0000-0000-000000000c12';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('42910002-0000-0000-0000-000000000c12', 'Cabinet PO3-4291-B');
INSERT INTO patient (id, cabinet_id, first_name, last_name) VALUES
  ('42910002-0000-0000-0000-000000000e12', '42910002-0000-0000-0000-000000000c12',
   'Patient', 'B');
RESET app.current_cabinet_id;

-- ===========================================================================
-- document : cas légitime (cabinet A, patient A) puis exploit (cabinet B
-- référençant patient A).
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '42910002-0000-0000-0000-000000000c11';
INSERT INTO document (cabinet_id, patient_id, category, storage_key, filename, mime_type, sha256)
  VALUES ('42910002-0000-0000-0000-000000000c11', '42910002-0000-0000-0000-000000000e11',
          'radio', 'sk-4291-doc', 'radio.jpg', 'image/jpeg', repeat('0', 64));
SELECT lives_ok(
  $$ SELECT 1 $$,
  'document : fixture légitime cabinet A / patient A insérée sans erreur');
RESET app.current_cabinet_id;
SET LOCAL app.current_cabinet_id = '42910002-0000-0000-0000-000000000c12';
SELECT throws_ok(
  $$ INSERT INTO document (cabinet_id, patient_id, category, storage_key, filename, mime_type, sha256)
     VALUES ('42910002-0000-0000-0000-000000000c12', '42910002-0000-0000-0000-000000000e11',
             'radio', 'sk-4291-doc-b', 'radio-b.jpg', 'image/jpeg', repeat('1', 64)) $$,
  '23503', NULL,
  '⭐ document : rattacher le patient A depuis le cabinet B refusé (23503, RLS FK)');
RESET app.current_cabinet_id;

-- ===========================================================================
-- quote : idem.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '42910002-0000-0000-0000-000000000c11';
INSERT INTO quote (cabinet_id, patient_id) VALUES
  ('42910002-0000-0000-0000-000000000c11', '42910002-0000-0000-0000-000000000e11');
SELECT lives_ok(
  $$ SELECT 1 $$,
  'quote : fixture légitime cabinet A / patient A insérée sans erreur');
RESET app.current_cabinet_id;
SET LOCAL app.current_cabinet_id = '42910002-0000-0000-0000-000000000c12';
SELECT throws_ok(
  $$ INSERT INTO quote (cabinet_id, patient_id)
     VALUES ('42910002-0000-0000-0000-000000000c12', '42910002-0000-0000-0000-000000000e11') $$,
  '23503', NULL,
  '⭐ quote : rattacher le patient A depuis le cabinet B refusé (23503, RLS FK)');
RESET app.current_cabinet_id;

-- ===========================================================================
-- appointment : idem (nécessite un practitioner).
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '42910002-0000-0000-0000-000000000c11';
INSERT INTO practitioner (id, cabinet_id, user_id) VALUES
  ('42910002-0000-0000-0000-000000000d11', '42910002-0000-0000-0000-000000000c11',
   '42910002-0000-0000-0000-0000000000a1');
INSERT INTO appointment (cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status) VALUES
  ('42910002-0000-0000-0000-000000000c11', '42910002-0000-0000-0000-000000000e11',
   '42910002-0000-0000-0000-000000000d11', now(), now() + interval '30 min', 'confirmed');
SELECT lives_ok(
  $$ SELECT 1 $$,
  'appointment : fixture légitime cabinet A / patient A insérée sans erreur');
RESET app.current_cabinet_id;
SET LOCAL app.current_cabinet_id = '42910002-0000-0000-0000-000000000c12';
INSERT INTO practitioner (id, cabinet_id, user_id) VALUES
  ('42910002-0000-0000-0000-000000000d12', '42910002-0000-0000-0000-000000000c12',
   '42910002-0000-0000-0000-0000000000a1');
SELECT throws_ok(
  $$ INSERT INTO appointment (cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status)
     VALUES ('42910002-0000-0000-0000-000000000c12', '42910002-0000-0000-0000-000000000e11',
             '42910002-0000-0000-0000-000000000d12', now(), now() + interval '30 min', 'confirmed') $$,
  '23503', NULL,
  '⭐ appointment : rattacher le patient A depuis le cabinet B refusé (23503, RLS FK)');
RESET app.current_cabinet_id;

-- ===========================================================================
-- medical_record : idem.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '42910002-0000-0000-0000-000000000c11';
INSERT INTO medical_record (cabinet_id, patient_id) VALUES
  ('42910002-0000-0000-0000-000000000c11', '42910002-0000-0000-0000-000000000e11');
SELECT lives_ok(
  $$ SELECT 1 $$,
  'medical_record : fixture légitime cabinet A / patient A insérée sans erreur');
RESET app.current_cabinet_id;
SET LOCAL app.current_cabinet_id = '42910002-0000-0000-0000-000000000c12';
SELECT throws_ok(
  $$ INSERT INTO medical_record (cabinet_id, patient_id)
     VALUES ('42910002-0000-0000-0000-000000000c12', '42910002-0000-0000-0000-000000000e11') $$,
  '23503', NULL,
  '⭐ medical_record : rattacher le patient A depuis le cabinet B refusé (23503, RLS FK)');
RESET app.current_cabinet_id;

-- ===========================================================================
-- conversation : idem.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '42910002-0000-0000-0000-000000000c11';
INSERT INTO conversation (cabinet_id, patient_id) VALUES
  ('42910002-0000-0000-0000-000000000c11', '42910002-0000-0000-0000-000000000e11');
SELECT lives_ok(
  $$ SELECT 1 $$,
  'conversation : fixture légitime cabinet A / patient A insérée sans erreur');
RESET app.current_cabinet_id;
SET LOCAL app.current_cabinet_id = '42910002-0000-0000-0000-000000000c12';
SELECT throws_ok(
  $$ INSERT INTO conversation (cabinet_id, patient_id)
     VALUES ('42910002-0000-0000-0000-000000000c12', '42910002-0000-0000-0000-000000000e11') $$,
  '23503', NULL,
  '⭐ conversation : rattacher le patient A depuis le cabinet B refusé (23503, RLS FK)');
RESET app.current_cabinet_id;

-- ===========================================================================
-- patient_tag : idem (nécessite label + created_by).
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '42910002-0000-0000-0000-000000000c11';
INSERT INTO patient_tag (cabinet_id, patient_id, label, created_by) VALUES
  ('42910002-0000-0000-0000-000000000c11', '42910002-0000-0000-0000-000000000e11',
   'VIP', '42910002-0000-0000-0000-0000000000a1');
SELECT lives_ok(
  $$ SELECT 1 $$,
  'patient_tag : fixture légitime cabinet A / patient A insérée sans erreur');
RESET app.current_cabinet_id;
SET LOCAL app.current_cabinet_id = '42910002-0000-0000-0000-000000000c12';
SELECT throws_ok(
  $$ INSERT INTO patient_tag (cabinet_id, patient_id, label, created_by)
     VALUES ('42910002-0000-0000-0000-000000000c12', '42910002-0000-0000-0000-000000000e11',
             'VIP', '42910002-0000-0000-0000-0000000000a1') $$,
  '23503', NULL,
  '⭐ patient_tag : rattacher le patient A depuis le cabinet B refusé (23503, RLS FK)');
RESET app.current_cabinet_id;

SELECT * FROM finish();
ROLLBACK;
