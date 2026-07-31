-- 89_practitioner_children_composite_fk.sql
-- pgTAP : FK composite tenant-scopée groupe "practitioner" (parent) —
-- migration 0214, audit #4291.
--   AP1/AP2. appointment.practitioner_id -> practitioner(id, cabinet_id) :
--            légitime OK, exploit cross-cabinet refusé (23503).
--   PR1/PR2. prescription.practitioner_id -> practitioner(id, cabinet_id) :
--            légitime OK, exploit cross-cabinet refusé (23503).
--   FA1/FA2. practitioner_favorite_act.practitioner_id ->
--            practitioner(id, cabinet_id) : légitime OK, exploit cross-cabinet
--            refusé (23503).
--   FC. Fail-closed : sans GUC -> 0 ligne visible.
-- Échantillon représentatif (pattern mécanique et identique pour les 4 autres
-- tables du lot — treatment_plan/consultation_act/consultation_session/
-- consultation_clinique/prescription_template — couvertes structurellement
-- par fk_ok() dans 00_schema.sql / 22_consultation_session.sql).
-- Exécuté par pg_prove sous nubia_app (NOSUPERUSER, NOBYPASSRLS).
-- Fixtures auto-contenues (BEGIN…ROLLBACK). Préfixe UUID 42910004-...
-- Issue : #4291

BEGIN;
SELECT plan(7);

-- ===========================================================================
-- Fixtures : 2 cabinets, chacun avec un patient + un practitioner.
-- ===========================================================================
INSERT INTO app_user (id, email, kind, status) VALUES
  ('42910004-0000-0000-0000-0000000000a1', 'praticien-pc-a@demo-42914.test', 'pro', 'active'),
  ('42910004-0000-0000-0000-0000000000a2', 'praticien-pc-b@demo-42914.test', 'pro', 'active');

SET LOCAL app.current_cabinet_id = '42910004-0000-0000-0000-000000000c11';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('42910004-0000-0000-0000-000000000c11', 'Cabinet PC-4291-A');
INSERT INTO patient (id, cabinet_id, first_name, last_name) VALUES
  ('42910004-0000-0000-0000-000000000e11', '42910004-0000-0000-0000-000000000c11',
   'Patient', 'A');
INSERT INTO practitioner (id, cabinet_id, user_id) VALUES
  ('42910004-0000-0000-0000-000000000d11', '42910004-0000-0000-0000-000000000c11',
   '42910004-0000-0000-0000-0000000000a1');
RESET app.current_cabinet_id;

SET LOCAL app.current_cabinet_id = '42910004-0000-0000-0000-000000000c12';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('42910004-0000-0000-0000-000000000c12', 'Cabinet PC-4291-B');
INSERT INTO patient (id, cabinet_id, first_name, last_name) VALUES
  ('42910004-0000-0000-0000-000000000e12', '42910004-0000-0000-0000-000000000c12',
   'Patient', 'B');
INSERT INTO practitioner (id, cabinet_id, user_id) VALUES
  ('42910004-0000-0000-0000-000000000d12', '42910004-0000-0000-0000-000000000c12',
   '42910004-0000-0000-0000-0000000000a2');
RESET app.current_cabinet_id;

-- ===========================================================================
-- AP1/AP2. appointment.practitioner_id
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '42910004-0000-0000-0000-000000000c11';
INSERT INTO appointment (id, cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status) VALUES
  ('42910004-0000-0000-0000-000000000f11', '42910004-0000-0000-0000-000000000c11',
   '42910004-0000-0000-0000-000000000e11', '42910004-0000-0000-0000-000000000d11',
   '2026-08-03 09:00+02', '2026-08-03 09:30+02', 'requested');
SELECT lives_ok(
  $$ SELECT 1 $$,
  'AP1 appointment : fixture légitime cabinet A / practitioner A insérée sans erreur');
RESET app.current_cabinet_id;
SET LOCAL app.current_cabinet_id = '42910004-0000-0000-0000-000000000c12';
SELECT throws_ok(
  $$ INSERT INTO appointment (cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status)
     VALUES ('42910004-0000-0000-0000-000000000c12',
             '42910004-0000-0000-0000-000000000e12', '42910004-0000-0000-0000-000000000d11',
             '2026-08-03 10:00+02', '2026-08-03 10:30+02', 'requested') $$,
  '23503', NULL,
  '⭐ AP2 appointment : rattacher le practitioner d''un autre cabinet refusé (23503, RLS FK)');
RESET app.current_cabinet_id;

-- ===========================================================================
-- PR1/PR2. prescription.practitioner_id
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '42910004-0000-0000-0000-000000000c11';
INSERT INTO prescription (id, cabinet_id, patient_id, practitioner_id, status) VALUES
  ('42910004-0000-0000-0000-000000000f21', '42910004-0000-0000-0000-000000000c11',
   '42910004-0000-0000-0000-000000000e11', '42910004-0000-0000-0000-000000000d11', 'draft');
SELECT lives_ok(
  $$ SELECT 1 $$,
  'PR1 prescription : fixture légitime cabinet A / practitioner A insérée sans erreur');
RESET app.current_cabinet_id;
SET LOCAL app.current_cabinet_id = '42910004-0000-0000-0000-000000000c12';
SELECT throws_ok(
  $$ INSERT INTO prescription (cabinet_id, patient_id, practitioner_id, status)
     VALUES ('42910004-0000-0000-0000-000000000c12',
             '42910004-0000-0000-0000-000000000e12', '42910004-0000-0000-0000-000000000d11',
             'draft') $$,
  '23503', NULL,
  '⭐ PR2 prescription : rattacher le practitioner d''un autre cabinet refusé (23503, RLS FK)');
RESET app.current_cabinet_id;

-- ===========================================================================
-- FA1/FA2. practitioner_favorite_act.practitioner_id
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '42910004-0000-0000-0000-000000000c11';
INSERT INTO practitioner_favorite_act (id, practitioner_id, cabinet_id, ccam_code, position) VALUES
  ('42910004-0000-0000-0000-000000000f31', '42910004-0000-0000-0000-000000000d11',
   '42910004-0000-0000-0000-000000000c11', 'HBQK002', 1);
SELECT lives_ok(
  $$ SELECT 1 $$,
  'FA1 practitioner_favorite_act : fixture légitime cabinet A / practitioner A insérée sans erreur');
RESET app.current_cabinet_id;
SET LOCAL app.current_cabinet_id = '42910004-0000-0000-0000-000000000c12';
-- ccam_code différent de FA1 (HBGD036 vs HBQK002) : évite que
-- UNIQUE(practitioner_id, ccam_code) masque le rejet FK attendu (23503),
-- piège déjà rencontré sur pharmacy_order (cf. 85_pharmacy_order_composite_fk.sql).
SELECT throws_ok(
  $$ INSERT INTO practitioner_favorite_act (practitioner_id, cabinet_id, ccam_code, position)
     VALUES ('42910004-0000-0000-0000-000000000d11',
             '42910004-0000-0000-0000-000000000c12', 'HBGD036', 1) $$,
  '23503', NULL,
  '⭐ FA2 practitioner_favorite_act : rattacher le practitioner d''un autre cabinet refusé (23503, RLS FK)');
RESET app.current_cabinet_id;

-- ===========================================================================
-- FC. Fail-closed : sans GUC -> 0 ligne visible.
-- ===========================================================================
SELECT is(
  (SELECT count(*)::int FROM appointment WHERE id = '42910004-0000-0000-0000-000000000f11')
    + (SELECT count(*)::int FROM prescription WHERE id = '42910004-0000-0000-0000-000000000f21')
    + (SELECT count(*)::int FROM practitioner_favorite_act WHERE id = '42910004-0000-0000-0000-000000000f31'),
  0,
  '⭐ FC fail-closed : 0 ligne visible (appointment/prescription/practitioner_favorite_act) sans GUC positionné');

SELECT * FROM finish();
ROLLBACK;
