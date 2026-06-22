-- 41_availability_slot_patient_read.sql
-- pgTAP : RLS availability_slot — policy availability_slot_patient_read (issue #2513).
--   PR1. Patient voit un slot disponible (status='open').
--   PR2. Patient ne voit pas un slot bloqué (status='held') ni réservé (status='booked').
--   PR3. Sans GUC positionné, les slots 'open' restent visibles (lecture publique).
-- Exécuté par pg_prove sous nubia_app (NOSUPERUSER, NOBYPASSRLS).
-- Fixtures auto-contenues (BEGIN…ROLLBACK). Préfixe UUID 25130000.
-- Issue : #2513

BEGIN;
SELECT plan(3);

-- ===========================================================================
-- Fixtures : 1 cabinet, 1 provider, 3 créneaux (open / held / booked).
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '25130000-0000-0000-0000-000000000001';

INSERT INTO cabinet (id, raison_sociale) VALUES
  ('25130000-0000-0000-0000-000000000001', 'Cabinet RLS-2513');

INSERT INTO app_user (id, email, password_hash, kind) VALUES
  ('25130000-0000-0000-0000-000000000010', 'prat.2513@nubia.test', '$argon2id$fixture', 'pro');

INSERT INTO provider (id, cabinet_id, user_id, display_name, rpps_verified, is_listed) VALUES
  ('25130000-0000-0000-0000-000000000020',
   '25130000-0000-0000-0000-000000000001',
   '25130000-0000-0000-0000-000000000010',
   'Dr RLS-2513', true, true);

INSERT INTO availability_slot (id, provider_id, starts_at, ends_at, motif, status, cabinet_id) VALUES
  ('25130000-0000-0000-0000-000000000031',
   '25130000-0000-0000-0000-000000000020',
   now() + interval '1 day', now() + interval '1 day' + interval '30 min',
   'Consultation', 'open',
   '25130000-0000-0000-0000-000000000001'),
  ('25130000-0000-0000-0000-000000000032',
   '25130000-0000-0000-0000-000000000020',
   now() + interval '2 days', now() + interval '2 days' + interval '30 min',
   'Consultation', 'held',
   '25130000-0000-0000-0000-000000000001'),
  ('25130000-0000-0000-0000-000000000033',
   '25130000-0000-0000-0000-000000000020',
   now() + interval '3 days', now() + interval '3 days' + interval '30 min',
   'Consultation', 'booked',
   '25130000-0000-0000-0000-000000000001');

-- ===========================================================================
-- PR1. Patient voit le slot disponible (status='open').
-- ===========================================================================
RESET app.current_cabinet_id;

SELECT is(
  (SELECT count(*)::int FROM availability_slot
   WHERE id = '25130000-0000-0000-0000-000000000031'),
  1,
  '⭐ PR1 availability_slot_patient_read : slot open (disponible) visible');

-- ===========================================================================
-- PR2. Patient ne voit pas les slots held ni booked.
-- ===========================================================================
SELECT is(
  (SELECT count(*)::int FROM availability_slot
   WHERE id IN (
     '25130000-0000-0000-0000-000000000032',
     '25130000-0000-0000-0000-000000000033'
   )),
  0,
  '⭐ PR2 availability_slot_patient_read : slots held et booked invisibles');

-- ===========================================================================
-- PR3. Sans GUC positionné, slot open reste visible (lecture publique).
-- ===========================================================================
RESET app.current_cabinet_id;

SELECT is(
  (SELECT count(*)::int FROM availability_slot
   WHERE id = '25130000-0000-0000-0000-000000000031'
     AND status = 'open'),
  1,
  '⭐ PR3 availability_slot_patient_read : visible sans GUC (public, fail-open)');

SELECT * FROM finish();
ROLLBACK;
