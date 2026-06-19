-- 34_document_strong.sql — TDD audit pgTAP : Document storage + access control.
-- Issue #1835 — T-DB-D009.
--
-- Invariants couverts :
--   FORCE1. document : FORCE ROW LEVEL SECURITY activée (0011).
--   FORCE2. document : policy tenant_isolation présente (0011).
--   FORCE3. document : policy document_patient_read présente (0034).
--   FORCE4. document : policy document_patient_owner présente (0026).
--   DW1.   WITH CHECK : INSERT cross-tenant (contexte B, cible cabinet A) refusé (42501).
--   DC1.   category CHECK : valeur invalide rejetée (23514).
--   DC2.   side CHECK : valeur invalide rejetée (23514) — valeurs attendues recto|verso.
--   DC3.   scan_status DEFAULT : valeur 'pending' injectée sans spécification (0026).
--   DC4.   size_bytes DEFAULT : colonne présente + valeur 0 par défaut (0037).
--   DS1.   soft-delete : UPDATE deleted_at → lives_ok (donnée conservée, non supprimée).
--   DS2.   sha256 NOT NULL : INSERT sans sha256 refusé (23502).
--   RPO1.  document_patient_owner : carte mutuelle (cabinet_id NULL) accessible via
--          app.patient_account_id direct (0026).
--   RPO2.  document_patient_owner : carte mutuelle invisible pour un autre patient_account.
--
-- Exécuté par pg_prove sous nubia_app (NOSUPERUSER, NOBYPASSRLS).
-- Fixtures auto-containées (BEGIN…ROLLBACK). Préfixe UUID 18350000.

BEGIN;
SELECT * FROM no_plan();

-- ===========================================================================
-- Pré-conditions : rôle et attributs RLS
-- ===========================================================================
SELECT is(current_user::text, 'nubia_app',
    '⭐ document_strong : exécuté sous nubia_app');

SELECT ok(NOT (SELECT rolbypassrls FROM pg_roles WHERE rolname = 'nubia_app'),
    '⭐ nubia_app NOBYPASSRLS confirmé');

-- ===========================================================================
-- FORCE1. FORCE ROW LEVEL SECURITY activée sur document
-- ===========================================================================
SELECT ok(
    (SELECT relforcerowsecurity FROM pg_class WHERE relname = 'document'),
    'FORCE1 document : FORCE ROW LEVEL SECURITY activée (0011)');

-- ===========================================================================
-- FORCE2. Policy tenant_isolation présente sur document
-- ===========================================================================
SELECT ok(
    EXISTS(SELECT 1 FROM pg_policies
           WHERE tablename  = 'document'
             AND policyname = 'tenant_isolation'),
    'FORCE2 document : policy tenant_isolation présente (0011)');

-- ===========================================================================
-- FORCE3. Policy document_patient_read présente (0034)
-- ===========================================================================
SELECT ok(
    EXISTS(SELECT 1 FROM pg_policies
           WHERE tablename  = 'document'
             AND policyname = 'document_patient_read'),
    'FORCE3 document : policy document_patient_read présente (0034)');

-- ===========================================================================
-- FORCE4. Policy document_patient_owner présente (0026)
-- ===========================================================================
SELECT ok(
    EXISTS(SELECT 1 FROM pg_policies
           WHERE tablename  = 'document'
             AND policyname = 'document_patient_owner'),
    'FORCE4 document : policy document_patient_owner présente (0026)');

-- ===========================================================================
-- Fixtures : 2 cabinets, 1 patient chacun, 1 document chacun.
-- Préfixe UUID 18350000 (propre à cette suite, hors des autres fixtures).
-- ===========================================================================

-- Cabinet A
SET LOCAL app.current_cabinet_id = '18350000-0000-0000-0000-000000000001';
INSERT INTO cabinet (id, raison_sociale)
    VALUES ('18350000-0000-0000-0000-000000000001', 'Cabinet Doc-Strong-A');

INSERT INTO app_user (id, email, password_hash, kind)
    VALUES ('18350000-0000-0000-0000-0000000000a1', 'pro.1835a@nubia.test', '$argon2id$fixture', 'pro');

INSERT INTO patient (id, cabinet_id, first_name, last_name)
    VALUES ('18350000-0000-0000-0000-0000000000b1',
            '18350000-0000-0000-0000-000000000001', 'Alice', 'DocStrong');

INSERT INTO document (id, cabinet_id, patient_id, category, storage_key, filename, mime_type, sha256)
    VALUES ('18350000-0000-0000-0000-0000000000d1',
            '18350000-0000-0000-0000-000000000001',
            '18350000-0000-0000-0000-0000000000b1',
            'ordonnance', 'key/1835/a/1', 'ordo_alice.pdf', 'application/pdf', repeat('a', 64));

-- Cabinet B
SET LOCAL app.current_cabinet_id = '18350000-0000-0000-0000-000000000002';
INSERT INTO cabinet (id, raison_sociale)
    VALUES ('18350000-0000-0000-0000-000000000002', 'Cabinet Doc-Strong-B');

INSERT INTO patient (id, cabinet_id, first_name, last_name)
    VALUES ('18350000-0000-0000-0000-0000000000b2',
            '18350000-0000-0000-0000-000000000002', 'Bob', 'DocStrong');

INSERT INTO document (id, cabinet_id, patient_id, category, storage_key, filename, mime_type, sha256)
    VALUES ('18350000-0000-0000-0000-0000000000d2',
            '18350000-0000-0000-0000-000000000002',
            '18350000-0000-0000-0000-0000000000b2',
            'facture', 'key/1835/b/1', 'facture_bob.pdf', 'application/pdf', repeat('b', 64));

-- ===========================================================================
-- DW1. WITH CHECK : INSERT cross-tenant (contexte B, cible cabinet A) refusé
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '18350000-0000-0000-0000-000000000002';
SELECT throws_ok(
    $$ INSERT INTO document (cabinet_id, patient_id, category, storage_key, filename, mime_type, sha256)
       VALUES ('18350000-0000-0000-0000-000000000001',
               '18350000-0000-0000-0000-0000000000b1',
               'radio', 'key/1835/pirate', 'radio_pirate.dcm', 'application/dicom', repeat('c', 64)) $$,
    '42501', NULL,
    '⭐ DW1 WITH CHECK document : INSERT cross-tenant (contexte B → cabinet A) refusé (42501)');

-- ===========================================================================
-- DC1. category CHECK : valeur invalide rejetée (23514)
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '18350000-0000-0000-0000-000000000001';
SELECT throws_ok(
    $$ INSERT INTO document (cabinet_id, patient_id, category, storage_key, filename, mime_type, sha256)
       VALUES ('18350000-0000-0000-0000-000000000001',
               '18350000-0000-0000-0000-0000000000b1',
               'virus', 'key/1835/bad', 'virus.exe', 'application/octet-stream', repeat('d', 64)) $$,
    '23514', NULL,
    '⭐ DC1 category CHECK : valeur "virus" rejetée (23514)');

-- ===========================================================================
-- DC2. side CHECK : valeur invalide rejetée (23514) — 0026
-- ===========================================================================
SELECT throws_ok(
    $$ INSERT INTO document (cabinet_id, patient_id, category, storage_key, filename, mime_type, sha256, side)
       VALUES ('18350000-0000-0000-0000-000000000001',
               '18350000-0000-0000-0000-0000000000b1',
               'carte_mutuelle', 'key/1835/side_bad', 'mutuelle_bad.pdf', 'application/pdf', repeat('e', 64),
               'front') $$,
    '23514', NULL,
    '⭐ DC2 side CHECK : valeur "front" rejetée (23514) — valeurs attendues : recto|verso (0026)');

-- ===========================================================================
-- DC3. scan_status DEFAULT 'pending' : valeur par défaut injectée (0026)
-- ===========================================================================
INSERT INTO document (id, cabinet_id, patient_id, category, storage_key, filename, mime_type, sha256)
    VALUES ('18350000-0000-0000-0000-0000000000d3',
            '18350000-0000-0000-0000-000000000001',
            '18350000-0000-0000-0000-0000000000b1',
            'carte_mutuelle', 'key/1835/a/mutuelle', 'mutuelle.pdf', 'application/pdf', repeat('f', 64));

SELECT is(
    (SELECT scan_status FROM document WHERE id = '18350000-0000-0000-0000-0000000000d3'),
    'pending',
    'DC3 scan_status DEFAULT : valeur "pending" injectée automatiquement (0026)');

-- ===========================================================================
-- DC4. size_bytes DEFAULT 0 : colonne présente + valeur par défaut 0 (0037)
-- ===========================================================================
SELECT is(
    (SELECT size_bytes FROM document WHERE id = '18350000-0000-0000-0000-0000000000d3'),
    0::bigint,
    'DC4 size_bytes DEFAULT : valeur 0 injectée automatiquement (0037)');

-- ===========================================================================
-- DS1. soft-delete : UPDATE deleted_at → lives_ok (donnée conservée)
-- ===========================================================================
SELECT lives_ok(
    $$ UPDATE document SET deleted_at = now()
       WHERE id = '18350000-0000-0000-0000-0000000000d1' $$,
    'DS1 soft-delete document : UPDATE deleted_at → lives_ok (pas de DELETE dur)');

-- ===========================================================================
-- DS2. sha256 NOT NULL : INSERT sans sha256 refusé (23502)
-- ===========================================================================
SELECT throws_ok(
    $$ INSERT INTO document (cabinet_id, patient_id, category, storage_key, filename, mime_type)
       VALUES ('18350000-0000-0000-0000-000000000001',
               '18350000-0000-0000-0000-0000000000b1',
               'radio', 'key/1835/nosha', 'radio_nosha.dcm', 'application/dicom') $$,
    '23502', NULL,
    '⭐ DS2 sha256 NOT NULL : INSERT sans sha256 refusé (23502)');

-- ===========================================================================
-- RPO. document_patient_owner : carte mutuelle (cabinet_id NULL) accessible
--      directement via app.patient_account_id (policy 0026).
-- ===========================================================================

-- Patient account (entité plateforme, pas de RLS cabinet).
INSERT INTO app_user (id, email, password_hash, kind)
    VALUES ('18350000-0000-0000-0000-0000000000e1', 'alice.1835@example.test', '$argon2id$fixture', 'patient');
INSERT INTO patient_account (id, app_user_id, first_name, last_name)
    VALUES ('18350000-0000-0000-0000-0000000000f1',
            '18350000-0000-0000-0000-0000000000e1', 'Alice', 'DocStrong');

-- Insérer une carte mutuelle rattachée au patient_account (cabinet_id NULL = document plateforme).
RESET app.current_cabinet_id;
SET LOCAL app.patient_account_id = '18350000-0000-0000-0000-0000000000f1';

SELECT lives_ok(
    $$ INSERT INTO document (id, cabinet_id, patient_account_id,
                             category, storage_key, filename, mime_type, sha256, side)
       VALUES ('18350000-0000-0000-0000-0000000000d4',
               NULL,
               '18350000-0000-0000-0000-0000000000f1',
               'carte_mutuelle', 'key/1835/mutuelle/recto', 'mutuelle_recto.jpg',
               'image/jpeg', repeat('g', 64), 'recto') $$,
    'RPO1 document_patient_owner : INSERT carte mutuelle via patient_account_id → lives_ok (0026)');

-- RPO1 : carte mutuelle visible avec le bon patient_account_id.
SELECT is(
    (SELECT count(*)::int FROM document WHERE id = '18350000-0000-0000-0000-0000000000d4'),
    1,
    '⭐ RPO1 document_patient_owner : carte mutuelle visible via app.patient_account_id (0026)');

-- RPO2 : carte mutuelle invisible pour un autre patient_account.
RESET app.patient_account_id;
SET LOCAL app.patient_account_id = '18350000-0000-0000-0000-000000000099';
SELECT is(
    (SELECT count(*)::int FROM document WHERE id = '18350000-0000-0000-0000-0000000000d4'),
    0,
    '⭐ RPO2 document_patient_owner : carte mutuelle invisible pour un autre patient_account');

SELECT * FROM finish();
ROLLBACK;
