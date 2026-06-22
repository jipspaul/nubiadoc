-- 22_availability_slot_patient_read.sql — pgTAP : policy availability_slot_patient_read (0116).
-- Issue #2513 — DB-T031.
--
-- Invariants couverts :
--   POL1.  policy availability_slot_patient_read présente (0116).
--   PR1.   patient voit un créneau status='available' sans GUC.
--   PR2.   créneau status='held' invisible.
--   PR3.   créneau status='booked' invisible.
--   PR4.   GUC absent → créneau 'available' toujours visible (policy publique).
--
-- Exécuté par pg_prove sous nubia_app (NOSUPERUSER, NOBYPASSRLS).
-- Fixtures auto-contenues (BEGIN…ROLLBACK). Préfixe UUID 25130000.

BEGIN;
SELECT * FROM no_plan();

-- ===========================================================================
-- Pré-conditions
-- ===========================================================================
SELECT is(current_user::text, 'nubia_app',
    'PRE : exécuté sous nubia_app');

SELECT ok(NOT (SELECT rolbypassrls FROM pg_roles WHERE rolname = 'nubia_app'),
    'PRE nubia_app NOBYPASSRLS confirmé');

-- ===========================================================================
-- POL1. Policy availability_slot_patient_read présente (0116)
-- ===========================================================================
SELECT ok(
    EXISTS(SELECT 1 FROM pg_policies
           WHERE tablename  = 'availability_slot'
             AND policyname = 'availability_slot_patient_read'),
    'POL1 availability_slot : policy availability_slot_patient_read présente (0116)');

-- ===========================================================================
-- Fixtures : 1 cabinet, 1 provider, 3 créneaux (available, held, booked).
-- Préfixe UUID 25130000.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '25130000-0000-0000-0000-000000000001';

INSERT INTO cabinet (id, raison_sociale)
    VALUES ('25130000-0000-0000-0000-000000000001', 'Cabinet PatientRead-T031');

INSERT INTO app_user (id, email, password_hash, kind)
    VALUES ('25130000-0000-0000-0000-0000000000a1',
            'dr.2513@nubia.test', '$argon2id$fixture', 'pro');

INSERT INTO provider (id, cabinet_id, user_id, display_name, rpps_verified, is_listed)
    VALUES ('25130000-0000-0000-0000-0000000000e1',
            '25130000-0000-0000-0000-000000000001',
            '25130000-0000-0000-0000-0000000000a1',
            'Dr PatientRead T031', true, true);

INSERT INTO availability_slot (id, provider_id, cabinet_id, starts_at, ends_at, status)
    VALUES
      ('25130000-0000-0000-0000-0000000000f1',
       '25130000-0000-0000-0000-0000000000e1',
       '25130000-0000-0000-0000-000000000001',
       now() + interval '1 day',
       now() + interval '1 day' + interval '30 min',
       'available'),
      ('25130000-0000-0000-0000-0000000000f2',
       '25130000-0000-0000-0000-0000000000e1',
       '25130000-0000-0000-0000-000000000001',
       now() + interval '2 days',
       now() + interval '2 days' + interval '30 min',
       'held'),
      ('25130000-0000-0000-0000-0000000000f3',
       '25130000-0000-0000-0000-0000000000e1',
       '25130000-0000-0000-0000-000000000001',
       now() + interval '3 days',
       now() + interval '3 days' + interval '30 min',
       'booked');

-- ===========================================================================
-- PR1. Patient voit le créneau status='available' (sans GUC)
-- ===========================================================================
RESET app.current_cabinet_id;

SELECT is(
    (SELECT count(*)::int FROM availability_slot
     WHERE id = '25130000-0000-0000-0000-0000000000f1'),
    1,
    '⭐ PR1 availability_slot_patient_read : créneau available visible (public)');

-- ===========================================================================
-- PR2. Créneau status='held' invisible
-- ===========================================================================
SELECT is(
    (SELECT count(*)::int FROM availability_slot
     WHERE id = '25130000-0000-0000-0000-0000000000f2'),
    0,
    '⭐ PR2 availability_slot_patient_read : créneau held invisible');

-- ===========================================================================
-- PR3. Créneau status='booked' invisible
-- ===========================================================================
SELECT is(
    (SELECT count(*)::int FROM availability_slot
     WHERE id = '25130000-0000-0000-0000-0000000000f3'),
    0,
    '⭐ PR3 availability_slot_patient_read : créneau booked invisible');

-- ===========================================================================
-- PR4. GUC absent → créneau 'available' toujours visible (policy publique)
-- ===========================================================================
SELECT is(
    (SELECT count(*)::int FROM availability_slot
     WHERE id = '25130000-0000-0000-0000-0000000000f1'),
    1,
    '⭐ PR4 GUC absent : créneau available toujours visible (policy publique sans GUC)');

SELECT * FROM finish();
ROLLBACK;
