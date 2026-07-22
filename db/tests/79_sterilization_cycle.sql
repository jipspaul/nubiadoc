-- 79_sterilization_cycle.sql
-- pgTAP : sterilization_cycle / sterilized_pouch (#4137, migration 0190).
--   SC1. Cabinet A crée un cycle + une pochette associée à son propre acte.
--   SC2. Associer une pochette à un consultation_act d'un AUTRE cabinet échoue (23503).
--   SC3. test_kind hors énum refusé (CHECK).
--   SC4. RLS sterilization_cycle : cabinet B ne voit PAS le cycle de A.
--   SC5. RLS sterilized_pouch : cabinet B ne voit PAS la pochette de A.
--   SC6. Fail-closed : sans GUC → 0 ligne sur les deux tables.
-- Exécuté par pg_prove sous nubia_app (NOSUPERUSER, NOBYPASSRLS).
-- Fixtures auto-contenues (BEGIN…ROLLBACK). Préfixe UUID 41370000.
-- Issue : #4137

BEGIN;
SELECT plan(6);

-- ===========================================================================
-- Fixtures : 2 cabinets, cabinet A avec patient/practitioner/appointment/acte.
-- ===========================================================================
INSERT INTO app_user (id, email, password_hash, kind) VALUES
  ('41370000-0000-0000-0000-0000000000a1', 'sterilization.4137@nubia.test', '$argon2id$fixture', 'pro');

SET LOCAL app.current_cabinet_id = '41370000-0000-0000-0000-000000000c01';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('41370000-0000-0000-0000-000000000c01', 'Cabinet Sterilization-4137-A');
INSERT INTO patient (id, cabinet_id, first_name, last_name) VALUES
  ('41370000-0000-0000-0000-0000000000e1', '41370000-0000-0000-0000-000000000c01',
   'Patient', 'SterilA');
INSERT INTO practitioner (id, cabinet_id, user_id) VALUES
  ('41370000-0000-0000-0000-0000000000f1', '41370000-0000-0000-0000-000000000c01',
   '41370000-0000-0000-0000-0000000000a1');
INSERT INTO appointment (id, cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status) VALUES
  ('41370000-0000-0000-0000-000000000b01', '41370000-0000-0000-0000-000000000c01',
   '41370000-0000-0000-0000-0000000000e1', '41370000-0000-0000-0000-0000000000f1',
   '2026-01-01 09:00:00+00', '2026-01-01 10:00:00+00', 'in_progress');
INSERT INTO consultation_act
    (id, cabinet_id, appointment_id, patient_id, practitioner_id, ccam_code, label, amount_cents) VALUES
  ('41370000-0000-0000-0000-000000000ac1', '41370000-0000-0000-0000-000000000c01',
   '41370000-0000-0000-0000-000000000b01', '41370000-0000-0000-0000-0000000000e1',
   '41370000-0000-0000-0000-0000000000f1', 'HBLD001', 'Détartrage', 7500);
RESET app.current_cabinet_id;

SET LOCAL app.current_cabinet_id = '41370000-0000-0000-0000-000000000c02';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('41370000-0000-0000-0000-000000000c02', 'Cabinet Sterilization-4137-B');
RESET app.current_cabinet_id;

-- ===========================================================================
-- SC1. Cabinet A crée un cycle + une pochette associée à son propre acte.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '41370000-0000-0000-0000-000000000c01';
INSERT INTO sterilization_cycle
    (id, cabinet_id, autoclave_ref, cycle_number, test_kind, test_result, status) VALUES
  ('41370000-0000-0000-0000-000000000d01', '41370000-0000-0000-0000-000000000c01',
   'Autoclave-1', 42, 'bowie_dick', 'virage complet', 'conforme');
INSERT INTO sterilized_pouch (id, cabinet_id, cycle_id, code, consultation_act_id) VALUES
  ('41370000-0000-0000-0000-000000000701', '41370000-0000-0000-0000-000000000c01',
   '41370000-0000-0000-0000-000000000d01', 'DM-000001',
   '41370000-0000-0000-0000-000000000ac1');
SELECT is(
  (SELECT count(*)::int FROM sterilized_pouch
   WHERE id = '41370000-0000-0000-0000-000000000701'),
  1,
  'SC1 sterilization_cycle/sterilized_pouch : création cabinet A, pochette associée à son acte OK');

-- ===========================================================================
-- SC2. Associer une pochette à un acte d'un AUTRE cabinet échoue (23503) —
-- consultation_act a RLS+FORCE RLS (migration 0042) : la ligne du cabinet A
-- est invisible sous le GUC B, la FK échoue avant toute policy sur pouch.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '41370000-0000-0000-0000-000000000c02';
INSERT INTO sterilization_cycle
    (id, cabinet_id, autoclave_ref, cycle_number, test_kind, test_result, status) VALUES
  ('41370000-0000-0000-0000-000000000d02', '41370000-0000-0000-0000-000000000c02',
   'Autoclave-B', 1, 'helix', 'virage complet', 'conforme');
SELECT throws_ok(
  $$ INSERT INTO sterilized_pouch (cabinet_id, cycle_id, code, consultation_act_id)
     VALUES ('41370000-0000-0000-0000-000000000c02',
             '41370000-0000-0000-0000-000000000d02', 'DM-000002',
             '41370000-0000-0000-0000-000000000ac1') $$,
  '23503', NULL,
  '⭐ SC2 sterilized_pouch : associer un acte d''un autre cabinet refusé (23503, RLS FK)');

-- ===========================================================================
-- SC3. test_kind hors énum refusé (CHECK).
-- ===========================================================================
SELECT throws_ok(
  $$ INSERT INTO sterilization_cycle
       (cabinet_id, autoclave_ref, cycle_number, test_kind, test_result, status)
     VALUES ('41370000-0000-0000-0000-000000000c02',
             'Autoclave-B', 2, 'invalide', 'x', 'conforme') $$,
  '23514', NULL,
  'SC3 sterilization_cycle_test_kind_check : test_kind hors énum refusé (23514)');

-- ===========================================================================
-- SC4. RLS sterilization_cycle : cabinet B ne voit PAS le cycle de A.
-- ===========================================================================
SELECT is(
  (SELECT count(*)::int FROM sterilization_cycle
   WHERE id = '41370000-0000-0000-0000-000000000d01'),
  0,
  '⭐ SC4 tenant_isolation sterilization_cycle : cabinet B ne voit PAS le cycle de A');

-- ===========================================================================
-- SC5. RLS sterilized_pouch : cabinet B ne voit PAS la pochette de A.
-- ===========================================================================
SELECT is(
  (SELECT count(*)::int FROM sterilized_pouch
   WHERE id = '41370000-0000-0000-0000-000000000701'),
  0,
  '⭐ SC5 tenant_isolation sterilized_pouch : cabinet B ne voit PAS la pochette de A');

-- ===========================================================================
-- SC6. Fail-closed : sans GUC → 0 ligne sur les deux tables.
-- ===========================================================================
RESET app.current_cabinet_id;
SELECT is(
  (SELECT count(*)::int FROM sterilization_cycle) +
  (SELECT count(*)::int FROM sterilized_pouch),
  0,
  '⭐ SC6 fail-closed : 0 ligne sans GUC positionné (sterilization_cycle + sterilized_pouch)');

SELECT * FROM finish();
ROLLBACK;
