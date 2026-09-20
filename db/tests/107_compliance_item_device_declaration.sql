-- 107_compliance_item_device_declaration.sql
-- pgTAP : compliance_item / custom_device_declaration (migration 0289, #7171).
--   CD1.  Cabinet A crée un compliance_item de formation (subject_user_id) OK.
--   CD2.  compliance_item_done_consistency : status='done' sans done_at refusé (23514).
--   CD3.  compliance_item_done_consistency : done_at renseigné avec status='pending' refusé (23514).
--   CD4.  kind hors énumération refusé (23514).
--   CD5.  Rattacher evidence_document_id d'un AUTRE cabinet refusé (23503).
--   CD6.  RLS compliance_item : cabinet B ne voit pas l'item de A.
--   CD7.  Fail-closed : sans GUC → 0 ligne compliance_item.
--   CD8.  Cabinet A crée une custom_device_declaration liée à un acte OK.
--   CD9.  Rattacher un patient d'un AUTRE cabinet refusé (23503).
--   CD10. Rattacher un consultation_act d'un AUTRE cabinet refusé (23503).
--   CD11. Rattacher un document d'un AUTRE cabinet refusé (23503).
--   CD12. RLS custom_device_declaration : cabinet B ne voit pas la déclaration de A.
--   CD13. Fail-closed : sans GUC → 0 ligne custom_device_declaration.
-- Exécuté par pg_prove sous nubia_app (NOSUPERUSER, NOBYPASSRLS).
-- Fixtures auto-contenues (BEGIN…ROLLBACK). Préfixe UUID 71710000.
-- Issue : #7171

BEGIN;
SELECT plan(13);

-- ===========================================================================
-- Fixtures : 2 cabinets. Cabinet A avec app_user/practitioner/patient/
-- appointment/consultation_act/document.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '71710000-0000-0000-0000-000000000c01';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('71710000-0000-0000-0000-000000000c01', 'Cabinet Compliance-7171-A');
INSERT INTO app_user (id, email, password_hash, kind) VALUES
  ('71710000-0000-0000-0000-000000000a01', 'praticien.7171@nubia.test', '$argon2id$fixture', 'pro');
INSERT INTO practitioner (id, cabinet_id, user_id) VALUES
  ('71710000-0000-0000-0000-000000000b01', '71710000-0000-0000-0000-000000000c01',
   '71710000-0000-0000-0000-000000000a01');
INSERT INTO patient (id, cabinet_id, first_name, last_name) VALUES
  ('71710000-0000-0000-0000-0000000000e1', '71710000-0000-0000-0000-000000000c01',
   'Patient', 'Compliance7171');
INSERT INTO appointment (id, cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status) VALUES
  ('71710000-0000-0000-0000-00000000ad01', '71710000-0000-0000-0000-000000000c01',
   '71710000-0000-0000-0000-0000000000e1', '71710000-0000-0000-0000-000000000b01',
   '2026-10-01 09:00+00', '2026-10-01 09:30+00', 'confirmed');
INSERT INTO consultation_act (id, cabinet_id, appointment_id, patient_id, practitioner_id, ccam_code, label, amount_cents) VALUES
  ('71710000-0000-0000-0000-00000000ca01', '71710000-0000-0000-0000-000000000c01',
   '71710000-0000-0000-0000-00000000ad01', '71710000-0000-0000-0000-0000000000e1',
   '71710000-0000-0000-0000-000000000b01', 'HBJD001', 'Pose prothèse', 45000);
INSERT INTO document (id, cabinet_id, category, storage_key, filename, mime_type, sha256) VALUES
  ('71710000-0000-0000-0000-00000000d001', '71710000-0000-0000-0000-000000000c01',
   'attestation', 'compliance/7171/a01.pdf', 'attestation.pdf', 'application/pdf', repeat('a', 64));
RESET app.current_cabinet_id;

SET LOCAL app.current_cabinet_id = '71710000-0000-0000-0000-000000000c02';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('71710000-0000-0000-0000-000000000c02', 'Cabinet Compliance-7171-B');
RESET app.current_cabinet_id;

-- ===========================================================================
-- CD1. Cabinet A crée un compliance_item de formation (subject_user_id) OK.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '71710000-0000-0000-0000-000000000c01';
INSERT INTO compliance_item (id, cabinet_id, kind, label, subject_user_id, due_date, recurrence_months) VALUES
  ('71710000-0000-0000-0000-000000005f01', '71710000-0000-0000-0000-000000000c01',
   'training', 'Formation gestes et soins d''urgence', '71710000-0000-0000-0000-000000000a01',
   '2027-01-15', 24);
SELECT is(
  (SELECT count(*)::int FROM compliance_item
   WHERE id = '71710000-0000-0000-0000-000000005f01'),
  1,
  'CD1 compliance_item : création cabinet A, item de formation OK');

-- ===========================================================================
-- CD2/CD3. compliance_item_done_consistency : status et done_at vont par
-- paire.
-- ===========================================================================
SELECT throws_ok(
  $$ INSERT INTO compliance_item (cabinet_id, kind, label, due_date, status)
     VALUES ('71710000-0000-0000-0000-000000000c01',
             'equipment_check', 'Contrôle autoclave', '2027-02-01', 'done') $$,
  '23514', NULL,
  'CD2 compliance_item_done_consistency : status=done sans done_at refusé (23514)');

SELECT throws_ok(
  $$ INSERT INTO compliance_item (cabinet_id, kind, label, due_date, done_at)
     VALUES ('71710000-0000-0000-0000-000000000c01',
             'equipment_check', 'Contrôle autoclave', '2027-02-01', now()) $$,
  '23514', NULL,
  'CD3 compliance_item_done_consistency : done_at renseigné avec status=pending refusé (23514)');

-- ===========================================================================
-- CD4. kind hors énumération refusé.
-- ===========================================================================
SELECT throws_ok(
  $$ INSERT INTO compliance_item (cabinet_id, kind, label, due_date)
     VALUES ('71710000-0000-0000-0000-000000000c01',
             'bogus_kind', 'Item invalide', '2027-02-01') $$,
  '23514', NULL,
  'CD4 compliance_item_kind_check : kind hors énumération refusé (23514)');

-- ===========================================================================
-- CD5. Rattacher evidence_document_id d'un AUTRE cabinet refusé (23503).
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '71710000-0000-0000-0000-000000000c02';
SELECT throws_ok(
  $$ INSERT INTO compliance_item (cabinet_id, kind, label, due_date, evidence_document_id)
     VALUES ('71710000-0000-0000-0000-000000000c02',
             'register', 'Registre DASRI', '2027-02-01',
             '71710000-0000-0000-0000-00000000d001') $$,
  '23503', NULL,
  '⭐ CD5 compliance_item : rattacher un document d''un autre cabinet refusé (23503, RLS FK)');

-- ===========================================================================
-- CD6. RLS compliance_item : cabinet B ne voit PAS l'item de A.
-- ===========================================================================
SELECT is(
  (SELECT count(*)::int FROM compliance_item
   WHERE id = '71710000-0000-0000-0000-000000005f01'),
  0,
  '⭐ CD6 tenant_isolation compliance_item : cabinet B ne voit PAS l''item de A');

-- ===========================================================================
-- CD7. Fail-closed : sans GUC → 0 ligne compliance_item.
-- ===========================================================================
RESET app.current_cabinet_id;
SELECT is(
  (SELECT count(*)::int FROM compliance_item),
  0,
  '⭐ CD7 fail-closed : 0 ligne compliance_item sans GUC positionné');

-- ===========================================================================
-- CD8. Cabinet A crée une custom_device_declaration liée à l'acte OK.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '71710000-0000-0000-0000-000000000c01';
INSERT INTO custom_device_declaration (id, cabinet_id, patient_id, consultation_act_id, lab_name, device_description, document_id) VALUES
  ('71710000-0000-0000-0000-000000006d01', '71710000-0000-0000-0000-000000000c01',
   '71710000-0000-0000-0000-0000000000e1', '71710000-0000-0000-0000-00000000ca01',
   'Laboratoire Dentaire Occitan', 'Prothèse amovible partielle', '71710000-0000-0000-0000-00000000d001');
SELECT is(
  (SELECT count(*)::int FROM custom_device_declaration
   WHERE id = '71710000-0000-0000-0000-000000006d01'),
  1,
  'CD8 custom_device_declaration : création cabinet A, déclaration liée à l''acte OK');

-- ===========================================================================
-- CD9. Rattacher un patient d'un AUTRE cabinet refusé (23503).
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '71710000-0000-0000-0000-000000000c02';
SELECT throws_ok(
  $$ INSERT INTO custom_device_declaration (cabinet_id, patient_id, lab_name, device_description)
     VALUES ('71710000-0000-0000-0000-000000000c02',
             '71710000-0000-0000-0000-0000000000e1',
             'Labo B', 'Gouttière occlusale') $$,
  '23503', NULL,
  '⭐ CD9 custom_device_declaration : rattacher un patient d''un autre cabinet refusé (23503, RLS FK)');

-- ===========================================================================
-- CD10. Rattacher un consultation_act d'un AUTRE cabinet refusé (23503).
-- Nécessite un patient valide côté B pour isoler l'échec sur le FK acte.
-- ===========================================================================
INSERT INTO patient (id, cabinet_id, first_name, last_name) VALUES
  ('71710000-0000-0000-0000-0000000000e2', '71710000-0000-0000-0000-000000000c02',
   'Patient', 'Compliance7171B');
SELECT throws_ok(
  $$ INSERT INTO custom_device_declaration (cabinet_id, patient_id, consultation_act_id, lab_name, device_description)
     VALUES ('71710000-0000-0000-0000-000000000c02',
             '71710000-0000-0000-0000-0000000000e2',
             '71710000-0000-0000-0000-00000000ca01',
             'Labo B', 'Gouttière occlusale') $$,
  '23503', NULL,
  '⭐ CD10 custom_device_declaration : rattacher un acte d''un autre cabinet refusé (23503, RLS FK)');

-- ===========================================================================
-- CD11. Rattacher un document d'un AUTRE cabinet refusé (23503).
-- ===========================================================================
SELECT throws_ok(
  $$ INSERT INTO custom_device_declaration (cabinet_id, patient_id, lab_name, device_description, document_id)
     VALUES ('71710000-0000-0000-0000-000000000c02',
             '71710000-0000-0000-0000-0000000000e2',
             'Labo B', 'Gouttière occlusale',
             '71710000-0000-0000-0000-00000000d001') $$,
  '23503', NULL,
  '⭐ CD11 custom_device_declaration : rattacher un document d''un autre cabinet refusé (23503, RLS FK)');

-- ===========================================================================
-- CD12. RLS custom_device_declaration : cabinet B ne voit PAS la déclaration
-- de A.
-- ===========================================================================
SELECT is(
  (SELECT count(*)::int FROM custom_device_declaration
   WHERE id = '71710000-0000-0000-0000-000000006d01'),
  0,
  '⭐ CD12 tenant_isolation custom_device_declaration : cabinet B ne voit PAS la déclaration de A');

-- ===========================================================================
-- CD13. Fail-closed : sans GUC → 0 ligne custom_device_declaration.
-- ===========================================================================
RESET app.current_cabinet_id;
SELECT is(
  (SELECT count(*)::int FROM custom_device_declaration),
  0,
  '⭐ CD13 fail-closed : 0 ligne custom_device_declaration sans GUC positionné');

SELECT * FROM finish();
ROLLBACK;
