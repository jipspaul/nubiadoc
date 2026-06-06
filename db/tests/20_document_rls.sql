-- 20_document_rls.sql — RLS document : isolation patient + cross-cabinet.
-- Issue : #809
-- Vérifie :
--   - Patient A ne voit que ses documents (pas ceux de Patient B)
--   - Cabinet A ne voit pas les documents du Cabinet B (cross-cabinet impossible)
--   - category invalide rejetée (CHECK existant, 0004)
--   - document_patient_read : patient voit son document via app.patient_account_id
BEGIN;
SELECT * FROM no_plan();

-- ===========================================================================
-- Fixtures : deux cabinets (A, B), un patient par cabinet, un document chacun.
-- ===========================================================================

-- Cabinet A
SET LOCAL app.current_cabinet_id = 'a0000000-0000-0000-0000-000000000001';
INSERT INTO cabinet (id, raison_sociale)
  VALUES ('a0000000-0000-0000-0000-000000000001', 'Cabinet A');

INSERT INTO app_user (id, email, password_hash, kind)
  VALUES ('a0000000-0000-0000-0000-0000000000a1', 'pro.a@example.test', '$argon2id$fixture', 'pro');

INSERT INTO patient (id, cabinet_id, first_name, last_name)
  VALUES ('a0000000-0000-0000-0000-0000000000d1', 'a0000000-0000-0000-0000-000000000001', 'Alice', 'A');

INSERT INTO document (id, cabinet_id, patient_id, category, storage_key, filename, mime_type, sha256)
  VALUES ('a0000000-0000-0000-0000-0000000000c1',
          'a0000000-0000-0000-0000-000000000001',
          'a0000000-0000-0000-0000-0000000000d1',
          'ordonnance', 'key/a/1', 'ordo_alice.pdf', 'application/pdf', repeat('a', 64));

-- Cabinet B
SET LOCAL app.current_cabinet_id = 'b0000000-0000-0000-0000-000000000001';
INSERT INTO cabinet (id, raison_sociale)
  VALUES ('b0000000-0000-0000-0000-000000000001', 'Cabinet B');

INSERT INTO app_user (id, email, password_hash, kind)
  VALUES ('b0000000-0000-0000-0000-0000000000a1', 'pro.b@example.test', '$argon2id$fixture', 'pro');

INSERT INTO patient (id, cabinet_id, first_name, last_name)
  VALUES ('b0000000-0000-0000-0000-0000000000d1', 'b0000000-0000-0000-0000-000000000001', 'Bob', 'B');

INSERT INTO document (id, cabinet_id, patient_id, category, storage_key, filename, mime_type, sha256)
  VALUES ('b0000000-0000-0000-0000-0000000000c1',
          'b0000000-0000-0000-0000-000000000001',
          'b0000000-0000-0000-0000-0000000000d1',
          'facture', 'key/b/1', 'facture_bob.pdf', 'application/pdf', repeat('b', 64));

-- ===========================================================================
-- 1. ISOLATION CABINET : contexte A ne voit que les docs de A.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = 'a0000000-0000-0000-0000-000000000001';
SELECT is(
  (SELECT count(*)::int FROM document),
  1,
  'contexte cabinet A : 1 document visible');

SELECT is(
  (SELECT count(*)::int FROM document
   WHERE cabinet_id = 'b0000000-0000-0000-0000-000000000001'),
  0,
  '⭐ cross-cabinet : contexte A ne voit AUCUN document de B');

-- ===========================================================================
-- 2. ISOLATION CABINET : contexte B ne voit que les docs de B.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = 'b0000000-0000-0000-0000-000000000001';
SELECT is(
  (SELECT count(*)::int FROM document),
  1,
  'contexte cabinet B : 1 document visible');

SELECT is(
  (SELECT count(*)::int FROM document
   WHERE cabinet_id = 'a0000000-0000-0000-0000-000000000001'),
  0,
  '⭐ cross-cabinet : contexte B ne voit AUCUN document de A');

-- ===========================================================================
-- 3. FAIL-CLOSED : sans GUC -> 0 document visible.
-- ===========================================================================
RESET app.current_cabinet_id;
SELECT is(
  (SELECT count(*)::int FROM document),
  0,
  '⭐ fail-closed : aucun document visible sans app.current_cabinet_id');

-- ===========================================================================
-- 4. PATIENT READ : policy document_patient_read via app.patient_account_id.
--    Un patient lié à Alice voit le document d'Alice, pas celui de Bob.
-- ===========================================================================

-- Créer les comptes patients
INSERT INTO app_user (id, email, password_hash, kind)
  VALUES ('a0000000-0000-0000-0000-0000000000e1', 'alice@example.test', '$argon2id$fixture', 'patient');
INSERT INTO app_user (id, email, password_hash, kind)
  VALUES ('b0000000-0000-0000-0000-0000000000e1', 'bob@example.test', '$argon2id$fixture', 'patient');

INSERT INTO patient_account (id, app_user_id, first_name, last_name)
  VALUES ('a0000000-0000-0000-0000-0000000000f1', 'a0000000-0000-0000-0000-0000000000e1', 'Alice', 'A');
INSERT INTO patient_account (id, app_user_id, first_name, last_name)
  VALUES ('b0000000-0000-0000-0000-0000000000f1', 'b0000000-0000-0000-0000-0000000000e1', 'Bob', 'B');

-- Lier les patients à leur account (sous le bon contexte cabinet)
SET LOCAL app.current_cabinet_id = 'a0000000-0000-0000-0000-000000000001';
UPDATE patient SET patient_account_id = 'a0000000-0000-0000-0000-0000000000f1'
  WHERE id = 'a0000000-0000-0000-0000-0000000000d1';

SET LOCAL app.current_cabinet_id = 'b0000000-0000-0000-0000-000000000001';
UPDATE patient SET patient_account_id = 'b0000000-0000-0000-0000-0000000000f1'
  WHERE id = 'b0000000-0000-0000-0000-0000000000d1';

-- Sans contexte cabinet mais avec patient_account_id d'Alice -> document d'Alice visible
RESET app.current_cabinet_id;
SET LOCAL app.patient_account_id = 'a0000000-0000-0000-0000-0000000000f1';
SELECT is(
  (SELECT count(*)::int FROM document),
  1,
  'policy document_patient_read : Alice voit son document via patient_account_id');

SELECT is(
  (SELECT count(*)::int FROM document
   WHERE patient_id = 'b0000000-0000-0000-0000-0000000000d1'),
  0,
  '⭐ patient A ne voit PAS les documents du patient B');

-- Patient B ne voit que ses docs
RESET app.patient_account_id;
SET LOCAL app.patient_account_id = 'b0000000-0000-0000-0000-0000000000f1';
SELECT is(
  (SELECT count(*)::int FROM document),
  1,
  'policy document_patient_read : Bob voit son document via patient_account_id');

SELECT is(
  (SELECT count(*)::int FROM document
   WHERE patient_id = 'a0000000-0000-0000-0000-0000000000d1'),
  0,
  '⭐ patient B ne voit PAS les documents du patient A');

-- ===========================================================================
-- 5. CHECK category : valeur invalide rejetée.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = 'a0000000-0000-0000-0000-000000000001';
SELECT throws_ok(
  $$ INSERT INTO document (cabinet_id, patient_id, category, storage_key, filename, mime_type, sha256)
     VALUES ('a0000000-0000-0000-0000-000000000001',
             'a0000000-0000-0000-0000-0000000000d1',
             'invalid_category', 'key/a/bad', 'bad.pdf', 'application/pdf', repeat('0', 64)) $$,
  '23514', NULL,
  'document.category invalide rejeté (CHECK)');

SELECT * FROM finish();
ROLLBACK;
