-- 93_sterilized_pouch_patient_use.sql
-- pgTAP : usage d'un sachet stérilisé par scan (DP-F13.a #7181, migration
-- 0269) — colonnes patient_id / consultation_id / used_at / used_by sur
-- sterilized_pouch, FK composites tenant-scopées (même pattern anti-
-- RLS-bypass que 0190/0198) et CHECK used_at <=> patient_id.
--   PU1. Cabinet A rattache son sachet à SON patient + SA séance : OK.
--   PU2. Rattacher un sachet à un patient d'un AUTRE cabinet refusé (23503).
--   PU3. Rattacher un sachet à une séance d'un AUTRE cabinet refusé (23503).
--   PU4. used_at sans patient_id refusé (23514, CHECK).
--   PU5. patient_id sans used_at refusé (23514, CHECK).
--   PU6. RLS : cabinet B ne voit pas le sachet utilisé de A.
-- Exécuté par pg_prove sous nubia_app (NOSUPERUSER, NOBYPASSRLS).
-- Fixtures auto-contenues (BEGIN…ROLLBACK). Préfixe UUID 71810000.
-- Issue : #7181

BEGIN;
SELECT plan(6);

-- ===========================================================================
-- Fixtures : 2 cabinets, chacun avec patient + practitioner + rdv + séance ;
-- cabinet A avec un cycle + un sachet.
-- ===========================================================================
INSERT INTO app_user (id, email, password_hash, kind) VALUES
  ('71810000-0000-0000-0000-0000000000a1', 'steril-use-a.7181@nubia.test', '$argon2id$fixture', 'pro'),
  ('71810000-0000-0000-0000-0000000000a2', 'steril-use-b.7181@nubia.test', '$argon2id$fixture', 'pro');

SET LOCAL app.current_cabinet_id = '71810000-0000-0000-0000-000000000c01';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('71810000-0000-0000-0000-000000000c01', 'Cabinet Steril-Use-7181-A');
INSERT INTO patient (id, cabinet_id, first_name, last_name) VALUES
  ('71810000-0000-0000-0000-0000000000e1', '71810000-0000-0000-0000-000000000c01',
   'Patient', 'UseA');
INSERT INTO practitioner (id, cabinet_id, user_id) VALUES
  ('71810000-0000-0000-0000-0000000000f1', '71810000-0000-0000-0000-000000000c01',
   '71810000-0000-0000-0000-0000000000a1');
INSERT INTO appointment (id, cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status) VALUES
  ('71810000-0000-0000-0000-000000000b01', '71810000-0000-0000-0000-000000000c01',
   '71810000-0000-0000-0000-0000000000e1', '71810000-0000-0000-0000-0000000000f1',
   '2026-01-01 09:00:00+00', '2026-01-01 10:00:00+00', 'in_progress');
INSERT INTO consultation_session (id, cabinet_id, appointment_id, practitioner_id) VALUES
  ('71810000-0000-0000-0000-000000000501', '71810000-0000-0000-0000-000000000c01',
   '71810000-0000-0000-0000-000000000b01', '71810000-0000-0000-0000-0000000000f1');
INSERT INTO sterilization_cycle
    (id, cabinet_id, autoclave_ref, cycle_number, test_kind, test_result, status) VALUES
  ('71810000-0000-0000-0000-000000000d01', '71810000-0000-0000-0000-000000000c01',
   'Autoclave-7181', 1, 'bowie_dick', 'virage complet', 'conforme');
INSERT INTO sterilized_pouch (id, cabinet_id, cycle_id, code) VALUES
  ('71810000-0000-0000-0000-000000000701', '71810000-0000-0000-0000-000000000c01',
   '71810000-0000-0000-0000-000000000d01', 'DM-7181-001');
RESET app.current_cabinet_id;

SET LOCAL app.current_cabinet_id = '71810000-0000-0000-0000-000000000c02';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('71810000-0000-0000-0000-000000000c02', 'Cabinet Steril-Use-7181-B');
INSERT INTO patient (id, cabinet_id, first_name, last_name) VALUES
  ('71810000-0000-0000-0000-0000000000e2', '71810000-0000-0000-0000-000000000c02',
   'Patient', 'UseB');
INSERT INTO practitioner (id, cabinet_id, user_id) VALUES
  ('71810000-0000-0000-0000-0000000000f2', '71810000-0000-0000-0000-000000000c02',
   '71810000-0000-0000-0000-0000000000a2');
INSERT INTO appointment (id, cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status) VALUES
  ('71810000-0000-0000-0000-000000000b02', '71810000-0000-0000-0000-000000000c02',
   '71810000-0000-0000-0000-0000000000e2', '71810000-0000-0000-0000-0000000000f2',
   '2026-01-01 09:00:00+00', '2026-01-01 10:00:00+00', 'in_progress');
INSERT INTO consultation_session (id, cabinet_id, appointment_id, practitioner_id) VALUES
  ('71810000-0000-0000-0000-000000000502', '71810000-0000-0000-0000-000000000c02',
   '71810000-0000-0000-0000-000000000b02', '71810000-0000-0000-0000-0000000000f2');
RESET app.current_cabinet_id;

-- ===========================================================================
-- PU1. Cabinet A rattache son sachet à SON patient + SA séance : OK.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '71810000-0000-0000-0000-000000000c01';
UPDATE sterilized_pouch
   SET patient_id = '71810000-0000-0000-0000-0000000000e1',
       consultation_id = '71810000-0000-0000-0000-000000000501',
       used_at = now(),
       used_by = '71810000-0000-0000-0000-0000000000a1'
 WHERE id = '71810000-0000-0000-0000-000000000701';
SELECT is(
  (SELECT count(*)::int FROM sterilized_pouch
   WHERE id = '71810000-0000-0000-0000-000000000701'
     AND patient_id = '71810000-0000-0000-0000-0000000000e1'
     AND consultation_id = '71810000-0000-0000-0000-000000000501'
     AND used_at IS NOT NULL),
  1,
  'PU1 sterilized_pouch : rattachement patient + séance du même cabinet OK');

-- ===========================================================================
-- PU2. Patient d'un AUTRE cabinet refusé (23503, FK composite 0269).
-- ===========================================================================
SELECT throws_ok(
  $$ UPDATE sterilized_pouch
        SET patient_id = '71810000-0000-0000-0000-0000000000e2', consultation_id = NULL
      WHERE id = '71810000-0000-0000-0000-000000000701' $$,
  '23503', NULL,
  '⭐ PU2 sterilized_pouch_patient_id_cabinet_fkey : patient d''un autre cabinet refusé (23503)');

-- ===========================================================================
-- PU3. Séance d'un AUTRE cabinet refusée (23503, FK composite 0269).
-- ===========================================================================
SELECT throws_ok(
  $$ UPDATE sterilized_pouch
        SET consultation_id = '71810000-0000-0000-0000-000000000502'
      WHERE id = '71810000-0000-0000-0000-000000000701' $$,
  '23503', NULL,
  '⭐ PU3 sterilized_pouch_consultation_id_cabinet_fkey : séance d''un autre cabinet refusée (23503)');

-- ===========================================================================
-- PU4/PU5. CHECK used_at <=> patient_id.
-- ===========================================================================
SELECT throws_ok(
  $$ INSERT INTO sterilized_pouch (cabinet_id, cycle_id, code, used_at)
     VALUES ('71810000-0000-0000-0000-000000000c01',
             '71810000-0000-0000-0000-000000000d01', 'DM-7181-002', now()) $$,
  '23514', NULL,
  'PU4 sterilized_pouch_used_at_with_patient_chk : used_at sans patient_id refusé (23514)');
SELECT throws_ok(
  $$ INSERT INTO sterilized_pouch (cabinet_id, cycle_id, code, patient_id)
     VALUES ('71810000-0000-0000-0000-000000000c01',
             '71810000-0000-0000-0000-000000000d01', 'DM-7181-003',
             '71810000-0000-0000-0000-0000000000e1') $$,
  '23514', NULL,
  'PU5 sterilized_pouch_used_at_with_patient_chk : patient_id sans used_at refusé (23514)');

-- ===========================================================================
-- PU6. RLS : cabinet B ne voit pas le sachet utilisé de A.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '71810000-0000-0000-0000-000000000c02';
SELECT is(
  (SELECT count(*)::int FROM sterilized_pouch
   WHERE patient_id = '71810000-0000-0000-0000-0000000000e1'),
  0,
  '⭐ PU6 tenant_isolation sterilized_pouch : cabinet B ne voit PAS le sachet utilisé de A');

SELECT * FROM finish();
ROLLBACK;
