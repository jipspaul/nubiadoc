-- db/tests/22_availability_slot_patient_read.sql
-- Tests pgTAP : policy RLS availability_slot_patient_read (issue #2513).
-- Exécuté sous nubia_app (NOSUPERUSER, NOBYPASSRLS, FORCE RLS actif).

BEGIN;
SELECT plan(3);

-- Fixtures : cabinet + provider pour les créneaux
SET LOCAL app.current_cabinet_id = 'c0000001-0000-0000-0000-000000002513';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('c0000001-0000-0000-0000-000000002513', 'Cabinet RLS Test 2513');

INSERT INTO app_user (id, email, password_hash, kind) VALUES
  ('u0000001-0000-0000-0000-000000002513', 'pro.rls2513@nubia.test', 'hash', 'pro');

INSERT INTO provider (id, cabinet_id, user_id, display_name, rpps_verified, is_listed) VALUES
  ('p0000001-0000-0000-0000-000000002513',
   'c0000001-0000-0000-0000-000000002513',
   'u0000001-0000-0000-0000-000000002513',
   'Dr RLS 2513', true, true);

-- Créneaux : 1 available, 1 held, 1 booked
INSERT INTO availability_slot (id, provider_id, starts_at, ends_at, motif, status) VALUES
  ('s0000001-0000-0000-0000-000000002513', 'p0000001-0000-0000-0000-000000002513',
   now() + interval '1 day', now() + interval '1 day' + interval '30 min', 'Test', 'available'),
  ('s0000002-0000-0000-0000-000000002513', 'p0000001-0000-0000-0000-000000002513',
   now() + interval '2 days', now() + interval '2 days' + interval '30 min', 'Test', 'held'),
  ('s0000003-0000-0000-0000-000000002513', 'p0000001-0000-0000-0000-000000002513',
   now() + interval '3 days', now() + interval '3 days' + interval '30 min', 'Test', 'booked');

-- Réinitialise le GUC cabinet (lecture publique sans contexte cabinet)
RESET app.current_cabinet_id;

-- Test 1 : patient quelconque voit le créneau status=available
SELECT is(
  (SELECT count(*)::int FROM availability_slot
   WHERE id = 's0000001-0000-0000-0000-000000002513'),
  1,
  'Patient voit le créneau status=available (policy availability_slot_patient_read)'
);

-- Test 2 : ne voit pas status=held ni status=booked
SELECT is(
  (SELECT count(*)::int FROM availability_slot
   WHERE id IN (
     's0000002-0000-0000-0000-000000002513',
     's0000003-0000-0000-0000-000000002513'
   )),
  0,
  'Patient ne voit pas les créneaux status=held et status=booked'
);

-- Test 3 : GUC absent → créneau available toujours visible (policy non fail-closed, publique)
SELECT set_config('app.current_cabinet_id', '', true);
SELECT is(
  (SELECT count(*)::int FROM availability_slot
   WHERE id = 's0000001-0000-0000-0000-000000002513'),
  1,
  'Sans GUC app.current_cabinet_id → créneau available toujours visible (non fail-closed)'
);

SELECT * FROM finish();
ROLLBACK;
