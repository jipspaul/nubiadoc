-- 65_appointment_recurrence.sql
-- pgTAP : recurrence_id/recurrence_index sur appointment (#4087, migration 0173).
--   RC1. Une série de 3 RDV partage le même recurrence_id.
--   RC2. recurrence_index reflète la position 1-based (1, 2, 3).
--   RC3. La contrainte no-overlap (0005) reste active : un RDV qui chevauche
--        un RDV de la série (même praticien) est toujours refusé, série ou pas.
--   RC4. CHECK pairée : recurrence_id sans recurrence_index refusé.
--   RC5. CHECK positive : recurrence_index <= 0 refusé.
-- Exécuté par pg_prove sous nubia_app (NOSUPERUSER, NOBYPASSRLS).
-- Fixtures auto-contenues (BEGIN…ROLLBACK). Préfixe UUID 40870000.
-- Issue : #4087

BEGIN;
SELECT plan(5);

-- ===========================================================================
-- Fixtures : 1 cabinet, 1 praticien, 1 patient, série de 3 RDV.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '40870000-0000-0000-0000-000000000001';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('40870000-0000-0000-0000-000000000001', 'Cabinet AppointmentRecurrence-4087');
INSERT INTO app_user (id, email, password_hash, kind) VALUES
  ('40870000-0000-0000-0000-0000000000a1', 'prat.recurrence@appt.test', '$argon2id$fixture', 'pro');
INSERT INTO practitioner (id, cabinet_id, user_id) VALUES
  ('40870000-0000-0000-0000-0000000000c1', '40870000-0000-0000-0000-000000000001',
   '40870000-0000-0000-0000-0000000000a1');
INSERT INTO patient (id, cabinet_id, first_name, last_name) VALUES
  ('40870000-0000-0000-0000-0000000000d1', '40870000-0000-0000-0000-000000000001',
   'Serge', 'Recurrence');

-- Série de 3 RDV hebdomadaires (parodonto), même recurrence_id, index 1/2/3.
INSERT INTO appointment
  (id, cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status,
   recurrence_id, recurrence_index) VALUES
  ('40870000-0000-0000-0000-0000000000e1', '40870000-0000-0000-0000-000000000001',
   '40870000-0000-0000-0000-0000000000d1', '40870000-0000-0000-0000-0000000000c1',
   '2026-07-06 09:00+00', '2026-07-06 09:30+00', 'confirmed',
   '40870000-0000-0000-0000-0000000000f0', 1),
  ('40870000-0000-0000-0000-0000000000e2', '40870000-0000-0000-0000-000000000001',
   '40870000-0000-0000-0000-0000000000d1', '40870000-0000-0000-0000-0000000000c1',
   '2026-07-13 09:00+00', '2026-07-13 09:30+00', 'confirmed',
   '40870000-0000-0000-0000-0000000000f0', 2),
  ('40870000-0000-0000-0000-0000000000e3', '40870000-0000-0000-0000-000000000001',
   '40870000-0000-0000-0000-0000000000d1', '40870000-0000-0000-0000-0000000000c1',
   '2026-07-20 09:00+00', '2026-07-20 09:30+00', 'confirmed',
   '40870000-0000-0000-0000-0000000000f0', 3);

-- ===========================================================================
-- RC1. Les 3 RDV partagent le même recurrence_id.
-- ===========================================================================
SELECT is(
  (SELECT count(*)::int FROM appointment
   WHERE recurrence_id = '40870000-0000-0000-0000-0000000000f0'),
  3,
  'RC1 appointment : la série de 3 RDV partage le même recurrence_id');

-- ===========================================================================
-- RC2. recurrence_index reflète la position 1-based, dans l'ordre chrono.
-- ===========================================================================
SELECT is(
  (SELECT array_agg(recurrence_index ORDER BY starts_at) FROM appointment
   WHERE recurrence_id = '40870000-0000-0000-0000-0000000000f0'),
  ARRAY[1, 2, 3],
  'RC2 appointment : recurrence_index = 1, 2, 3 dans l''ordre chronologique');

-- ===========================================================================
-- RC3. no-overlap (0005) toujours actif : un RDV chevauchant le 1er de la
-- série (même praticien), même sans lien de série, est refusé.
-- ===========================================================================
SELECT throws_ok(
  $$ INSERT INTO appointment
       (cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status)
     VALUES ('40870000-0000-0000-0000-000000000001',
             '40870000-0000-0000-0000-0000000000d1',
             '40870000-0000-0000-0000-0000000000c1',
             '2026-07-06 09:15+00', '2026-07-06 09:45+00', 'confirmed') $$,
  '23P01', NULL,
  'RC3 appointment_no_overlap : chevauchement praticien toujours refusé (série ou pas)');

-- ===========================================================================
-- RC4. CHECK pairée : recurrence_id sans recurrence_index refusé.
-- ===========================================================================
SELECT throws_ok(
  $$ INSERT INTO appointment
       (cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status,
        recurrence_id, recurrence_index)
     VALUES ('40870000-0000-0000-0000-000000000001',
             '40870000-0000-0000-0000-0000000000d1',
             '40870000-0000-0000-0000-0000000000c1',
             '2026-08-01 09:00+00', '2026-08-01 09:30+00', 'confirmed',
             '40870000-0000-0000-0000-0000000000f1', NULL) $$,
  '23514', NULL,
  'RC4 appointment_recurrence_pair_chk : recurrence_id sans recurrence_index refusé');

-- ===========================================================================
-- RC5. CHECK positive : recurrence_index <= 0 refusé.
-- ===========================================================================
SELECT throws_ok(
  $$ INSERT INTO appointment
       (cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status,
        recurrence_id, recurrence_index)
     VALUES ('40870000-0000-0000-0000-000000000001',
             '40870000-0000-0000-0000-0000000000d1',
             '40870000-0000-0000-0000-0000000000c1',
             '2026-08-08 09:00+00', '2026-08-08 09:30+00', 'confirmed',
             '40870000-0000-0000-0000-0000000000f2', 0) $$,
  '23514', NULL,
  'RC5 appointment_recurrence_index_positive_chk : recurrence_index=0 refusé');

SELECT * FROM finish();
ROLLBACK;
