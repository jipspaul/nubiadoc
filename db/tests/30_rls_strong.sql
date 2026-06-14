-- 30_rls_strong.sql — TDD audit RLS renforcé : provider_verification, medical_record, dental_chart.
-- Issue #1827 — T-DB-D001.
--
-- Invariants couverts :
--   PV1. provider_verification : fail-closed sans app.current_cabinet_id.
--   PV2. provider_verification : isolation — cabinet A ne voit PAS les vérifs de B.
--   PV3. provider_verification : WITH CHECK — insertion cross-tenant refusée (42501).
--   PV4. provider_verification : FORCE ROW LEVEL SECURITY active.
--   MR1. medical_record : fail-closed sans app.current_cabinet_id.
--   MR2. medical_record : isolation cross-tenant (0 ligne d'un autre cabinet).
--   MR3. medical_record : WITH CHECK — écriture cross-tenant refusée (42501).
--   DC1. dental_chart : fail-closed sans app.current_cabinet_id.
--   DC2. dental_chart : isolation cross-tenant (0 ligne d'un autre cabinet).
--   DC3. dental_chart : WITH CHECK — écriture cross-tenant refusée (42501).
--
-- Exécuté par pg_prove sous nubia_app (NOSUPERUSER, NOBYPASSRLS).
-- Fixtures auto-containées (BEGIN…ROLLBACK). Préfixe UUID 18270000.

BEGIN;
SELECT * FROM no_plan();

-- ===========================================================================
-- Pré-condition : les tests tournent bien sous nubia_app
-- ===========================================================================
SELECT is(current_user::text, 'nubia_app',
    '⭐ tests RLS strong exécutés sous nubia_app');
SELECT ok(NOT (SELECT rolbypassrls FROM pg_roles WHERE rolname = 'nubia_app'),
    '⭐ nubia_app NOBYPASSRLS confirmé');

-- ===========================================================================
-- Fixtures communes : 2 cabinets A et B, 2 providers, 2 patients
-- Préfixe UUID 18270000 (propre à cette suite)
-- ===========================================================================

-- Cabinet A
SET LOCAL app.current_cabinet_id = '18270000-0000-0000-0000-000000000001';
INSERT INTO cabinet (id, raison_sociale)
    VALUES ('18270000-0000-0000-0000-000000000001', 'Cabinet RLS-Strong-A');

INSERT INTO app_user (id, email, password_hash, kind)
    VALUES ('18270000-0000-0000-0000-0000000000a1', 'prat.1827a@nubia.test', '$argon2id$fixture', 'pro');

INSERT INTO provider (id, cabinet_id, user_id, display_name, rpps_verified, is_listed)
    VALUES ('18270000-0000-0000-0000-0000000000b1',
            '18270000-0000-0000-0000-000000000001',
            '18270000-0000-0000-0000-0000000000a1',
            'Dr Strong-A', false, false);

INSERT INTO patient (id, cabinet_id, first_name, last_name)
    VALUES ('18270000-0000-0000-0000-0000000000c1',
            '18270000-0000-0000-0000-000000000001', 'Alice', 'Strong');

-- Vérification RPPS pour le provider A (inséré sous contexte A)
INSERT INTO provider_verification (id, provider_id, cabinet_id, identifier, id_type, status)
    VALUES ('18270000-0000-0000-0000-0000000000d1',
            '18270000-0000-0000-0000-0000000000b1',
            '18270000-0000-0000-0000-000000000001',
            '10001234567', 'rpps', 'pending');

-- Dossier médical pour patient A
INSERT INTO medical_record (id, cabinet_id, patient_id)
    VALUES ('18270000-0000-0000-0000-0000000000e1',
            '18270000-0000-0000-0000-000000000001',
            '18270000-0000-0000-0000-0000000000c1');

-- Odontogramme pour patient A
INSERT INTO dental_chart (id, cabinet_id, patient_id)
    VALUES ('18270000-0000-0000-0000-0000000000f1',
            '18270000-0000-0000-0000-000000000001',
            '18270000-0000-0000-0000-0000000000c1');

-- Cabinet B
SET LOCAL app.current_cabinet_id = '18270000-0000-0000-0000-000000000002';
INSERT INTO cabinet (id, raison_sociale)
    VALUES ('18270000-0000-0000-0000-000000000002', 'Cabinet RLS-Strong-B');

INSERT INTO app_user (id, email, password_hash, kind)
    VALUES ('18270000-0000-0000-0000-0000000000a2', 'prat.1827b@nubia.test', '$argon2id$fixture', 'pro');

INSERT INTO provider (id, cabinet_id, user_id, display_name, rpps_verified, is_listed)
    VALUES ('18270000-0000-0000-0000-0000000000b2',
            '18270000-0000-0000-0000-000000000002',
            '18270000-0000-0000-0000-0000000000a2',
            'Dr Strong-B', false, false);

INSERT INTO patient (id, cabinet_id, first_name, last_name)
    VALUES ('18270000-0000-0000-0000-0000000000c2',
            '18270000-0000-0000-0000-000000000002', 'Bob', 'Strong');

-- Vérification RPPS pour le provider B
INSERT INTO provider_verification (id, provider_id, cabinet_id, identifier, id_type, status)
    VALUES ('18270000-0000-0000-0000-0000000000d2',
            '18270000-0000-0000-0000-0000000000b2',
            '18270000-0000-0000-0000-000000000002',
            '10009876543', 'rpps', 'pending');

-- Dossier médical pour patient B
INSERT INTO medical_record (id, cabinet_id, patient_id)
    VALUES ('18270000-0000-0000-0000-0000000000e2',
            '18270000-0000-0000-0000-000000000002',
            '18270000-0000-0000-0000-0000000000c2');

-- Odontogramme pour patient B
INSERT INTO dental_chart (id, cabinet_id, patient_id)
    VALUES ('18270000-0000-0000-0000-0000000000f2',
            '18270000-0000-0000-0000-000000000002',
            '18270000-0000-0000-0000-0000000000c2');

-- ===========================================================================
-- PV4. FORCE ROW LEVEL SECURITY sur provider_verification
-- ===========================================================================
SELECT ok(
    (SELECT relforcerowsecurity FROM pg_class WHERE relname = 'provider_verification'),
    'provider_verification : FORCE ROW LEVEL SECURITY activée (0060)');

SELECT ok(
    EXISTS(SELECT 1 FROM pg_policies
           WHERE tablename = 'provider_verification'
             AND policyname = 'tenant_isolation'),
    'provider_verification : policy tenant_isolation présente (0060)');

-- ===========================================================================
-- PV1. FAIL-CLOSED : sans GUC → 0 vérification visible
-- ===========================================================================
RESET app.current_cabinet_id;
SELECT is(
    (SELECT count(*)::int FROM provider_verification
     WHERE id IN ('18270000-0000-0000-0000-0000000000d1',
                  '18270000-0000-0000-0000-0000000000d2')),
    0,
    '⭐ PV1 fail-closed provider_verification : aucune vérif visible sans app.current_cabinet_id');

-- ===========================================================================
-- PV2. ISOLATION : contexte A → voit seulement les vérifs de A, pas celles de B
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '18270000-0000-0000-0000-000000000001';
SELECT is(
    (SELECT count(*)::int FROM provider_verification
     WHERE cabinet_id = '18270000-0000-0000-0000-000000000001'),
    1,
    'PV2a contexte A : 1 vérification visible (cabinet A)');

SELECT is(
    (SELECT count(*)::int FROM provider_verification
     WHERE cabinet_id = '18270000-0000-0000-0000-000000000002'),
    0,
    '⭐ PV2b non-fuite provider_verification : contexte A ne voit PAS les vérifs de B');

SET LOCAL app.current_cabinet_id = '18270000-0000-0000-0000-000000000002';
SELECT is(
    (SELECT count(*)::int FROM provider_verification
     WHERE cabinet_id = '18270000-0000-0000-0000-000000000001'),
    0,
    '⭐ PV2c non-fuite provider_verification : contexte B ne voit PAS les vérifs de A');

-- ===========================================================================
-- PV3. WITH CHECK : insertion cross-tenant refusée (contexte B, cible cabinet A)
-- ===========================================================================
SELECT throws_ok(
    $$ INSERT INTO provider_verification (provider_id, cabinet_id, identifier, id_type)
       VALUES (
           '18270000-0000-0000-0000-0000000000b1',
           '18270000-0000-0000-0000-000000000001',
           '99999999999', 'rpps'
       ) $$,
    '42501', NULL,
    '⭐ PV3 WITH CHECK provider_verification : insertion cross-tenant (B→A) refusée');

-- ===========================================================================
-- MR1. FAIL-CLOSED medical_record : sans GUC → 0 dossier visible
-- ===========================================================================
RESET app.current_cabinet_id;
SELECT is(
    (SELECT count(*)::int FROM medical_record
     WHERE id IN ('18270000-0000-0000-0000-0000000000e1',
                  '18270000-0000-0000-0000-0000000000e2')),
    0,
    '⭐ MR1 fail-closed medical_record : aucun dossier visible sans app.current_cabinet_id');

-- ===========================================================================
-- MR2. ISOLATION medical_record : contexte A ne voit pas les dossiers de B
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '18270000-0000-0000-0000-000000000001';
SELECT is(
    (SELECT count(*)::int FROM medical_record
     WHERE cabinet_id = '18270000-0000-0000-0000-000000000001'),
    1,
    'MR2a contexte A : 1 dossier médical visible (cabinet A)');

SET LOCAL app.current_cabinet_id = '18270000-0000-0000-0000-000000000002';
SELECT is(
    (SELECT count(*)::int FROM medical_record
     WHERE cabinet_id = '18270000-0000-0000-0000-000000000001'),
    0,
    '⭐ MR2b non-fuite medical_record : contexte B ne voit PAS les dossiers de A');

-- ===========================================================================
-- MR3. WITH CHECK medical_record : écriture cross-tenant refusée (contexte B, cible A)
-- ===========================================================================
SELECT throws_ok(
    $$ INSERT INTO medical_record (cabinet_id, patient_id)
       VALUES (
           '18270000-0000-0000-0000-000000000001',
           '18270000-0000-0000-0000-0000000000c1'
       ) $$,
    '42501', NULL,
    '⭐ MR3 WITH CHECK medical_record : insertion cross-tenant (B→A) refusée');

-- ===========================================================================
-- DC1. FAIL-CLOSED dental_chart : sans GUC → 0 odontogramme visible
-- ===========================================================================
RESET app.current_cabinet_id;
SELECT is(
    (SELECT count(*)::int FROM dental_chart
     WHERE id IN ('18270000-0000-0000-0000-0000000000f1',
                  '18270000-0000-0000-0000-0000000000f2')),
    0,
    '⭐ DC1 fail-closed dental_chart : aucun odontogramme visible sans app.current_cabinet_id');

-- ===========================================================================
-- DC2. ISOLATION dental_chart : contexte A ne voit pas les charts de B
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '18270000-0000-0000-0000-000000000001';
SELECT is(
    (SELECT count(*)::int FROM dental_chart
     WHERE cabinet_id = '18270000-0000-0000-0000-000000000001'),
    1,
    'DC2a contexte A : 1 dental_chart visible (cabinet A)');

SET LOCAL app.current_cabinet_id = '18270000-0000-0000-0000-000000000002';
SELECT is(
    (SELECT count(*)::int FROM dental_chart
     WHERE cabinet_id = '18270000-0000-0000-0000-000000000001'),
    0,
    '⭐ DC2b non-fuite dental_chart : contexte B ne voit PAS les charts de A');

-- ===========================================================================
-- DC3. WITH CHECK dental_chart : écriture cross-tenant refusée (contexte B, cible A)
-- ===========================================================================
SELECT throws_ok(
    $$ INSERT INTO dental_chart (cabinet_id, patient_id)
       VALUES (
           '18270000-0000-0000-0000-000000000001',
           '18270000-0000-0000-0000-0000000000c1'
       ) $$,
    '42501', NULL,
    '⭐ DC3 WITH CHECK dental_chart : insertion cross-tenant (B→A) refusée');

SELECT * FROM finish();
ROLLBACK;
