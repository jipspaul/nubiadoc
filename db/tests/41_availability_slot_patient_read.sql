-- 41_availability_slot_patient_read.sql
-- pgTAP : policy availability_slot_patient_read (issue #2513 — DB-T031).
-- PR1 slot open visible sans GUC, PR2 slot held invisible, PR3 slot booked invisible.
-- Exécuté par pg_prove sous nubia_app (NOSUPERUSER, NOBYPASSRLS).
-- Fixtures auto-contenues (BEGIN...ROLLBACK). Préfixe UUID 25130000.

BEGIN;
SELECT plan(3);

-- ===========================================================================
-- Fixtures : cabinet + provider + 3 slots (open / held / booked).
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '25130000-0000-0000-0000-000000000001';

INSERT INTO cabinet (id, raison_sociale)
    VALUES ('25130000-0000-0000-0000-000000000001', 'Cabinet Patient Read 2513');

INSERT INTO app_user (id, email, password_hash, kind)
    VALUES ('25130000-0000-0000-0000-0000000000a1',
            'dr.pr2513@nubia.test', '$argon2id$fixture', 'pro');

INSERT INTO provider (id, cabinet_id, user_id, display_name, rpps_verified, is_listed)
    VALUES ('25130000-0000-0000-0000-0000000000e1',
            '25130000-0000-0000-0000-000000000001',
            '25130000-0000-0000-0000-0000000000a1',
            'Dr Patient Read 2513', true, true);

INSERT INTO availability_slot (id, provider_id, cabinet_id, starts_at, ends_at, status)
    VALUES
        ('25130000-0000-0000-0000-0000000000f1',
         '25130000-0000-0000-0000-0000000000e1',
         '25130000-0000-0000-0000-000000000001',
         now() + interval '1 day',
         now() + interval '1 day'  + interval '30 min',
         'open'),
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

-- GUC absent → patient quelconque sans contexte cabinet
RESET app.current_cabinet_id;

-- ===========================================================================
-- PR1. Slot open visible sans GUC (fail-open public : booking marketplace)
-- ===========================================================================
SELECT is(
    (SELECT count(*)::int FROM availability_slot
     WHERE id = '25130000-0000-0000-0000-0000000000f1'),
    1,
    'PR1 patient-read : slot open visible sans GUC (public)');

-- ===========================================================================
-- PR2. Slot held invisible sans GUC
-- ===========================================================================
SELECT is(
    (SELECT count(*)::int FROM availability_slot
     WHERE id = '25130000-0000-0000-0000-0000000000f2'),
    0,
    'PR2 patient-read : slot held invisible (non-public)');

-- ===========================================================================
-- PR3. Slot booked invisible sans GUC
-- ===========================================================================
SELECT is(
    (SELECT count(*)::int FROM availability_slot
     WHERE id = '25130000-0000-0000-0000-0000000000f3'),
    0,
    'PR3 patient-read : slot booked invisible (non-public)');

SELECT finish();
ROLLBACK;
