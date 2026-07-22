-- 74_treatment_phase_planned_sessions.sql
-- pgTAP : treatment_phase.planned_sessions/completed_sessions (#4119,
-- migration 0184).
--   TP1. planned_sessions NULL (mécanisme non utilisé) reste valide.
--   TP2. planned_sessions + completed_sessions renseignés → valide.
--   TP3. planned_sessions = 0 refusé (CHECK positive).
--   TP4. completed_sessions négatif refusé (CHECK non-negative).
--   TP5. completed_sessions > planned_sessions refusé.
-- Exécuté par pg_prove sous nubia_app (NOSUPERUSER, NOBYPASSRLS).
-- Fixtures auto-contenues (BEGIN…ROLLBACK). Préfixe UUID 41190000.
-- Issue : #4119

BEGIN;
SELECT plan(5);

-- ===========================================================================
-- Fixtures : 1 cabinet + 1 patient + 1 treatment_plan.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '41190000-0000-0000-0000-000000000c01';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('41190000-0000-0000-0000-000000000c01', 'Cabinet PlannedSessions-4119');
INSERT INTO patient (id, cabinet_id, first_name, last_name) VALUES
  ('41190000-0000-0000-0000-0000000000e1', '41190000-0000-0000-0000-000000000c01',
   'Patient', 'PlannedSessions');
INSERT INTO treatment_plan (id, cabinet_id, patient_id, title) VALUES
  ('41190000-0000-0000-0000-000000000d01', '41190000-0000-0000-0000-000000000c01',
   '41190000-0000-0000-0000-0000000000e1', 'Plan ortho test');

-- ===========================================================================
-- TP1. planned_sessions NULL reste valide (phases existantes non concernées).
-- ===========================================================================
INSERT INTO treatment_phase (id, cabinet_id, plan_id, position, title) VALUES
  ('41190000-0000-0000-0000-000000000f01', '41190000-0000-0000-0000-000000000c01',
   '41190000-0000-0000-0000-000000000d01', 1, 'Phase sans séances programmées');
SELECT is(
  (SELECT planned_sessions FROM treatment_phase
   WHERE id = '41190000-0000-0000-0000-000000000f01'),
  NULL::int,
  'TP1 treatment_phase.planned_sessions : NULL par défaut, mécanisme non utilisé');

-- ===========================================================================
-- TP2. planned_sessions + completed_sessions renseignés → valide.
-- ===========================================================================
INSERT INTO treatment_phase
  (id, cabinet_id, plan_id, position, title, planned_sessions, completed_sessions) VALUES
  ('41190000-0000-0000-0000-000000000f02', '41190000-0000-0000-0000-000000000c01',
   '41190000-0000-0000-0000-000000000d01', 2, 'Suivi ortho', 10, 3);
SELECT is(
  (SELECT completed_sessions FROM treatment_phase
   WHERE id = '41190000-0000-0000-0000-000000000f02'),
  3,
  'TP2 treatment_phase.completed_sessions : 3/10 séances valide');

-- ===========================================================================
-- TP3. planned_sessions = 0 refusé.
-- ===========================================================================
SELECT throws_ok(
  $$ INSERT INTO treatment_phase (cabinet_id, plan_id, position, title, planned_sessions)
     VALUES ('41190000-0000-0000-0000-000000000c01',
             '41190000-0000-0000-0000-000000000d01', 3, 'Phase zéro séance', 0) $$,
  '23514', NULL,
  'TP3 treatment_phase_planned_sessions_positive : planned_sessions = 0 refusé (23514)');

-- ===========================================================================
-- TP4. completed_sessions négatif refusé.
-- ===========================================================================
SELECT throws_ok(
  $$ INSERT INTO treatment_phase (cabinet_id, plan_id, position, title, completed_sessions)
     VALUES ('41190000-0000-0000-0000-000000000c01',
             '41190000-0000-0000-0000-000000000d01', 4, 'Phase négative', -1) $$,
  '23514', NULL,
  'TP4 treatment_phase_completed_sessions_non_negative : négatif refusé (23514)');

-- ===========================================================================
-- TP5. completed_sessions > planned_sessions refusé.
-- ===========================================================================
SELECT throws_ok(
  $$ INSERT INTO treatment_phase
       (cabinet_id, plan_id, position, title, planned_sessions, completed_sessions)
     VALUES ('41190000-0000-0000-0000-000000000c01',
             '41190000-0000-0000-0000-000000000d01', 5, 'Phase incohérente', 5, 6) $$,
  '23514', NULL,
  'TP5 treatment_phase_completed_not_over_planned : completed > planned refusé (23514)');

SELECT * FROM finish();
ROLLBACK;
