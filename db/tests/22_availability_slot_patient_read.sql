-- 22_availability_slot_patient_read.sql
-- pgTAP : RLS availability_slot — policy availability_slot_patient_read (issue #2513).
--   PR1. Patient quelconque (sans GUC) voit les créneaux status='available'.
--   PR2. Patient ne voit pas les créneaux status='held' ou 'booked'.
--   PR3. GUC absent (empty) → policy publique, slots 'available' toujours visibles (fail-open).
-- Exécuté par pg_prove sous nubia_app (NOSUPERUSER, NOBYPASSRLS).
-- Fixtures auto-contenues (BEGIN…ROLLBACK). Préfixe UUID 25130000.
-- Issue : #2513

BEGIN;
SELECT plan(3);

-- ===========================================================================
-- Fixtures : 1 cabinet, 1 compte pro, 1 provider, 3 créneaux.
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

-- Créneau 'available' : doit être visible (booking patient).
INSERT INTO availability_slot (id, provider_id, cabinet_id, starts_at, ends_at, status) VALUES
  ('25130000-0000-0000-0000-000000000030',
   '25130000-0000-0000-0000-000000000020',
   '25130000-0000-0000-0000-000000000001',
   now() + interval '1 day',
   now() + interval '1 day' + interval '30 min',
   'available');

-- Créneau 'held' : doit être invisible.
INSERT INTO availability_slot (id, provider_id, cabinet_id, starts_at, ends_at, status) VALUES
  ('25130000-0000-0000-0000-000000000031',
   '25130000-0000-0000-0000-000000000020',
   '25130000-0000-0000-0000-000000000001',
   now() + interval '2 days',
   now() + interval '2 days' + interval '30 min',
   'held');

-- Créneau 'booked' : doit être invisible.
INSERT INTO availability_slot (id, provider_id, cabinet_id, starts_at, ends_at, status) VALUES
  ('25130000-0000-0000-0000-000000000032',
   '25130000-0000-0000-0000-000000000020',
   '25130000-0000-0000-0000-000000000001',
   now() + interval '3 days',
   now() + interval '3 days' + interval '30 min',
   'booked');

-- ===========================================================================
-- PR1. Patient quelconque (sans GUC cabinet) voit le créneau status='available'.
-- ===========================================================================
RESET app.current_cabinet_id;

SELECT is(
  (SELECT count(*)::int FROM availability_slot
   WHERE id = '25130000-0000-0000-0000-000000000030'),
  1,
  '⭐ PR1 availability_slot_patient_read : slot available visible pour tout patient');

-- ===========================================================================
-- PR2. Créneaux status='held' et 'booked' invisibles (policy ne couvre que 'available').
-- ===========================================================================
SELECT is(
  (SELECT count(*)::int FROM availability_slot
   WHERE id IN ('25130000-0000-0000-0000-000000000031',
                '25130000-0000-0000-0000-000000000032')),
  0,
  '⭐ PR2 availability_slot_patient_read : slots held|booked invisibles');

-- ===========================================================================
-- PR3. GUC explicitement absent (empty string) → policy publique, fail-open :
--      slot 'available' toujours visible sans contexte applicatif.
-- ===========================================================================
SELECT set_config('app.current_cabinet_id', '', true);
SELECT set_config('app.patient_account_id', '', true);

SELECT is(
  (SELECT count(*)::int FROM availability_slot
   WHERE id = '25130000-0000-0000-0000-000000000030'),
  1,
  '⭐ PR3 availability_slot_patient_read : visible sans GUC (policy publique, fail-open)');

SELECT * FROM finish();
ROLLBACK;
