-- 22_availability_slot_patient_read.sql — RLS patient-read availability_slot (issue #2513).
-- pgTAP. Exécuté par pg_prove sous nubia_app. Réf. migration 0116.
--   T1. status=open → visible en lecture publique (GUC absent).
--   T2. status=held → invisible.
--   T3. status=booked → invisible.
-- Préfixe UUID : 25130000.
BEGIN;
SELECT plan(3);

-- ===========================================================================
-- Fixtures : 1 cabinet, 1 provider, 3 créneaux statuts variés.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '25130000-0000-0000-0000-000000000001';

INSERT INTO cabinet (id, raison_sociale) VALUES
  ('25130000-0000-0000-0000-000000000001', 'Cabinet RLS-2513');

INSERT INTO app_user (id, email, password_hash, kind) VALUES
  ('25130000-0000-0000-0000-000000000010', 'provider.2513@nubia.test', '$argon2id$fixture', 'pro');

INSERT INTO provider (id, cabinet_id, user_id, display_name, rpps_verified, is_listed) VALUES
  ('25130000-0000-0000-0000-000000000020',
   '25130000-0000-0000-0000-000000000001',
   '25130000-0000-0000-0000-000000000010',
   'Dr RLS-2513', true, true);

-- 3 créneaux : 1 open (disponible pour booking), 1 held, 1 booked.
INSERT INTO availability_slot (id, provider_id, starts_at, ends_at, status) VALUES
  ('25130000-0000-0000-0000-000000000030',
   '25130000-0000-0000-0000-000000000020',
   now() + interval '1 day', now() + interval '1 day' + interval '30 min', 'open'),
  ('25130000-0000-0000-0000-000000000031',
   '25130000-0000-0000-0000-000000000020',
   now() + interval '2 days', now() + interval '2 days' + interval '30 min', 'held'),
  ('25130000-0000-0000-0000-000000000032',
   '25130000-0000-0000-0000-000000000020',
   now() + interval '3 days', now() + interval '3 days' + interval '30 min', 'booked');

-- GUC absent → lecture publique (aucun contexte cabinet).
RESET app.current_cabinet_id;

-- ===========================================================================
-- T1. status=open → visible sans GUC (policy availability_slot_patient_read).
-- ===========================================================================
SELECT is(
  (SELECT count(*)::int FROM availability_slot
   WHERE id = '25130000-0000-0000-0000-000000000030'),
  1,
  'T1 créneau open visible en lecture publique (GUC absent)');

-- ===========================================================================
-- T2. status=held → invisible.
-- ===========================================================================
SELECT is(
  (SELECT count(*)::int FROM availability_slot
   WHERE id = '25130000-0000-0000-0000-000000000031'),
  0,
  'T2 créneau held invisible (non public)');

-- ===========================================================================
-- T3. status=booked → invisible.
-- ===========================================================================
SELECT is(
  (SELECT count(*)::int FROM availability_slot
   WHERE id = '25130000-0000-0000-0000-000000000032'),
  0,
  'T3 créneau booked invisible (non public)');

SELECT finish();
ROLLBACK;
