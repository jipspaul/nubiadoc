-- 99_quote_attachment_information_attestation.sql
-- pgTAP : quote_attachment + quote_information_attestation (#7204, migration 0278).
--   QA1. Cabinet A crée une pièce jointe liée à un document du même cabinet.
--   QA2. Cabinet A crée une pièce jointe liée à un modèle (template_ref seul).
--   QA3. kind hors énum refusé (23514).
--   QA4. Ni document_id ni template_ref renseigné : refusé (23514, XOR).
--   QA5. document_id ET template_ref renseignés ensemble : refusé (23514, XOR).
--   QA6. document_id d'un AUTRE cabinet refusé (23503, FK composite).
--   QA7. quote_id d'un AUTRE cabinet refusé (23503, FK composite).
--   QA8. RLS : cabinet B ne voit PAS la pièce jointe du cabinet A.
--   QA9. Fail-closed : sans GUC cabinet → 0 ligne.
--   QA10. Lecture patient : bénéficiaire voit la pièce jointe de son devis envoyé.
--   QA11. Lecture patient : devis brouillon → pièce jointe invisible au patient.
--   QI1. Cabinet A crée une attestation d'information.
--   QI2. body vide (après trim) refusé (23514).
--   QI3. patient_id d'un AUTRE cabinet refusé (23503, FK composite).
--   QI4. RLS : cabinet B ne voit PAS l'attestation du cabinet A.
--   QI5. Lecture patient : bénéficiaire voit l'attestation de son devis envoyé.
--   QI6. Lecture patient : devis brouillon → attestation invisible au patient.
-- Exécuté par pg_prove sous nubia_app (NOSUPERUSER, NOBYPASSRLS).
-- Fixtures auto-contenues (BEGIN…ROLLBACK). Préfixe UUID 72040000.
-- Issue : #7204

BEGIN;
SELECT plan(17);

-- ===========================================================================
-- Fixtures : 2 cabinets (A, B), 1 patient + 1 devis 'sent' + 1 devis 'draft'
-- + 1 document par cabinet. Patient A relié à un patient_account (lecture
-- patient).
-- ===========================================================================

INSERT INTO app_user (id, email, password_hash, kind) VALUES
  ('72040000-0000-0000-0000-0000000000a1', 'staff.7204@nubia.test', '$argon2id$fixture', 'pro');
INSERT INTO app_user (id, email, password_hash, kind) VALUES
  ('72040000-0000-0000-0000-0000000000a2', 'patient.7204@nubia.test', '$argon2id$fixture', 'patient');

INSERT INTO patient_account (id, app_user_id, first_name, last_name) VALUES
  ('72040000-0000-0000-0000-0000000000e1', '72040000-0000-0000-0000-0000000000a2', 'Léa', 'Beneficiaire7204');

SET LOCAL app.current_cabinet_id = '72040000-0000-0000-0000-000000000c01';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('72040000-0000-0000-0000-000000000c01', 'Cabinet QuoteAttachment-7204-A');
INSERT INTO patient (id, cabinet_id, first_name, last_name, patient_account_id) VALUES
  ('72040000-0000-0000-0000-000000000020', '72040000-0000-0000-0000-000000000c01',
   'Léa', 'Beneficiaire7204', '72040000-0000-0000-0000-0000000000e1');
INSERT INTO quote (id, cabinet_id, patient_id, status, total_amount) VALUES
  ('72040000-0000-0000-0000-000000000030', '72040000-0000-0000-0000-000000000c01',
   '72040000-0000-0000-0000-000000000020', 'sent', 500.00);
INSERT INTO quote (id, cabinet_id, patient_id, status, total_amount) VALUES
  ('72040000-0000-0000-0000-000000000031', '72040000-0000-0000-0000-000000000c01',
   '72040000-0000-0000-0000-000000000020', 'draft', 500.00);
INSERT INTO document (id, cabinet_id, category, storage_key, filename, mime_type, sha256, uploaded_by) VALUES
  ('72040000-0000-0000-0000-000000000040', '72040000-0000-0000-0000-000000000c01',
   'consentement', 'storage/7204/consent-a.pdf', 'consentement-a.pdf', 'application/pdf',
   repeat('a', 64), '72040000-0000-0000-0000-0000000000a1');
RESET app.current_cabinet_id;

SET LOCAL app.current_cabinet_id = '72040000-0000-0000-0000-000000000c02';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('72040000-0000-0000-0000-000000000c02', 'Cabinet QuoteAttachment-7204-B');
INSERT INTO patient (id, cabinet_id, first_name, last_name) VALUES
  ('72040000-0000-0000-0000-000000000021', '72040000-0000-0000-0000-000000000c02',
   'Marc', 'PatientB7204');
INSERT INTO quote (id, cabinet_id, patient_id, status, total_amount) VALUES
  ('72040000-0000-0000-0000-000000000032', '72040000-0000-0000-0000-000000000c02',
   '72040000-0000-0000-0000-000000000021', 'sent', 300.00);
INSERT INTO document (id, cabinet_id, category, storage_key, filename, mime_type, sha256, uploaded_by) VALUES
  ('72040000-0000-0000-0000-000000000041', '72040000-0000-0000-0000-000000000c02',
   'consentement', 'storage/7204/consent-b.pdf', 'consentement-b.pdf', 'application/pdf',
   repeat('b', 64), NULL);
RESET app.current_cabinet_id;

-- ===========================================================================
-- QA1. Cabinet A crée une pièce jointe liée à un document du même cabinet.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '72040000-0000-0000-0000-000000000c01';
INSERT INTO quote_attachment (id, cabinet_id, quote_id, kind, document_id) VALUES
  ('72040000-0000-0000-0000-000000000050', '72040000-0000-0000-0000-000000000c01',
   '72040000-0000-0000-0000-000000000030', 'consent', '72040000-0000-0000-0000-000000000040');
SELECT is(
  (SELECT count(*)::int FROM quote_attachment WHERE id = '72040000-0000-0000-0000-000000000050'),
  1,
  'QA1 quote_attachment : pièce jointe document même-cabinet OK');

-- ===========================================================================
-- QA2. Cabinet A crée une pièce jointe liée à un modèle (template_ref seul).
-- ===========================================================================
INSERT INTO quote_attachment (id, cabinet_id, quote_id, kind, template_ref) VALUES
  ('72040000-0000-0000-0000-000000000051', '72040000-0000-0000-0000-000000000c01',
   '72040000-0000-0000-0000-000000000030', 'letter', 'modele-courrier-suivi');
SELECT is(
  (SELECT count(*)::int FROM quote_attachment WHERE id = '72040000-0000-0000-0000-000000000051'),
  1,
  'QA2 quote_attachment : pièce jointe template_ref seul OK');

-- Pièce jointe posée sur le devis brouillon (utilisée par QA11).
INSERT INTO quote_attachment (id, cabinet_id, quote_id, kind, template_ref) VALUES
  ('72040000-0000-0000-0000-000000000052', '72040000-0000-0000-0000-000000000c01',
   '72040000-0000-0000-0000-000000000031', 'letter', 'modele-courrier-draft');

-- ===========================================================================
-- QA3. kind hors énum refusé (23514).
-- ===========================================================================
SELECT throws_ok(
  $$ INSERT INTO quote_attachment (cabinet_id, quote_id, kind, template_ref)
     VALUES ('72040000-0000-0000-0000-000000000c01',
             '72040000-0000-0000-0000-000000000030', 'invoice', 'x') $$,
  '23514', NULL,
  'QA3 quote_attachment_kind_check : kind hors énum refusé (23514)');

-- ===========================================================================
-- QA4. Ni document_id ni template_ref renseigné : refusé (23514, XOR).
-- ===========================================================================
SELECT throws_ok(
  $$ INSERT INTO quote_attachment (cabinet_id, quote_id, kind)
     VALUES ('72040000-0000-0000-0000-000000000c01',
             '72040000-0000-0000-0000-000000000030', 'other') $$,
  '23514', NULL,
  'QA4 quote_attachment_source_xor : ni document_id ni template_ref refusé (23514)');

-- ===========================================================================
-- QA5. document_id ET template_ref renseignés ensemble : refusé (23514, XOR).
-- ===========================================================================
SELECT throws_ok(
  $$ INSERT INTO quote_attachment (cabinet_id, quote_id, kind, document_id, template_ref)
     VALUES ('72040000-0000-0000-0000-000000000c01',
             '72040000-0000-0000-0000-000000000030', 'other',
             '72040000-0000-0000-0000-000000000040', 'x') $$,
  '23514', NULL,
  'QA5 quote_attachment_source_xor : document_id + template_ref ensemble refusés (23514)');

-- ===========================================================================
-- QA6. document_id d'un AUTRE cabinet refusé (23503, FK composite).
-- ===========================================================================
SELECT throws_ok(
  $$ INSERT INTO quote_attachment (cabinet_id, quote_id, kind, document_id)
     VALUES ('72040000-0000-0000-0000-000000000c01',
             '72040000-0000-0000-0000-000000000030', 'consent',
             '72040000-0000-0000-0000-000000000041') $$,
  '23503', NULL,
  '⭐ QA6 quote_attachment : document_id d''un autre cabinet refusé (23503, FK composite)');

-- ===========================================================================
-- QA7. quote_id d'un AUTRE cabinet refusé (23503, FK composite).
-- ===========================================================================
SELECT throws_ok(
  $$ INSERT INTO quote_attachment (cabinet_id, quote_id, kind, template_ref)
     VALUES ('72040000-0000-0000-0000-000000000c01',
             '72040000-0000-0000-0000-000000000032', 'letter', 'x') $$,
  '23503', NULL,
  '⭐ QA7 quote_attachment : quote_id d''un autre cabinet refusé (23503, FK composite)');

-- ===========================================================================
-- QA8. RLS : cabinet B ne voit PAS la pièce jointe du cabinet A.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '72040000-0000-0000-0000-000000000c02';
SELECT is(
  (SELECT count(*)::int FROM quote_attachment WHERE id = '72040000-0000-0000-0000-000000000050'),
  0,
  '⭐ QA8 tenant_isolation : cabinet B ne voit PAS la pièce jointe du cabinet A');

-- ===========================================================================
-- QA9. Fail-closed : sans GUC cabinet → 0 ligne.
-- ===========================================================================
RESET app.current_cabinet_id;
SELECT is(
  (SELECT count(*)::int FROM quote_attachment),
  0,
  'QA9 fail-closed : 0 ligne sans GUC cabinet positionné');

-- ===========================================================================
-- QA10. Lecture patient : bénéficiaire voit la pièce jointe de son devis envoyé.
-- ===========================================================================
SET LOCAL app.patient_account_id = '72040000-0000-0000-0000-0000000000e1';
SELECT is(
  (SELECT count(*)::int FROM quote_attachment WHERE id = '72040000-0000-0000-0000-000000000050'),
  1,
  'QA10 quote_attachment_patient_read : bénéficiaire voit la pièce jointe de son devis envoyé');

-- ===========================================================================
-- QA11. Lecture patient : devis brouillon → pièce jointe invisible au patient.
-- ===========================================================================
SELECT is(
  (SELECT count(*)::int FROM quote_attachment WHERE id = '72040000-0000-0000-0000-000000000052'),
  0,
  'QA11 quote_attachment_patient_read : pièce jointe d''un devis brouillon invisible au patient');

RESET app.patient_account_id;

-- ===========================================================================
-- QI1. Cabinet A crée une attestation d'information.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '72040000-0000-0000-0000-000000000c01';
INSERT INTO quote_information_attestation (id, cabinet_id, quote_id, patient_id, body, signed_at, signature_ref) VALUES
  ('72040000-0000-0000-0000-000000000060', '72040000-0000-0000-0000-000000000c01',
   '72040000-0000-0000-0000-000000000030', '72040000-0000-0000-0000-000000000020',
   'Texte d''attestation d''information remis au patient.', now(), 'sig-ref-7204');
SELECT is(
  (SELECT count(*)::int FROM quote_information_attestation WHERE id = '72040000-0000-0000-0000-000000000060'),
  1,
  'QI1 quote_information_attestation : création cabinet A OK');

-- Attestation posée sur le devis brouillon (utilisée par QI6).
INSERT INTO quote_information_attestation (id, cabinet_id, quote_id, patient_id, body) VALUES
  ('72040000-0000-0000-0000-000000000061', '72040000-0000-0000-0000-000000000c01',
   '72040000-0000-0000-0000-000000000031', '72040000-0000-0000-0000-000000000020',
   'Texte d''attestation sur devis brouillon.');

-- ===========================================================================
-- QI2. body vide (après trim) refusé (23514).
-- ===========================================================================
SELECT throws_ok(
  $$ INSERT INTO quote_information_attestation (cabinet_id, quote_id, patient_id, body)
     VALUES ('72040000-0000-0000-0000-000000000c01',
             '72040000-0000-0000-0000-000000000030',
             '72040000-0000-0000-0000-000000000020', '   ') $$,
  '23514', NULL,
  'QI2 quote_information_attestation_body_not_blank : body vide refusé (23514)');

-- ===========================================================================
-- QI3. patient_id d'un AUTRE cabinet refusé (23503, FK composite).
-- ===========================================================================
SELECT throws_ok(
  $$ INSERT INTO quote_information_attestation (cabinet_id, quote_id, patient_id, body)
     VALUES ('72040000-0000-0000-0000-000000000c01',
             '72040000-0000-0000-0000-000000000030',
             '72040000-0000-0000-0000-000000000021', 'Texte') $$,
  '23503', NULL,
  '⭐ QI3 quote_information_attestation : patient_id d''un autre cabinet refusé (23503, FK composite)');

-- ===========================================================================
-- QI4. RLS : cabinet B ne voit PAS l'attestation du cabinet A.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '72040000-0000-0000-0000-000000000c02';
SELECT is(
  (SELECT count(*)::int FROM quote_information_attestation WHERE id = '72040000-0000-0000-0000-000000000060'),
  0,
  '⭐ QI4 tenant_isolation : cabinet B ne voit PAS l''attestation du cabinet A');

RESET app.current_cabinet_id;

-- ===========================================================================
-- QI5. Lecture patient : bénéficiaire voit l'attestation de son devis envoyé.
-- ===========================================================================
SET LOCAL app.patient_account_id = '72040000-0000-0000-0000-0000000000e1';
SELECT is(
  (SELECT count(*)::int FROM quote_information_attestation WHERE id = '72040000-0000-0000-0000-000000000060'),
  1,
  'QI5 quote_information_attestation_patient_read : bénéficiaire voit l''attestation de son devis envoyé');

-- ===========================================================================
-- QI6. Lecture patient : devis brouillon → attestation invisible au patient.
-- ===========================================================================
SELECT is(
  (SELECT count(*)::int FROM quote_information_attestation WHERE id = '72040000-0000-0000-0000-000000000061'),
  0,
  'QI6 quote_information_attestation_patient_read : attestation d''un devis brouillon invisible au patient');

SELECT * FROM finish();
ROLLBACK;
