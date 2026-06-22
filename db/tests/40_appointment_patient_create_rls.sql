-- 40_appointment_patient_create_rls.sql
-- pgTAP : RLS appointment — policy appointment_patient_create (issue #2497).
--   PC1. Patient (Alice) peut insérer un RDV pour son propre dossier patient.
--   PC2. Patient (Alice) ne peut pas insérer un RDV pour un autre patient (Bob) → 42501.
--   PC3. Sans GUC → INSERT bloqué (fail-closed).
-- Exécuté par pg_prove sous nubia_app (NOSUPERUSER, NOBYPASSRLS).
-- Fixtures auto-contenues (BEGIN…ROLLBACK). Préfixe UUID 24970000.
-- Issue : #2497

BEGIN;
SELECT plan(3);

-- ===========================================================================
-- Fixtures : 1 cabinet, 1 praticien, 2 patients avec comptes plateforme.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '24970000-0000-0000-0000-000000000001';

INSERT INTO cabinet (id, raison_sociale) VALUES
  ('24970000-0000-0000-0000-000000000001', 'Cabinet RLS-2497');

INSERT INTO app_user (id, email, password_hash, kind) VALUES
  ('24970000-0000-0000-0000-000000000010', 'prat.2497@nubia.test',  '$argon2id$fixture', 'pro'),
  ('24970000-0000-0000-0000-000000000011', 'alice.2497@nubia.test', '$argon2id$fixture', 'patient'),
  ('24970000-0000-0000-0000-000000000012', 'bob.2497@nubia.test',   '$argon2id$fixture', 'patient');

INSERT INTO patient_account (id, app_user_id, first_name, last_name) VALUES
  ('24970000-0000-0000-0000-000000000020', '24970000-0000-0000-0000-000000000011', 'Alice', 'RLS2497'),
  ('24970000-0000-0000-0000-000000000021', '24970000-0000-0000-0000-000000000012', 'Bob',   'RLS2497');

INSERT INTO patient (id, cabinet_id, patient_account_id, first_name, last_name) VALUES
  ('24970000-0000-0000-0000-000000000030',
   '24970000-0000-0000-0000-000000000001',
   '24970000-0000-0000-0000-000000000020', 'Alice', 'RLS2497'),
  ('24970000-0000-0000-0000-000000000031',
   '24970000-0000-0000-0000-000000000001',
   '24970000-0000-0000-0000-000000000021', 'Bob',   'RLS2497');

INSERT INTO practitioner (id, cabinet_id, user_id) VALUES
  ('24970000-0000-0000-0000-000000000040',
   '24970000-0000-0000-0000-000000000001',
   '24970000-0000-0000-0000-000000000010');

-- ===========================================================================
-- PC1. Alice insère un RDV pour elle-même (app.patient_account_id uniquement).
-- ===========================================================================
RESET app.current_cabinet_id;
SELECT set_config('app.patient_account_id', '24970000-0000-0000-0000-000000000020', true);

INSERT INTO appointment (id, cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status)
VALUES (
  '24970000-0000-0000-0000-000000000050',
  '24970000-0000-0000-0000-000000000001',
  '24970000-0000-0000-0000-000000000030',
  '24970000-0000-0000-0000-000000000040',
  now() + interval '2 days',
  now() + interval '2 days' + interval '30 min',
  'requested'
);

-- Vérification via appointment_patient_read (policy 0029, même GUC).
SELECT is(
  (SELECT count(*)::int FROM appointment WHERE id = '24970000-0000-0000-0000-000000000050'),
  1,
  '⭐ PC1 appointment_patient_create : Alice peut créer un RDV pour son dossier');

-- ===========================================================================
-- PC2. Alice ne peut pas insérer un RDV pour Bob (patient_id ≠ son compte).
-- ===========================================================================
SELECT throws_ok(
  $$ INSERT INTO appointment (id, cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status)
     VALUES (
       '24970000-0000-0000-0000-000000000051',
       '24970000-0000-0000-0000-000000000001',
       '24970000-0000-0000-0000-000000000031',
       '24970000-0000-0000-0000-000000000040',
       now() + interval '3 days',
       now() + interval '3 days' + interval '30 min',
       'requested'
     ) $$,
  '42501', NULL,
  '⭐ PC2 appointment_patient_create : Alice ne peut pas créer un RDV pour Bob');

-- ===========================================================================
-- PC3. Sans GUC → INSERT bloqué (fail-closed).
-- ===========================================================================
SELECT set_config('app.patient_account_id', '', true);

SELECT throws_ok(
  $$ INSERT INTO appointment (id, cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status)
     VALUES (
       '24970000-0000-0000-0000-000000000052',
       '24970000-0000-0000-0000-000000000001',
       '24970000-0000-0000-0000-000000000030',
       '24970000-0000-0000-0000-000000000040',
       now() + interval '4 days',
       now() + interval '4 days' + interval '30 min',
       'requested'
     ) $$,
  '42501', NULL,
  '⭐ PC3 appointment_patient_create : INSERT bloqué sans GUC (fail-closed)');

SELECT * FROM finish();
ROLLBACK;
