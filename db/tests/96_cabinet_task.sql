-- 96_cabinet_task.sql
-- pgTAP : cabinet_task (#7212, migration 0273).
--   CT1. Cabinet A crée une tâche complète (assignee + patient + RDV).
--   CT2. status hors énum refusé (23514).
--   CT3. title vide (après trim) refusé (23514, cabinet_task_title_not_blank).
--   CT4. assignee_user_id d'un AUTRE cabinet refusé (23503, FK composite).
--   CT5. patient_id d'un AUTRE cabinet refusé (23503, FK composite).
--   CT6. appointment_id d'un AUTRE cabinet refusé (23503, FK composite).
--   CT7. RLS : cabinet B ne voit PAS la tâche de A.
--   CT8. Fail-closed : sans GUC → 0 ligne.
-- Exécuté par pg_prove sous nubia_app (NOSUPERUSER, NOBYPASSRLS).
-- Fixtures auto-contenues (BEGIN…ROLLBACK). Préfixe UUID 72120000.
-- Issue : #7212

BEGIN;
SELECT plan(8);

-- ===========================================================================
-- Fixtures : 2 cabinets, cabinet A avec app_user/membership/patient/
-- practitioner/appointment (nécessaires pour tester les FK composites).
-- ===========================================================================
INSERT INTO app_user (id, email, password_hash, kind) VALUES
  ('72120000-0000-0000-0000-0000000000a1', 'assignee.7212@nubia.test', '$argon2id$fixture', 'pro'),
  ('72120000-0000-0000-0000-0000000000a2', 'creator.7212@nubia.test', '$argon2id$fixture', 'pro');

SET LOCAL app.current_cabinet_id = '72120000-0000-0000-0000-000000000c01';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('72120000-0000-0000-0000-000000000c01', 'Cabinet Task-7212-A');
INSERT INTO cabinet_membership (cabinet_id, user_id, role) VALUES
  ('72120000-0000-0000-0000-000000000c01', '72120000-0000-0000-0000-0000000000a1', 'secretary'),
  ('72120000-0000-0000-0000-000000000c01', '72120000-0000-0000-0000-0000000000a2', 'admin');
INSERT INTO patient (id, cabinet_id, first_name, last_name) VALUES
  ('72120000-0000-0000-0000-0000000000e1', '72120000-0000-0000-0000-000000000c01',
   'Patient', 'TaskA');
INSERT INTO practitioner (id, cabinet_id, user_id) VALUES
  ('72120000-0000-0000-0000-0000000000f1', '72120000-0000-0000-0000-000000000c01',
   '72120000-0000-0000-0000-0000000000a2');
INSERT INTO appointment (id, cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status) VALUES
  ('72120000-0000-0000-0000-000000000b01', '72120000-0000-0000-0000-000000000c01',
   '72120000-0000-0000-0000-0000000000e1', '72120000-0000-0000-0000-0000000000f1',
   '2026-01-01 09:00:00+00', '2026-01-01 10:00:00+00', 'confirmed');
RESET app.current_cabinet_id;

SET LOCAL app.current_cabinet_id = '72120000-0000-0000-0000-000000000c02';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('72120000-0000-0000-0000-000000000c02', 'Cabinet Task-7212-B');
INSERT INTO patient (id, cabinet_id, first_name, last_name) VALUES
  ('72120000-0000-0000-0000-0000000000e2', '72120000-0000-0000-0000-000000000c02',
   'Patient', 'TaskB');
RESET app.current_cabinet_id;

-- ===========================================================================
-- CT1. Cabinet A crée une tâche complète (assignee + patient + RDV).
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '72120000-0000-0000-0000-000000000c01';
INSERT INTO cabinet_task
    (id, cabinet_id, title, description, assignee_user_id, patient_id, appointment_id, due_date, created_by) VALUES
  ('72120000-0000-0000-0000-000000000d01', '72120000-0000-0000-0000-000000000c01',
   'Rappeler le patient pour confirmer le devis', 'Suite au RDV de ce matin',
   '72120000-0000-0000-0000-0000000000a1', '72120000-0000-0000-0000-0000000000e1',
   '72120000-0000-0000-0000-000000000b01', '2026-01-05',
   '72120000-0000-0000-0000-0000000000a2');
SELECT is(
  (SELECT count(*)::int FROM cabinet_task
   WHERE id = '72120000-0000-0000-0000-000000000d01'),
  1,
  'CT1 cabinet_task : création cabinet A avec assignee + patient + RDV OK');

-- ===========================================================================
-- CT2. status hors énum refusé (23514).
-- ===========================================================================
SELECT throws_ok(
  $$ INSERT INTO cabinet_task (cabinet_id, title, created_by, status)
     VALUES ('72120000-0000-0000-0000-000000000c01',
             'Tâche statut invalide', '72120000-0000-0000-0000-0000000000a2', 'invalide') $$,
  '23514', NULL,
  'CT2 cabinet_task_status_check : status hors énum refusé (23514)');

-- ===========================================================================
-- CT3. title vide (après trim) refusé (23514, cabinet_task_title_not_blank).
-- ===========================================================================
SELECT throws_ok(
  $$ INSERT INTO cabinet_task (cabinet_id, title, created_by)
     VALUES ('72120000-0000-0000-0000-000000000c01',
             '   ', '72120000-0000-0000-0000-0000000000a2') $$,
  '23514', NULL,
  'CT3 cabinet_task_title_not_blank : title vide (après trim) refusé (23514)');

-- ===========================================================================
-- CT4. assignee_user_id d'un AUTRE cabinet refusé (23503, FK composite).
-- Le créateur reste un membre de A (created_by n'a pas de FK composite),
-- seul l'assignee (membre de A) est utilisé côté cabinet B.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '72120000-0000-0000-0000-000000000c02';
SELECT throws_ok(
  $$ INSERT INTO cabinet_task (cabinet_id, title, assignee_user_id, created_by)
     VALUES ('72120000-0000-0000-0000-000000000c02',
             'Tâche assignee hors cabinet', '72120000-0000-0000-0000-0000000000a1',
             '72120000-0000-0000-0000-0000000000a2') $$,
  '23503', NULL,
  '⭐ CT4 cabinet_task : assignee non-membre du cabinet refusé (23503, FK composite)');

-- ===========================================================================
-- CT5. patient_id d'un AUTRE cabinet refusé (23503, FK composite).
-- ===========================================================================
SELECT throws_ok(
  $$ INSERT INTO cabinet_task (cabinet_id, title, patient_id, created_by)
     VALUES ('72120000-0000-0000-0000-000000000c02',
             'Tâche patient hors cabinet', '72120000-0000-0000-0000-0000000000e1',
             '72120000-0000-0000-0000-0000000000a2') $$,
  '23503', NULL,
  '⭐ CT5 cabinet_task : patient d''un autre cabinet refusé (23503, FK composite)');

-- ===========================================================================
-- CT6. appointment_id d'un AUTRE cabinet refusé (23503, FK composite).
-- ===========================================================================
SELECT throws_ok(
  $$ INSERT INTO cabinet_task (cabinet_id, title, appointment_id, created_by)
     VALUES ('72120000-0000-0000-0000-000000000c02',
             'Tâche RDV hors cabinet', '72120000-0000-0000-0000-000000000b01',
             '72120000-0000-0000-0000-0000000000a2') $$,
  '23503', NULL,
  '⭐ CT6 cabinet_task : appointment d''un autre cabinet refusé (23503, FK composite)');

-- ===========================================================================
-- CT7. RLS : cabinet B ne voit PAS la tâche de A.
-- ===========================================================================
SELECT is(
  (SELECT count(*)::int FROM cabinet_task
   WHERE id = '72120000-0000-0000-0000-000000000d01'),
  0,
  '⭐ CT7 tenant_isolation : cabinet B ne voit PAS la tâche du cabinet A');

-- ===========================================================================
-- CT8. Fail-closed : sans GUC → 0 ligne.
-- ===========================================================================
RESET app.current_cabinet_id;
SELECT is(
  (SELECT count(*)::int FROM cabinet_task),
  0,
  '⭐ CT8 fail-closed : 0 ligne sans GUC positionné');

SELECT * FROM finish();
ROLLBACK;
