-- 20_consultation_clinique_patient_read.sql
-- pgTAP : RLS consultation_clinique — policy patient-read (DB-T028).
--   CC1. Patient titulaire (Alice) voit son compte rendu.
--   CC2. Autre patient (Bob) voit 0 ligne (isolation inter-patient).
--   CC3. Sans GUC (fail-closed) : 0 ligne visible.
-- Exécuté par pg_prove sous nubia_app (NOSUPERUSER, NOBYPASSRLS).
-- Fixtures auto-contenues (BEGIN…ROLLBACK). Préfixe UUID 24720000.
-- Issue : #2472

BEGIN;
SELECT plan(3);

-- ===========================================================================
-- Fixtures : 1 cabinet, 2 patients avec comptes plateforme,
-- 1 praticien, 2 RDV, 1 compte rendu (pour Alice).
-- ===========================================================================

SET LOCAL app.current_cabinet_id = '24720000-0000-0000-0000-000000000001';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('24720000-0000-0000-0000-000000000001', 'Cabinet RLS-2472');

INSERT INTO app_user (id, email, password_hash, kind) VALUES
  ('24720000-0000-0000-0000-000000000010', 'prat.2472@nubia.test',  '$argon2id$fixture', 'pro'),
  ('24720000-0000-0000-0000-000000000011', 'alice.2472@nubia.test', '$argon2id$fixture', 'patient'),
  ('24720000-0000-0000-0000-000000000012', 'bob.2472@nubia.test',   '$argon2id$fixture', 'patient');

INSERT INTO patient_account (id, app_user_id, first_name, last_name) VALUES
  ('24720000-0000-0000-0000-000000000020', '24720000-0000-0000-0000-000000000011', 'Alice', 'RLS2472'),
  ('24720000-0000-0000-0000-000000000021', '24720000-0000-0000-0000-000000000012', 'Bob',   'RLS2472');

INSERT INTO patient (id, cabinet_id, patient_account_id, first_name, last_name) VALUES
  ('24720000-0000-0000-0000-000000000030',
   '24720000-0000-0000-0000-000000000001',
   '24720000-0000-0000-0000-000000000020', 'Alice', 'RLS2472'),
  ('24720000-0000-0000-0000-000000000031',
   '24720000-0000-0000-0000-000000000001',
   '24720000-0000-0000-0000-000000000021', 'Bob',   'RLS2472');

INSERT INTO practitioner (id, cabinet_id, user_id) VALUES
  ('24720000-0000-0000-0000-000000000040',
   '24720000-0000-0000-0000-000000000001',
   '24720000-0000-0000-0000-000000000010');

INSERT INTO appointment (id, cabinet_id, patient_id, practitioner_id,
                         starts_at, ends_at, status) VALUES
  ('24720000-0000-0000-0000-000000000050',
   '24720000-0000-0000-0000-000000000001',
   '24720000-0000-0000-0000-000000000030',
   '24720000-0000-0000-0000-000000000040',
   now(), now() + interval '30 min', 'done'),
  ('24720000-0000-0000-0000-000000000051',
   '24720000-0000-0000-0000-000000000001',
   '24720000-0000-0000-0000-000000000031',
   '24720000-0000-0000-0000-000000000040',
   now() + interval '1 hour', now() + interval '1 hour 30 min', 'done');

-- Compte rendu d'Alice uniquement.
INSERT INTO consultation_clinique (id, cabinet_id, appointment_id, practitioner_id, status) VALUES
  ('24720000-0000-0000-0000-000000000060',
   '24720000-0000-0000-0000-000000000001',
   '24720000-0000-0000-0000-000000000050',
   '24720000-0000-0000-0000-000000000040',
   'finalized');

-- ===========================================================================
-- CC1. Patient titulaire (Alice) voit son compte rendu
-- ===========================================================================
RESET app.current_cabinet_id;
SELECT set_config('app.patient_account_id', '24720000-0000-0000-0000-000000000020', true);

SELECT is(
  (SELECT count(*)::int FROM consultation_clinique
   WHERE id = '24720000-0000-0000-0000-000000000060'),
  1,
  'CC1 consultation_clinique : patient titulaire voit son compte rendu');

-- ===========================================================================
-- CC2. Autre patient (Bob) voit 0 ligne
-- ===========================================================================
SELECT set_config('app.patient_account_id', '24720000-0000-0000-0000-000000000021', true);

SELECT is(
  (SELECT count(*)::int FROM consultation_clinique
   WHERE id = '24720000-0000-0000-0000-000000000060'),
  0,
  'CC2 consultation_clinique : autre patient ne voit pas le compte rendu (isolation inter-patient)');

-- ===========================================================================
-- CC3. Sans GUC — fail-closed : 0 ligne visible
-- ===========================================================================
SELECT set_config('app.patient_account_id', '', true);
RESET app.current_cabinet_id;

SELECT is(
  (SELECT count(*)::int FROM consultation_clinique
   WHERE id = '24720000-0000-0000-0000-000000000060'),
  0,
  'CC3 consultation_clinique fail-closed : 0 ligne sans GUC');

SELECT * FROM finish();
ROLLBACK;
