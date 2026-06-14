-- 32_provider_strong.sql — TDD audit pgTAP : Provider marketplace identity + verification.
-- Issue #1831 — T-DB-D005.
--
-- Invariants couverts :
--   PR1. provider : FORCE ROW LEVEL SECURITY activé (0011).
--   PR2. provider : policy provider_public_read présente — seul is_listed=true visible sans GUC.
--   PR3. ⭐ provider : fail-closed profils privés — is_listed=false invisible sans GUC.
--   PR4. ⭐ provider : CHECK provider_listed_requires_rpps_verified — is_listed=true
--         avec rpps_verified=false refusé (23514) (0058).
--   PR5. ⭐ provider : isolation cross-cabinet — contexte A ne voit PAS le profil
--         privé (is_listed=false) de B.
--   PR6. ⭐ provider : WITH CHECK provider_cabinet_manage — insertion cross-tenant
--         (contexte B, cible cabinet A) refusée (42501).
--   PV1. ⭐ provider_verification : status CHECK — valeur invalide refusée (23514).
--   PV2. provider_verification : id_type CHECK — valeur invalide refusée (23514).
--   PV3. provider_verification : resolved_at — colonne présente et nullable (0020).
--   PS1. ⭐ provider_secretariat : UNIQUE partial WHERE active — doublon actif
--         (provider_id, secretariat_id) refusé (23505) (0087).
--
-- Exécuté par pg_prove sous nubia_app (NOSUPERUSER, NOBYPASSRLS).
-- Fixtures auto-containées (BEGIN…ROLLBACK). Préfixe UUID 18310000.

BEGIN;
SELECT * FROM no_plan();

-- ===========================================================================
-- Pré-condition : tests exécutés sous nubia_app
-- ===========================================================================
SELECT is(current_user::text, 'nubia_app',
    '⭐ provider_strong : exécuté sous nubia_app (NOSUPERUSER, NOBYPASSRLS)');

-- ===========================================================================
-- Fixtures : deux cabinets A et B, 2 users, providers listés/privés,
--             vérifications RPPS, 1 secrétariat + liaison par cabinet.
-- Préfixe UUID 18310000 (propre à cette suite).
-- ===========================================================================

-- Cabinet A + provider listé + provider privé + vérification + secrétariat
SET LOCAL app.current_cabinet_id = '18310000-0000-0000-0000-000000000001';
INSERT INTO cabinet (id, raison_sociale)
    VALUES ('18310000-0000-0000-0000-000000000001', 'Cabinet D005-A')
    ON CONFLICT DO NOTHING;

INSERT INTO app_user (id, email, password_hash, kind)
    VALUES ('18310000-0000-0000-0000-0000000000a1', 'prat.1831a@nubia.test', '$argon2id$fixture', 'pro')
    ON CONFLICT DO NOTHING;

-- Provider A listé (rpps_verified=true, is_listed=true)
INSERT INTO provider (id, cabinet_id, user_id, display_name, rpps_verified, is_listed)
    VALUES ('18310000-0000-0000-0000-0000000000b1',
            '18310000-0000-0000-0000-000000000001',
            '18310000-0000-0000-0000-0000000000a1',
            'Dr Listed-D005-A', true, true)
    ON CONFLICT DO NOTHING;

-- Provider A privé (rpps_verified=false, is_listed=false)
INSERT INTO provider (id, cabinet_id, user_id, display_name, rpps_verified, is_listed)
    VALUES ('18310000-0000-0000-0000-0000000000b3',
            '18310000-0000-0000-0000-000000000001',
            '18310000-0000-0000-0000-0000000000a1',
            'Dr Private-D005-A', false, false)
    ON CONFLICT DO NOTHING;

-- Vérification RPPS pour provider A listé
INSERT INTO provider_verification (id, provider_id, cabinet_id, identifier, id_type, status)
    VALUES ('18310000-0000-0000-0000-0000000000d1',
            '18310000-0000-0000-0000-0000000000b1',
            '18310000-0000-0000-0000-000000000001',
            '11112345678', 'rpps', 'pending')
    ON CONFLICT DO NOTHING;

-- Secrétariat A
INSERT INTO secretariat (id, cabinet_id, name)
    VALUES ('18310000-0000-0000-0000-000000000011',
            '18310000-0000-0000-0000-000000000001',
            'Secrétariat D005-A')
    ON CONFLICT DO NOTHING;

-- Liaison provider_secretariat A (active=true — sert de base pour PS1)
INSERT INTO provider_secretariat (id, provider_id, secretariat_id, active)
    VALUES ('18310000-0000-0000-0000-000000001001',
            '18310000-0000-0000-0000-0000000000b1',
            '18310000-0000-0000-0000-000000000011',
            true)
    ON CONFLICT DO NOTHING;

-- Cabinet B + provider privé + vérification
SET LOCAL app.current_cabinet_id = '18310000-0000-0000-0000-000000000002';
INSERT INTO cabinet (id, raison_sociale)
    VALUES ('18310000-0000-0000-0000-000000000002', 'Cabinet D005-B')
    ON CONFLICT DO NOTHING;

INSERT INTO app_user (id, email, password_hash, kind)
    VALUES ('18310000-0000-0000-0000-0000000000a2', 'prat.1831b@nubia.test', '$argon2id$fixture', 'pro')
    ON CONFLICT DO NOTHING;

-- Provider B privé (is_listed=false) — ne doit PAS être visible depuis contexte A
INSERT INTO provider (id, cabinet_id, user_id, display_name, rpps_verified, is_listed)
    VALUES ('18310000-0000-0000-0000-0000000000b2',
            '18310000-0000-0000-0000-000000000002',
            '18310000-0000-0000-0000-0000000000a2',
            'Dr Private-D005-B', false, false)
    ON CONFLICT DO NOTHING;

INSERT INTO provider_verification (id, provider_id, cabinet_id, identifier, id_type, status)
    VALUES ('18310000-0000-0000-0000-0000000000d2',
            '18310000-0000-0000-0000-0000000000b2',
            '18310000-0000-0000-0000-000000000002',
            '22229876543', 'rpps', 'pending')
    ON CONFLICT DO NOTHING;

-- ===========================================================================
-- PR1. FORCE ROW LEVEL SECURITY sur provider
-- ===========================================================================
SELECT ok(
    (SELECT relforcerowsecurity FROM pg_class WHERE relname = 'provider'),
    'PR1 provider : FORCE ROW LEVEL SECURITY activée (0011)');

-- ===========================================================================
-- PR2. LECTURE PUBLIQUE : policy provider_public_read présente
-- ===========================================================================
SELECT ok(
    EXISTS(SELECT 1 FROM pg_policies
           WHERE tablename = 'provider' AND policyname = 'provider_public_read'),
    'PR2 provider : policy provider_public_read présente (0011)');

-- ===========================================================================
-- PR2b / PR3 : sans GUC — only is_listed=true visible, is_listed=false invisible
-- ===========================================================================
RESET app.current_cabinet_id;

SELECT is(
    (SELECT count(*)::int FROM provider
     WHERE id = '18310000-0000-0000-0000-0000000000b1'),
    1,
    'PR2b provider is_listed=true visible en lecture publique sans GUC');

SELECT is(
    (SELECT count(*)::int FROM provider
     WHERE id = '18310000-0000-0000-0000-0000000000b3'),
    0,
    '⭐ PR3 provider is_listed=false invisible sans GUC — fail-closed lecture publique');

-- ===========================================================================
-- PR4. ⭐ CHECK provider_listed_requires_rpps_verified (0058)
-- Invariant métier : is_listed=true SANS rpps_verified=true → 23514
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '18310000-0000-0000-0000-000000000001';
SELECT throws_ok(
    $$ INSERT INTO provider (cabinet_id, user_id, display_name, rpps_verified, is_listed)
       VALUES (
           '18310000-0000-0000-0000-000000000001',
           '18310000-0000-0000-0000-0000000000a1',
           'Dr Fraude-Listing', false, true
       ) $$,
    '23514', NULL,
    '⭐ PR4 CHECK provider_listed_requires_rpps_verified : is_listed=true sans rpps_verified refusé (23514)');

-- ===========================================================================
-- PR5. ⭐ ISOLATION cross-cabinet : contexte A ne voit PAS le profil privé de B
-- ===========================================================================
SELECT is(
    (SELECT count(*)::int FROM provider
     WHERE id = '18310000-0000-0000-0000-0000000000b2'),
    0,
    '⭐ PR5 non-fuite provider : contexte A ne voit PAS le profil privé (is_listed=false) de B');

-- ===========================================================================
-- PR6. ⭐ WITH CHECK provider_cabinet_manage : insertion cross-tenant refusée
-- (contexte B, on tente d'insérer un provider rattaché au cabinet A)
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '18310000-0000-0000-0000-000000000002';
SELECT throws_ok(
    $$ INSERT INTO provider (cabinet_id, user_id, display_name, rpps_verified, is_listed)
       VALUES (
           '18310000-0000-0000-0000-000000000001',
           '18310000-0000-0000-0000-0000000000a2',
           'Dr Usurpateur', false, false
       ) $$,
    '42501', NULL,
    '⭐ PR6 WITH CHECK provider_cabinet_manage : insertion cross-tenant (B→A) refusée (42501)');

-- ===========================================================================
-- PV1. ⭐ provider_verification status CHECK : valeur invalide refusée (23514)
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '18310000-0000-0000-0000-000000000001';
SELECT throws_ok(
    $$ INSERT INTO provider_verification (provider_id, cabinet_id, identifier, id_type, status)
       VALUES (
           '18310000-0000-0000-0000-0000000000b1',
           '18310000-0000-0000-0000-000000000001',
           '99999000001', 'rpps', 'approved'
       ) $$,
    '23514', NULL,
    '⭐ PV1 provider_verification status CHECK : valeur ''approved'' refusée (23514)');

-- ===========================================================================
-- PV2. provider_verification id_type CHECK : valeur invalide refusée (23514)
-- ===========================================================================
SELECT throws_ok(
    $$ INSERT INTO provider_verification (provider_id, cabinet_id, identifier, id_type)
       VALUES (
           '18310000-0000-0000-0000-0000000000b1',
           '18310000-0000-0000-0000-000000000001',
           '99999000002', 'finess'
       ) $$,
    '23514', NULL,
    'PV2 provider_verification id_type CHECK : valeur ''finess'' refusée (23514)');

-- ===========================================================================
-- PV3. provider_verification resolved_at : colonne présente et nullable (0020)
-- ===========================================================================
SELECT has_column('provider_verification', 'resolved_at',
    'PV3 provider_verification : colonne resolved_at présente (0020)');

SELECT col_is_null('provider_verification', 'resolved_at',
    'PV3b provider_verification : resolved_at nullable — non résolu par défaut (0020)');

-- ===========================================================================
-- PS1. ⭐ provider_secretariat UNIQUE partial WHERE active (0087)
-- Doublon actif (même provider_id + secretariat_id, active=true) refusé (23505)
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '18310000-0000-0000-0000-000000000001';
SELECT throws_ok(
    $$ INSERT INTO provider_secretariat (provider_id, secretariat_id, active)
       VALUES (
           '18310000-0000-0000-0000-0000000000b1',
           '18310000-0000-0000-0000-000000000011',
           true
       ) $$,
    '23505', NULL,
    '⭐ PS1 provider_secretariat UNIQUE partial WHERE active : doublon actif refusé (23505)');

SELECT * FROM finish();
ROLLBACK;
