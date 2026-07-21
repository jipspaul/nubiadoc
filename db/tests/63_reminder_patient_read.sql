-- 63_reminder_patient_read.sql
-- pgTAP : policy reminder_patient_read (#4077).
-- Vérifie la policy ajoutée par la migration 0171 :
--   RPR1. Le patient propriétaire voit son rappel (cross-cabinet, via
--         patient_account_id, sans GUC app.current_cabinet_id positionné)
--   RPR2. Un autre patient_account ne voit pas ce rappel
--   RPR3. Fail-closed : sans GUC app.patient_account_id positionné → 0 ligne
--   RPR4. Le cabinet voit toujours son rappel via tenant_isolation (non-régression)
-- Exécuté par pg_prove sous nubia_app (NOSUPERUSER, NOBYPASSRLS).
-- Fixtures auto-contenues (BEGIN…ROLLBACK). Préfixe UUID 41770000.
-- Issue : #4077

BEGIN;
SELECT plan(4);

SET LOCAL app.current_cabinet_id = '41770000-0000-0000-0000-000000000001';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('41770000-0000-0000-0000-000000000001', 'Cabinet ReminderPatientRead-4077');

INSERT INTO app_user (id, email, password_hash, kind) VALUES
  ('41770000-0000-0000-0000-000000000010', 'patient.4077@nubia.test', '$argon2id$fixture', 'patient');
INSERT INTO patient_account (id, app_user_id, first_name, last_name) VALUES
  ('41770000-0000-0000-0000-000000000011',
   '41770000-0000-0000-0000-000000000010', 'Claire', 'Reminder4077');

INSERT INTO patient (id, cabinet_id, first_name, last_name, patient_account_id) VALUES
  ('41770000-0000-0000-0000-000000000020',
   '41770000-0000-0000-0000-000000000001', 'Claire', 'Reminder4077',
   '41770000-0000-0000-0000-000000000011');

INSERT INTO practitioner (id, cabinet_id, user_id) VALUES
  ('41770000-0000-0000-0000-000000000030',
   '41770000-0000-0000-0000-000000000001',
   '41770000-0000-0000-0000-000000000010');

INSERT INTO appointment (id, cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status) VALUES
  ('41770000-0000-0000-0000-000000000040',
   '41770000-0000-0000-0000-000000000001',
   '41770000-0000-0000-0000-000000000020',
   '41770000-0000-0000-0000-000000000030',
   now() + interval '2 days', now() + interval '2 days' + interval '30 minutes',
   'confirmed');

INSERT INTO reminder (id, cabinet_id, appointment_id, patient_id, scheduled_at, kind, channel, status) VALUES
  ('41770000-0000-0000-0000-000000000050',
   '41770000-0000-0000-0000-000000000001',
   '41770000-0000-0000-0000-000000000040',
   '41770000-0000-0000-0000-000000000020',
   now() + interval '1 day', 'rdv_rappel', 'push', 'pending');

-- ===========================================================================
-- RPR1. Le patient propriétaire voit son rappel (pas de GUC cabinet_id).
-- ===========================================================================
RESET app.current_cabinet_id;
SET LOCAL app.patient_account_id = '41770000-0000-0000-0000-000000000011';
SELECT is(
  (SELECT count(*)::int FROM reminder
   WHERE id = '41770000-0000-0000-0000-000000000050'),
  1,
  'RPR1 reminder : le patient propriétaire voit son rappel (reminder_patient_read)');

-- ===========================================================================
-- RPR2. Un autre patient_account ne voit pas ce rappel.
-- ===========================================================================
SET LOCAL app.patient_account_id = '41770000-0000-0000-0000-000000000099';
SELECT is(
  (SELECT count(*)::int FROM reminder
   WHERE id = '41770000-0000-0000-0000-000000000050'),
  0,
  'RPR2 reminder : un autre patient_account ne voit PAS ce rappel');

-- ===========================================================================
-- RPR3. Fail-closed : sans GUC app.patient_account_id positionné → 0 ligne.
-- ===========================================================================
RESET app.patient_account_id;
SELECT is(
  (SELECT count(*)::int FROM reminder
   WHERE id = '41770000-0000-0000-0000-000000000050'),
  0,
  'RPR3 reminder : fail-closed, 0 ligne visible sans GUC patient_account_id');

-- ===========================================================================
-- RPR4. Non-régression : le cabinet voit toujours son rappel (tenant_isolation).
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '41770000-0000-0000-0000-000000000001';
SELECT is(
  (SELECT count(*)::int FROM reminder
   WHERE id = '41770000-0000-0000-0000-000000000050'),
  1,
  'RPR4 reminder : le cabinet voit toujours son rappel (non-régression tenant_isolation)');

SELECT * FROM finish();
ROLLBACK;
