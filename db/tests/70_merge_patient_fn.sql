-- 70_merge_patient_fn.sql
-- pgTAP : merge_patient(source_id, target_id) fusionne deux dossiers
-- doublons (#4101, migration 0178).
--   MP1. Après fusion, les RDV du patient source apparaissent sous le
--        patient cible (spec exacte de l'issue).
--   MP2. Le patient source est marqué deleted_at (spec exacte de l'issue).
--   MP3. dental_chart : si le patient cible a déjà un schéma, celui du
--        patient source n'est PAS écrasé (reste sous le patient source).
--   MP4. waiting_list_entry : le doublon actif (même provider) du patient
--        source est annulé, pas réattribué en double actif.
--   MP5. Cabinets différents refusés (pas de fusion cross-tenant).
-- Exécuté par pg_prove sous nubia_app (NOSUPERUSER, NOBYPASSRLS) —
-- merge_patient est SECURITY DEFINER, donc exécutable malgré la RLS.
-- Fixtures auto-contenues (BEGIN…ROLLBACK). Préfixe UUID 41010000.
-- Issue : #4101

BEGIN;
SELECT plan(6);

-- ===========================================================================
-- Fixtures : cabinet, praticien, patient source + patient cible (doublons),
-- 1 RDV pour le source, un dental_chart pour chacun, une waiting_list_entry
-- active pour chacun (même provider).
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '41010000-0000-0000-0000-000000000001';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('41010000-0000-0000-0000-000000000001', 'Cabinet MergePatient-4101');

INSERT INTO app_user (id, email, password_hash, kind) VALUES
  ('41010000-0000-0000-0000-0000000000a1', 'merge.prat@nubia.test', '$argon2id$fixture', 'pro');
INSERT INTO practitioner (id, cabinet_id, user_id) VALUES
  ('41010000-0000-0000-0000-000000000c01', '41010000-0000-0000-0000-000000000001',
   '41010000-0000-0000-0000-0000000000a1');

INSERT INTO provider (id, cabinet_id, user_id, display_name) VALUES
  ('41010000-0000-0000-0000-000000000f01', '41010000-0000-0000-0000-000000000001',
   '41010000-0000-0000-0000-0000000000a1', 'Dr MergeProvider');

INSERT INTO patient (id, cabinet_id, first_name, last_name) VALUES
  ('41010000-0000-0000-0000-000000000010', '41010000-0000-0000-0000-000000000001', 'Marc', 'Doublon');
INSERT INTO patient (id, cabinet_id, first_name, last_name) VALUES
  ('41010000-0000-0000-0000-000000000011', '41010000-0000-0000-0000-000000000001', 'Marc', 'Doublon');

-- RDV du patient source.
INSERT INTO appointment (id, cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status) VALUES
  ('41010000-0000-0000-0000-000000000020', '41010000-0000-0000-0000-000000000001',
   '41010000-0000-0000-0000-000000000010', '41010000-0000-0000-0000-000000000c01',
   '2026-08-01 09:00+00', '2026-08-01 09:30+00', 'confirmed');

-- dental_chart pour les deux (conflit MP3).
INSERT INTO dental_chart (id, cabinet_id, patient_id) VALUES
  ('41010000-0000-0000-0000-000000000030', '41010000-0000-0000-0000-000000000001',
   '41010000-0000-0000-0000-000000000010');
INSERT INTO dental_chart (id, cabinet_id, patient_id) VALUES
  ('41010000-0000-0000-0000-000000000031', '41010000-0000-0000-0000-000000000001',
   '41010000-0000-0000-0000-000000000011');

-- waiting_list_entry active pour les deux, même provider (conflit MP4).
INSERT INTO waiting_list_entry (id, cabinet_id, patient_id, provider_id, status) VALUES
  ('41010000-0000-0000-0000-000000000040', '41010000-0000-0000-0000-000000000001',
   '41010000-0000-0000-0000-000000000010', '41010000-0000-0000-0000-000000000f01', 'active');
INSERT INTO waiting_list_entry (id, cabinet_id, patient_id, provider_id, status) VALUES
  ('41010000-0000-0000-0000-000000000041', '41010000-0000-0000-0000-000000000001',
   '41010000-0000-0000-0000-000000000011', '41010000-0000-0000-0000-000000000f01', 'active');

RESET app.current_cabinet_id;

-- ===========================================================================
-- Fusion : source = ...010, cible = ...011.
-- ===========================================================================
SELECT merge_patient(
  '41010000-0000-0000-0000-000000000010',
  '41010000-0000-0000-0000-000000000011'
);

SET LOCAL app.current_cabinet_id = '41010000-0000-0000-0000-000000000001';

-- ===========================================================================
-- MP1. Le RDV du patient source apparaît sous le patient cible.
-- ===========================================================================
SELECT is(
  (SELECT patient_id FROM appointment WHERE id = '41010000-0000-0000-0000-000000000020'),
  '41010000-0000-0000-0000-000000000011'::uuid,
  '⭐ MP1 merge_patient : le RDV du patient source apparaît sous le patient cible');

-- ===========================================================================
-- MP2. Le patient source est marqué deleted_at.
-- ===========================================================================
SELECT isnt(
  (SELECT deleted_at FROM patient WHERE id = '41010000-0000-0000-0000-000000000010'),
  NULL,
  '⭐ MP2 merge_patient : le patient source est marqué deleted_at');

-- ===========================================================================
-- MP3. dental_chart : le patient cible garde SON schéma (conflit détecté,
-- celui du source n'est pas réattribué).
-- ===========================================================================
SELECT is(
  (SELECT id FROM dental_chart WHERE patient_id = '41010000-0000-0000-0000-000000000011'),
  '41010000-0000-0000-0000-000000000031'::uuid,
  'MP3a dental_chart : le patient cible garde son propre schéma (pas écrasé)');
SELECT is(
  (SELECT patient_id FROM dental_chart WHERE id = '41010000-0000-0000-0000-000000000030'),
  '41010000-0000-0000-0000-000000000010'::uuid,
  'MP3b dental_chart : celui du patient source reste sous le patient source (pas perdu)');

-- ===========================================================================
-- MP4. waiting_list_entry : le doublon actif du patient source est annulé.
-- ===========================================================================
SELECT is(
  (SELECT status FROM waiting_list_entry WHERE id = '41010000-0000-0000-0000-000000000040'),
  'cancelled',
  'MP4 waiting_list_entry : le doublon actif du patient source est annulé (pas de double actif)');

RESET app.current_cabinet_id;

-- ===========================================================================
-- MP5. Cabinets différents refusés.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '41010000-0000-0000-0000-000000000002';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('41010000-0000-0000-0000-000000000002', 'Cabinet MergePatient-4101-Autre');
INSERT INTO patient (id, cabinet_id, first_name, last_name) VALUES
  ('41010000-0000-0000-0000-000000000012', '41010000-0000-0000-0000-000000000002', 'Autre', 'Cabinet');
RESET app.current_cabinet_id;

SELECT throws_ok(
  $$ SELECT merge_patient(
       '41010000-0000-0000-0000-000000000011',
       '41010000-0000-0000-0000-000000000012'
     ) $$,
  'P0001', NULL,
  '⭐ MP5 merge_patient : cabinets différents refusés (pas de fusion cross-tenant)');

SELECT * FROM finish();
ROLLBACK;
