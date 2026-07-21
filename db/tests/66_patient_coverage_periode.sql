-- 66_patient_coverage_periode.sql
-- pgTAP : periode_debut/periode_fin sur patient_coverage (#4096, migration 0174).
--   PP1. periode_fin > periode_debut acceptée.
--   PP2. periode_fin <= periode_debut refusée (CHECK).
--   PP3. periode_debut seul (periode_fin NULL) acceptée.
--   PP4. periode_fin seul (periode_debut NULL) acceptée.
--   PP5. RLS patient-scoped inchangée : GUC account A → voit sa couverture,
--        pas celle de B (même invariant que PC3, 37_patient_strong.sql).
-- Exécuté par pg_prove sous nubia_app (NOSUPERUSER, NOBYPASSRLS).
-- Fixtures auto-contenues (BEGIN…ROLLBACK). Préfixe UUID 40960000.
-- Issue : #4096

BEGIN;
SELECT plan(5);

-- ===========================================================================
-- Fixtures : 2 comptes plateforme (A, B).
-- ===========================================================================
INSERT INTO app_user (id, email, password_hash, kind) VALUES
  ('40960000-0000-0000-0000-0000000000a1', 'coverage.periode.a@nubia.test', '$argon2id$fixture', 'patient');
INSERT INTO app_user (id, email, password_hash, kind) VALUES
  ('40960000-0000-0000-0000-0000000000a2', 'coverage.periode.b@nubia.test', '$argon2id$fixture', 'patient');

INSERT INTO patient_account (id, app_user_id, first_name, last_name) VALUES
  ('40960000-0000-0000-0000-0000000000e1', '40960000-0000-0000-0000-0000000000a1', 'Patient', 'PeriodeA');
INSERT INTO patient_account (id, app_user_id, first_name, last_name) VALUES
  ('40960000-0000-0000-0000-0000000000e2', '40960000-0000-0000-0000-0000000000a2', 'Patient', 'PeriodeB');

-- ===========================================================================
-- PP1. periode_fin > periode_debut acceptée.
-- ===========================================================================
SET LOCAL app.patient_account_id = '40960000-0000-0000-0000-0000000000e1';
INSERT INTO patient_coverage
  (id, patient_account_id, regime_obligatoire, tiers_payant, periode_debut, periode_fin)
  VALUES ('40960000-0000-0000-0000-000000000010',
          '40960000-0000-0000-0000-0000000000e1', 'regime_general', false,
          '2026-01-01', '2026-12-31');
SELECT is(
  (SELECT count(*)::int FROM patient_coverage
   WHERE id = '40960000-0000-0000-0000-000000000010'),
  1,
  'PP1 patient_coverage : periode_fin > periode_debut acceptée');

-- ===========================================================================
-- PP2. periode_fin <= periode_debut refusée (CHECK).
-- ===========================================================================
SET LOCAL app.patient_account_id = '40960000-0000-0000-0000-0000000000e2';
SELECT throws_ok(
  $$ INSERT INTO patient_coverage
       (patient_account_id, tiers_payant, periode_debut, periode_fin)
     VALUES ('40960000-0000-0000-0000-0000000000e2', false,
             '2026-06-01', '2026-01-01') $$,
  '23514', NULL,
  'PP2 patient_coverage_periode_order_chk : periode_fin <= periode_debut refusée (23514)');

-- ===========================================================================
-- PP3. periode_debut seul (periode_fin NULL) acceptée.
-- ===========================================================================
SELECT lives_ok(
  $$ INSERT INTO patient_coverage
       (id, patient_account_id, tiers_payant, periode_debut)
     VALUES ('40960000-0000-0000-0000-000000000011',
             '40960000-0000-0000-0000-0000000000e2', false, '2026-01-01') $$,
  'PP3 patient_coverage : periode_debut seul (periode_fin NULL) acceptée');

-- ===========================================================================
-- PP4. periode_fin seul (periode_debut NULL) acceptée — sur une nouvelle ligne
-- (UNIQUE patient_account_id oblige à repartir d'un 3e compte).
-- ===========================================================================
INSERT INTO app_user (id, email, password_hash, kind) VALUES
  ('40960000-0000-0000-0000-0000000000a3', 'coverage.periode.c@nubia.test', '$argon2id$fixture', 'patient');
INSERT INTO patient_account (id, app_user_id, first_name, last_name) VALUES
  ('40960000-0000-0000-0000-0000000000e3', '40960000-0000-0000-0000-0000000000a3', 'Patient', 'PeriodeC');
SET LOCAL app.patient_account_id = '40960000-0000-0000-0000-0000000000e3';
SELECT lives_ok(
  $$ INSERT INTO patient_coverage
       (id, patient_account_id, tiers_payant, periode_fin)
     VALUES ('40960000-0000-0000-0000-000000000012',
             '40960000-0000-0000-0000-0000000000e3', false, '2026-12-31') $$,
  'PP4 patient_coverage : periode_fin seul (periode_debut NULL) acceptée');

-- ===========================================================================
-- PP5. RLS inchangée : GUC account A → voit sa couverture, pas celle de C.
-- ===========================================================================
SET LOCAL app.patient_account_id = '40960000-0000-0000-0000-0000000000e1';
SELECT is(
  (SELECT count(*)::int FROM patient_coverage
   WHERE id = '40960000-0000-0000-0000-000000000012'),
  0,
  '⭐ PP5 patient_coverage_owner : GUC account A ne voit PAS la couverture de C (RLS inchangée)');

SELECT * FROM finish();
ROLLBACK;
