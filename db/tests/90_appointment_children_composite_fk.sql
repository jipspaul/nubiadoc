-- 90_appointment_children_composite_fk.sql
-- pgTAP : FK composite tenant-scopée groupe "appointment" (parent) —
-- migration 0215, audit #4291.
--   CE1/CE2. checkin_event.appointment_id -> appointment(id, cabinet_id) :
--            légitime OK, exploit cross-cabinet refusé (23503).
--   RM1/RM2. reminder.appointment_id -> appointment(id, cabinet_id) :
--            légitime OK, exploit cross-cabinet refusé (23503).
--   FC. Fail-closed : sans GUC -> 0 ligne visible.
-- Échantillon représentatif (pattern mécanique et identique pour les 3
-- autres tables du lot — consultation_act/consultation_session/
-- consultation_clinique — couvertes structurellement par fk_ok() dans
-- 00_schema.sql / 22_consultation_session.sql).
-- Exécuté par pg_prove sous nubia_app (NOSUPERUSER, NOBYPASSRLS).
-- Fixtures auto-contenues (BEGIN…ROLLBACK). Préfixe UUID 42910005-...
-- Issue : #4291

BEGIN;
SELECT plan(5);

-- ===========================================================================
-- Fixtures : 2 cabinets, chacun avec un patient + un practitioner + un rdv.
-- ===========================================================================
INSERT INTO app_user (id, email, kind, status) VALUES
  ('42910005-0000-0000-0000-0000000000a1', 'praticien-ac-a@demo-42915.test', 'pro', 'active'),
  ('42910005-0000-0000-0000-0000000000a2', 'praticien-ac-b@demo-42915.test', 'pro', 'active');

SET LOCAL app.current_cabinet_id = '42910005-0000-0000-0000-000000000c11';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('42910005-0000-0000-0000-000000000c11', 'Cabinet AC-4291-A');
INSERT INTO patient (id, cabinet_id, first_name, last_name) VALUES
  ('42910005-0000-0000-0000-000000000e11', '42910005-0000-0000-0000-000000000c11',
   'Patient', 'A');
INSERT INTO practitioner (id, cabinet_id, user_id) VALUES
  ('42910005-0000-0000-0000-000000000d11', '42910005-0000-0000-0000-000000000c11',
   '42910005-0000-0000-0000-0000000000a1');
INSERT INTO appointment (id, cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status) VALUES
  ('42910005-0000-0000-0000-000000000f11', '42910005-0000-0000-0000-000000000c11',
   '42910005-0000-0000-0000-000000000e11', '42910005-0000-0000-0000-000000000d11',
   '2026-08-03 09:00+02', '2026-08-03 09:30+02', 'requested');
-- 2e rdv jamais check-in, dédié à l'exploit CE2 : évite que
-- UNIQUE(appointment_id) sur checkin_event masque le rejet FK attendu
-- (23503), piège déjà rencontré sur pharmacy_order / practitioner_favorite_act.
INSERT INTO appointment (id, cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status) VALUES
  ('42910005-0000-0000-0000-000000000f13', '42910005-0000-0000-0000-000000000c11',
   '42910005-0000-0000-0000-000000000e11', '42910005-0000-0000-0000-000000000d11',
   '2026-08-03 11:00+02', '2026-08-03 11:30+02', 'requested');
RESET app.current_cabinet_id;

SET LOCAL app.current_cabinet_id = '42910005-0000-0000-0000-000000000c12';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('42910005-0000-0000-0000-000000000c12', 'Cabinet AC-4291-B');
INSERT INTO patient (id, cabinet_id, first_name, last_name) VALUES
  ('42910005-0000-0000-0000-000000000e12', '42910005-0000-0000-0000-000000000c12',
   'Patient', 'B');
INSERT INTO practitioner (id, cabinet_id, user_id) VALUES
  ('42910005-0000-0000-0000-000000000d12', '42910005-0000-0000-0000-000000000c12',
   '42910005-0000-0000-0000-0000000000a2');
RESET app.current_cabinet_id;

-- ===========================================================================
-- CE1/CE2. checkin_event.appointment_id
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '42910005-0000-0000-0000-000000000c11';
INSERT INTO checkin_event (cabinet_id, appointment_id, mode) VALUES
  ('42910005-0000-0000-0000-000000000c11', '42910005-0000-0000-0000-000000000f11', 'qr_app');
SELECT lives_ok(
  $$ SELECT 1 $$,
  'CE1 checkin_event : fixture légitime cabinet A / rdv A insérée sans erreur');
RESET app.current_cabinet_id;
SET LOCAL app.current_cabinet_id = '42910005-0000-0000-0000-000000000c12';
SELECT throws_ok(
  $$ INSERT INTO checkin_event (cabinet_id, appointment_id, mode)
     VALUES ('42910005-0000-0000-0000-000000000c12',
             '42910005-0000-0000-0000-000000000f13', 'qr_app') $$,
  '23503', NULL,
  '⭐ CE2 checkin_event : rattacher le rdv d''un autre cabinet refusé (23503, RLS FK)');
RESET app.current_cabinet_id;

-- ===========================================================================
-- RM1/RM2. reminder.appointment_id
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '42910005-0000-0000-0000-000000000c11';
INSERT INTO reminder (id, cabinet_id, appointment_id, patient_id, scheduled_at) VALUES
  ('42910005-0000-0000-0000-000000000f21', '42910005-0000-0000-0000-000000000c11',
   '42910005-0000-0000-0000-000000000f11', '42910005-0000-0000-0000-000000000e11',
   '2026-08-02 09:00+02');
SELECT lives_ok(
  $$ SELECT 1 $$,
  'RM1 reminder : fixture légitime cabinet A / rdv A insérée sans erreur');
RESET app.current_cabinet_id;
SET LOCAL app.current_cabinet_id = '42910005-0000-0000-0000-000000000c12';
SELECT throws_ok(
  $$ INSERT INTO reminder (cabinet_id, appointment_id, patient_id, scheduled_at)
     VALUES ('42910005-0000-0000-0000-000000000c12',
             '42910005-0000-0000-0000-000000000f11', '42910005-0000-0000-0000-000000000e12',
             '2026-08-02 09:00+02') $$,
  '23503', NULL,
  '⭐ RM2 reminder : rattacher le rdv d''un autre cabinet refusé (23503, RLS FK)');
RESET app.current_cabinet_id;

-- ===========================================================================
-- FC. Fail-closed : sans GUC -> 0 ligne visible.
-- ===========================================================================
SELECT is(
  (SELECT count(*)::int FROM checkin_event WHERE appointment_id = '42910005-0000-0000-0000-000000000f11')
    + (SELECT count(*)::int FROM reminder WHERE id = '42910005-0000-0000-0000-000000000f21'),
  0,
  '⭐ FC fail-closed : 0 ligne visible (checkin_event/reminder) sans GUC positionné');

SELECT * FROM finish();
ROLLBACK;
