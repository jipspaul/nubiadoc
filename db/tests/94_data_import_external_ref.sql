-- 94_data_import_external_ref.sql
-- pgTAP : reprise de données (#7179, migration 0268).
--   DIP1. patient.external_ref unique par cabinet (doublon refusé, 23505)
--   DIP2. Le même external_ref est accepté dans un AUTRE cabinet (index partiel scoped cabinet)
--   DIP3. appointment.external_ref unique par cabinet (23505)
--   DIP4. data_import_job : payload chiffré et key_ref vont par paire (23514)
--   DIP5. data_import_job.kind hors énum refusé (23514)
--   DIP6. Isolation : cabinet B ne voit pas le job (report) du cabinet A
-- Exécuté par pg_prove sous nubia_app (NOSUPERUSER, NOBYPASSRLS).
-- Fixtures auto-contenues (BEGIN…ROLLBACK). Préfixe UUID 71790000.
-- Issue : #7179

BEGIN;
SELECT plan(6);

SET LOCAL app.current_cabinet_id = '71790000-0000-0000-0000-000000000001';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('71790000-0000-0000-0000-000000000001', 'Cabinet DataImport-7179-A');
SET LOCAL app.current_cabinet_id = '71790000-0000-0000-0000-000000000002';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('71790000-0000-0000-0000-000000000002', 'Cabinet DataImport-7179-B');

SET LOCAL app.current_cabinet_id = '71790000-0000-0000-0000-000000000001';
INSERT INTO app_user (id, email, password_hash, kind) VALUES
  ('71790000-0000-0000-0000-000000000010', 'dip-7179-prac@nubia.test', 'hash', 'pro');
INSERT INTO practitioner (id, cabinet_id, user_id) VALUES
  ('71790000-0000-0000-0000-000000000011',
   '71790000-0000-0000-0000-000000000001',
   '71790000-0000-0000-0000-000000000010');
INSERT INTO patient (id, cabinet_id, first_name, last_name, external_ref) VALUES
  ('71790000-0000-0000-0000-000000000020',
   '71790000-0000-0000-0000-000000000001', 'Alice', 'Import', 'LOGOS-1');

-- DIP1
SELECT throws_ok(
  $$ INSERT INTO patient (cabinet_id, first_name, last_name, external_ref)
     VALUES ('71790000-0000-0000-0000-000000000001', 'Bob', 'Import', 'LOGOS-1') $$,
  '23505', NULL,
  'DIP1 patient.external_ref : doublon refusé dans le même cabinet (23505)');

-- DIP2
SET LOCAL app.current_cabinet_id = '71790000-0000-0000-0000-000000000002';
SELECT lives_ok(
  $$ INSERT INTO patient (cabinet_id, first_name, last_name, external_ref)
     VALUES ('71790000-0000-0000-0000-000000000002', 'Carl', 'Import', 'LOGOS-1') $$,
  'DIP2 patient.external_ref : même clé acceptée dans un autre cabinet');

-- DIP3
SET LOCAL app.current_cabinet_id = '71790000-0000-0000-0000-000000000001';
INSERT INTO appointment (cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status, external_ref)
VALUES ('71790000-0000-0000-0000-000000000001',
        '71790000-0000-0000-0000-000000000020',
        '71790000-0000-0000-0000-000000000011',
        '2030-01-06 09:00+00', '2030-01-06 09:30+00', 'done', 'RDV-1');
SELECT throws_ok(
  $$ INSERT INTO appointment (cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status, external_ref)
     VALUES ('71790000-0000-0000-0000-000000000001',
             '71790000-0000-0000-0000-000000000020',
             '71790000-0000-0000-0000-000000000011',
             '2030-02-06 09:00+00', '2030-02-06 09:30+00', 'done', 'RDV-1') $$,
  '23505', NULL,
  'DIP3 appointment.external_ref : doublon refusé dans le même cabinet (23505)');

-- DIP4
SELECT throws_ok(
  $$ INSERT INTO data_import_job (cabinet_id, source_system, kind, payload_ciphertext)
     VALUES ('71790000-0000-0000-0000-000000000001', 'csv', 'csv_patients', '\x00'::bytea) $$,
  '23514', NULL,
  'DIP4 data_import_job : payload_ciphertext sans payload_key_ref refusé (23514)');

-- DIP5
SELECT throws_ok(
  $$ INSERT INTO data_import_job (cabinet_id, source_system, kind)
     VALUES ('71790000-0000-0000-0000-000000000001', 'csv', 'dsio') $$,
  '23514', NULL,
  'DIP5 data_import_job.kind hors énum refusé (23514)');

-- DIP6
INSERT INTO data_import_job (id, cabinet_id, source_system, kind, report) VALUES
  ('71790000-0000-0000-0000-000000000030',
   '71790000-0000-0000-0000-000000000001', 'csv', 'csv_patients',
   '{"mode":"run","lines":[{"line":2,"action":"created"}]}'::jsonb);
SET LOCAL app.current_cabinet_id = '71790000-0000-0000-0000-000000000002';
SELECT is(
  (SELECT count(*)::int FROM data_import_job
   WHERE id = '71790000-0000-0000-0000-000000000030'),
  0,
  'DIP6 data_import_job : cabinet B ne voit pas le rapport du cabinet A');

SELECT * FROM finish();
ROLLBACK;
