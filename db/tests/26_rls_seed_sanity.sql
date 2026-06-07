-- 26_rls_seed_sanity.sql — Sanity RLS seed (issue #1143 — P9).
-- Certifie que chaque profil seed (patient, praticien) ne voit
-- que ses propres données sous le rôle applicatif nubia_app.
--
-- Tests couverts :
--   P1. Patient P1 ne voit QUE ses RDV (pas ceux de P2)         [appointment_patient_read]
--   P2. Patient P1 ne voit QUE ses documents (pas ceux de P2)   [document_patient_read]
--   P3. Patient P1 ne voit QUE ses conversations (pas celles P2)[conversation_patient_read]
--   P4. Patient P1 ne voit QUE ses devis (pas ceux de P2)       [quote_patient_read]
--   P5. Patient P1 ne voit QUE ses plans de traitement (≠ P2)   [treatment_plan_patient_read]
--   P6. waiting_list_entry : fail-closed hors contexte cabinet   [tenant_isolation seule]
--   P7. Praticien : cabinet_membership borné à son cabinet
--
-- Exécuté par pg_prove sous nubia_app (NOSUPERUSER, NOBYPASSRLS).
-- Fixtures auto-contenues (BEGIN…ROLLBACK). Préfixe UUID 11430000.
-- Issue : #1143

BEGIN;
SELECT * FROM no_plan();

-- ===========================================================================
-- Fixtures — 2 cabinets, 2 praticiens, 2 patients avec comptes plateforme,
-- 1 entrée par table par patient.
-- UUID préfixe 11430000 : identifiant unique pour cette suite de tests.
-- Tous les segments sont en hexadécimal valide.
-- ===========================================================================

-- Cabinet C1 + praticien + patient P1
SET LOCAL app.current_cabinet_id = '11430000-0000-0000-0000-000000000001';

INSERT INTO cabinet (id, raison_sociale) VALUES
  ('11430000-0000-0000-0000-000000000001', 'Cabinet P9-C1');

-- Utilisateurs pro et patient pour C1
INSERT INTO app_user (id, email, password_hash, kind) VALUES
  ('11430000-0000-0000-0000-000000a00001', 'prat1@p9.test', '$argon2id$fixture', 'pro'),
  ('11430000-0000-0000-0000-00000b000001', 'patient1@p9.test', '$argon2id$fixture', 'patient');

INSERT INTO cabinet_membership (id, cabinet_id, user_id, role) VALUES
  ('11430000-0000-0000-0000-000000000011',
   '11430000-0000-0000-0000-000000000001',
   '11430000-0000-0000-0000-000000a00001', 'practitioner');

INSERT INTO practitioner (id, cabinet_id, user_id) VALUES
  ('11430000-0000-0000-0000-000000000021',
   '11430000-0000-0000-0000-000000000001',
   '11430000-0000-0000-0000-000000a00001');

INSERT INTO patient_account (id, app_user_id, first_name, last_name) VALUES
  ('11430000-0000-0000-0000-000000000031',
   '11430000-0000-0000-0000-00000b000001', 'PatientUn', 'P9');

INSERT INTO patient (id, cabinet_id, patient_account_id, first_name, last_name) VALUES
  ('11430000-0000-0000-0000-000000000041',
   '11430000-0000-0000-0000-000000000001',
   '11430000-0000-0000-0000-000000000031', 'PatientUn', 'P9');

INSERT INTO appointment (id, cabinet_id, patient_id, practitioner_id,
                         starts_at, ends_at, status) VALUES
  ('11430000-0000-0000-0000-000000000051',
   '11430000-0000-0000-0000-000000000001',
   '11430000-0000-0000-0000-000000000041',
   '11430000-0000-0000-0000-000000000021',
   '2026-07-01 09:00+00', '2026-07-01 09:30+00', 'confirmed');

INSERT INTO document (id, cabinet_id, patient_id, patient_account_id,
                      category, storage_key, filename, mime_type, sha256) VALUES
  ('11430000-0000-0000-0000-000000000061',
   '11430000-0000-0000-0000-000000000001',
   '11430000-0000-0000-0000-000000000041',
   '11430000-0000-0000-0000-000000000031',
   'ordonnance', 'p9/ord-p1.pdf', 'ordo_p1.pdf', 'application/pdf', repeat('1', 64));

INSERT INTO conversation (id, cabinet_id, patient_id, patient_account_id,
                          scope, status) VALUES
  ('11430000-0000-0000-0000-000000000071',
   '11430000-0000-0000-0000-000000000001',
   '11430000-0000-0000-0000-000000000041',
   '11430000-0000-0000-0000-000000000031',
   'patient_cabinet', 'open');

INSERT INTO quote (id, cabinet_id, patient_id, status, total_amount, currency) VALUES
  ('11430000-0000-0000-0000-000000000081',
   '11430000-0000-0000-0000-000000000001',
   '11430000-0000-0000-0000-000000000041',
   'draft', 500.00, 'EUR');

INSERT INTO treatment_plan (id, cabinet_id, patient_id, title, status) VALUES
  ('11430000-0000-0000-0000-000000000091',
   '11430000-0000-0000-0000-000000000001',
   '11430000-0000-0000-0000-000000000041',
   'Plan P9-P1', 'draft');

INSERT INTO waiting_list_entry (id, cabinet_id, patient_id,
                                desired_window, score, status) VALUES
  ('11430000-0000-0000-0000-0000000000a1',
   '11430000-0000-0000-0000-000000000001',
   '11430000-0000-0000-0000-000000000041',
   '{"from":"2026-08-01","to":"2026-08-31"}', 5.0, 'active');

-- Cabinet C2 + praticien + patient P2 (données qui NE doivent PAS fuiter vers P1)
SET LOCAL app.current_cabinet_id = '11430000-0000-0000-0000-000000000002';

INSERT INTO cabinet (id, raison_sociale) VALUES
  ('11430000-0000-0000-0000-000000000002', 'Cabinet P9-C2');

INSERT INTO app_user (id, email, password_hash, kind) VALUES
  ('11430000-0000-0000-0000-000000a00002', 'prat2@p9.test', '$argon2id$fixture', 'pro'),
  ('11430000-0000-0000-0000-00000b000002', 'patient2@p9.test', '$argon2id$fixture', 'patient');

INSERT INTO cabinet_membership (id, cabinet_id, user_id, role) VALUES
  ('11430000-0000-0000-0000-000000000012',
   '11430000-0000-0000-0000-000000000002',
   '11430000-0000-0000-0000-000000a00002', 'practitioner');

INSERT INTO practitioner (id, cabinet_id, user_id) VALUES
  ('11430000-0000-0000-0000-000000000022',
   '11430000-0000-0000-0000-000000000002',
   '11430000-0000-0000-0000-000000a00002');

INSERT INTO patient_account (id, app_user_id, first_name, last_name) VALUES
  ('11430000-0000-0000-0000-000000000032',
   '11430000-0000-0000-0000-00000b000002', 'PatientDeux', 'P9');

INSERT INTO patient (id, cabinet_id, patient_account_id, first_name, last_name) VALUES
  ('11430000-0000-0000-0000-000000000042',
   '11430000-0000-0000-0000-000000000002',
   '11430000-0000-0000-0000-000000000032', 'PatientDeux', 'P9');

INSERT INTO appointment (id, cabinet_id, patient_id, practitioner_id,
                         starts_at, ends_at, status) VALUES
  ('11430000-0000-0000-0000-000000000052',
   '11430000-0000-0000-0000-000000000002',
   '11430000-0000-0000-0000-000000000042',
   '11430000-0000-0000-0000-000000000022',
   '2026-07-01 10:00+00', '2026-07-01 10:30+00', 'confirmed');

INSERT INTO document (id, cabinet_id, patient_id, patient_account_id,
                      category, storage_key, filename, mime_type, sha256) VALUES
  ('11430000-0000-0000-0000-000000000062',
   '11430000-0000-0000-0000-000000000002',
   '11430000-0000-0000-0000-000000000042',
   '11430000-0000-0000-0000-000000000032',
   'radio', 'p9/rad-p2.jpg', 'radio_p2.jpg', 'image/jpeg', repeat('2', 64));

INSERT INTO conversation (id, cabinet_id, patient_id, patient_account_id,
                          scope, status) VALUES
  ('11430000-0000-0000-0000-000000000072',
   '11430000-0000-0000-0000-000000000002',
   '11430000-0000-0000-0000-000000000042',
   '11430000-0000-0000-0000-000000000032',
   'patient_cabinet', 'open');

INSERT INTO quote (id, cabinet_id, patient_id, status, total_amount, currency) VALUES
  ('11430000-0000-0000-0000-000000000082',
   '11430000-0000-0000-0000-000000000002',
   '11430000-0000-0000-0000-000000000042',
   'draft', 800.00, 'EUR');

INSERT INTO treatment_plan (id, cabinet_id, patient_id, title, status) VALUES
  ('11430000-0000-0000-0000-000000000092',
   '11430000-0000-0000-0000-000000000002',
   '11430000-0000-0000-0000-000000000042',
   'Plan P9-P2', 'draft');

INSERT INTO waiting_list_entry (id, cabinet_id, patient_id,
                                desired_window, score, status) VALUES
  ('11430000-0000-0000-0000-0000000000a2',
   '11430000-0000-0000-0000-000000000002',
   '11430000-0000-0000-0000-000000000042',
   '{"from":"2026-09-01","to":"2026-09-30"}', 3.0, 'active');

-- ===========================================================================
-- P1. appointment : P1 voit ses RDV, pas ceux de P2.
-- ===========================================================================
RESET app.current_cabinet_id;
SET LOCAL app.patient_account_id = '11430000-0000-0000-0000-000000000031';

SELECT is(
  (SELECT count(*)::int FROM appointment
   WHERE id = '11430000-0000-0000-0000-000000000051'),
  1,
  '⭐ P9 patient : appointment P1 visible via patient_account_id');

SELECT is(
  (SELECT count(*)::int FROM appointment
   WHERE id = '11430000-0000-0000-0000-000000000052'),
  0,
  '⭐ P9 isolation : appointment P2 invisible depuis contexte patient P1');

RESET app.patient_account_id;
SET LOCAL app.patient_account_id = '11430000-0000-0000-0000-000000000032';

SELECT is(
  (SELECT count(*)::int FROM appointment
   WHERE id = '11430000-0000-0000-0000-000000000052'),
  1,
  '⭐ P9 patient : appointment P2 visible via patient_account_id');

SELECT is(
  (SELECT count(*)::int FROM appointment
   WHERE id = '11430000-0000-0000-0000-000000000051'),
  0,
  '⭐ P9 isolation : appointment P1 invisible depuis contexte patient P2');

-- ===========================================================================
-- P2. document : P1 voit ses docs, pas ceux de P2.
-- ===========================================================================
RESET app.patient_account_id;
SET LOCAL app.patient_account_id = '11430000-0000-0000-0000-000000000031';

SELECT is(
  (SELECT count(*)::int FROM document
   WHERE id = '11430000-0000-0000-0000-000000000061'),
  1,
  '⭐ P9 patient : document P1 visible via patient_account_id');

SELECT is(
  (SELECT count(*)::int FROM document
   WHERE id = '11430000-0000-0000-0000-000000000062'),
  0,
  '⭐ P9 isolation : document P2 invisible depuis contexte patient P1');

RESET app.patient_account_id;
SET LOCAL app.patient_account_id = '11430000-0000-0000-0000-000000000032';

SELECT is(
  (SELECT count(*)::int FROM document
   WHERE id = '11430000-0000-0000-0000-000000000062'),
  1,
  '⭐ P9 patient : document P2 visible via patient_account_id');

SELECT is(
  (SELECT count(*)::int FROM document
   WHERE id = '11430000-0000-0000-0000-000000000061'),
  0,
  '⭐ P9 isolation : document P1 invisible depuis contexte patient P2');

-- ===========================================================================
-- P3. conversation : P1 voit ses conversations, pas celles de P2.
-- ===========================================================================
RESET app.patient_account_id;
SET LOCAL app.patient_account_id = '11430000-0000-0000-0000-000000000031';

SELECT is(
  (SELECT count(*)::int FROM conversation
   WHERE id = '11430000-0000-0000-0000-000000000071'),
  1,
  '⭐ P9 patient : conversation P1 visible via patient_account_id');

SELECT is(
  (SELECT count(*)::int FROM conversation
   WHERE id = '11430000-0000-0000-0000-000000000072'),
  0,
  '⭐ P9 isolation : conversation P2 invisible depuis contexte patient P1');

RESET app.patient_account_id;
SET LOCAL app.patient_account_id = '11430000-0000-0000-0000-000000000032';

SELECT is(
  (SELECT count(*)::int FROM conversation
   WHERE id = '11430000-0000-0000-0000-000000000072'),
  1,
  '⭐ P9 patient : conversation P2 visible via patient_account_id');

SELECT is(
  (SELECT count(*)::int FROM conversation
   WHERE id = '11430000-0000-0000-0000-000000000071'),
  0,
  '⭐ P9 isolation : conversation P1 invisible depuis contexte patient P2');

-- ===========================================================================
-- P4. quote : P1 voit ses devis, pas ceux de P2.
-- ===========================================================================
RESET app.patient_account_id;
SET LOCAL app.patient_account_id = '11430000-0000-0000-0000-000000000031';

SELECT is(
  (SELECT count(*)::int FROM quote
   WHERE id = '11430000-0000-0000-0000-000000000081'),
  1,
  '⭐ P9 patient : devis P1 visible via patient_account_id');

SELECT is(
  (SELECT count(*)::int FROM quote
   WHERE id = '11430000-0000-0000-0000-000000000082'),
  0,
  '⭐ P9 isolation : devis P2 invisible depuis contexte patient P1');

RESET app.patient_account_id;
SET LOCAL app.patient_account_id = '11430000-0000-0000-0000-000000000032';

SELECT is(
  (SELECT count(*)::int FROM quote
   WHERE id = '11430000-0000-0000-0000-000000000082'),
  1,
  '⭐ P9 patient : devis P2 visible via patient_account_id');

SELECT is(
  (SELECT count(*)::int FROM quote
   WHERE id = '11430000-0000-0000-0000-000000000081'),
  0,
  '⭐ P9 isolation : devis P1 invisible depuis contexte patient P2');

-- ===========================================================================
-- P5. treatment_plan : P1 voit ses plans, pas ceux de P2.
-- ===========================================================================
RESET app.patient_account_id;
SET LOCAL app.patient_account_id = '11430000-0000-0000-0000-000000000031';

SELECT is(
  (SELECT count(*)::int FROM treatment_plan
   WHERE id = '11430000-0000-0000-0000-000000000091'),
  1,
  '⭐ P9 patient : treatment_plan P1 visible via patient_account_id');

SELECT is(
  (SELECT count(*)::int FROM treatment_plan
   WHERE id = '11430000-0000-0000-0000-000000000092'),
  0,
  '⭐ P9 isolation : treatment_plan P2 invisible depuis contexte patient P1');

RESET app.patient_account_id;
SET LOCAL app.patient_account_id = '11430000-0000-0000-0000-000000000032';

SELECT is(
  (SELECT count(*)::int FROM treatment_plan
   WHERE id = '11430000-0000-0000-0000-000000000092'),
  1,
  '⭐ P9 patient : treatment_plan P2 visible via patient_account_id');

SELECT is(
  (SELECT count(*)::int FROM treatment_plan
   WHERE id = '11430000-0000-0000-0000-000000000091'),
  0,
  '⭐ P9 isolation : treatment_plan P1 invisible depuis contexte patient P2');

-- ===========================================================================
-- P6. waiting_list_entry : fail-closed hors contexte cabinet
--     (pas de policy patient_account_id → seule tenant_isolation cabinet).
--     Sous contexte patient sans cabinet_id, les entrées sont invisibles.
-- ===========================================================================
RESET app.patient_account_id;
RESET app.current_cabinet_id;

SELECT is(
  (SELECT count(*)::int FROM waiting_list_entry
   WHERE cabinet_id IN (
     '11430000-0000-0000-0000-000000000001',
     '11430000-0000-0000-0000-000000000002')),
  0,
  '⭐ P9 fail-closed : waiting_list_entry invisible sans app.current_cabinet_id');

-- Sous contexte cabinet C1 : seules les entrées de C1 sont visibles (isolation inter-cabinet).
SET LOCAL app.current_cabinet_id = '11430000-0000-0000-0000-000000000001';

SELECT is(
  (SELECT count(*)::int FROM waiting_list_entry
   WHERE id = '11430000-0000-0000-0000-0000000000a1'),
  1,
  '⭐ P9 cabinet C1 : waiting_list_entry P1 visible dans son cabinet');

SELECT is(
  (SELECT count(*)::int FROM waiting_list_entry
   WHERE id = '11430000-0000-0000-0000-0000000000a2'),
  0,
  '⭐ P9 isolation : waiting_list_entry P2 invisible depuis cabinet C1');

-- ===========================================================================
-- P7. cabinet_membership : praticien borné à son cabinet.
-- ===========================================================================
RESET app.current_cabinet_id;
SET LOCAL app.current_cabinet_id = '11430000-0000-0000-0000-000000000001';

SELECT is(
  (SELECT count(*)::int FROM cabinet_membership
   WHERE cabinet_id = '11430000-0000-0000-0000-000000000001'),
  1,
  '⭐ P9 praticien : cabinet_membership C1 visible dans son cabinet');

SELECT is(
  (SELECT count(*)::int FROM cabinet_membership
   WHERE cabinet_id = '11430000-0000-0000-0000-000000000002'),
  0,
  '⭐ P9 isolation : cabinet_membership C2 invisible depuis contexte C1');

SET LOCAL app.current_cabinet_id = '11430000-0000-0000-0000-000000000002';

SELECT is(
  (SELECT count(*)::int FROM cabinet_membership
   WHERE cabinet_id = '11430000-0000-0000-0000-000000000002'),
  1,
  '⭐ P9 praticien : cabinet_membership C2 visible dans son cabinet');

SELECT is(
  (SELECT count(*)::int FROM cabinet_membership
   WHERE cabinet_id = '11430000-0000-0000-0000-000000000001'),
  0,
  '⭐ P9 isolation : cabinet_membership C1 invisible depuis contexte C2');

SELECT * FROM finish();
ROLLBACK;
