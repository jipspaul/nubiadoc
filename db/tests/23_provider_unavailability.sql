-- 23_provider_unavailability.sql — Tests provider_unavailability : structure, FK, CHECK, RLS.
-- Vérifie : colonnes + types, CHECK starts_at < ends_at (23514), cabinet isolation A↔B,
-- FK ON DELETE CASCADE, fail-closed sans GUC.
-- Issue #2514 — DB-T032.
-- Préfixe UUID : 25140000 (propre à cette suite).
BEGIN;
SELECT * FROM no_plan();

-- ===========================================================================
-- 1. STRUCTURE : table, colonnes, types
-- ===========================================================================
SELECT has_table('provider_unavailability',
    'provider_unavailability : table présente (0116)');

SELECT has_column('provider_unavailability', 'id',
    'provider_unavailability.id présent');
SELECT col_type_is('provider_unavailability', 'id', 'uuid',
    'provider_unavailability.id uuid');
SELECT col_has_default('provider_unavailability', 'id',
    'provider_unavailability.id a un défaut (gen_random_uuid)');

SELECT has_column('provider_unavailability', 'provider_id',
    'provider_unavailability.provider_id présent');
SELECT col_type_is('provider_unavailability', 'provider_id', 'uuid',
    'provider_unavailability.provider_id uuid');
SELECT col_not_null('provider_unavailability', 'provider_id',
    'provider_unavailability.provider_id NOT NULL');

SELECT has_column('provider_unavailability', 'starts_at',
    'provider_unavailability.starts_at présent');
SELECT col_type_is('provider_unavailability', 'starts_at', 'timestamp with time zone',
    'provider_unavailability.starts_at timestamptz');

SELECT has_column('provider_unavailability', 'ends_at',
    'provider_unavailability.ends_at présent');
SELECT col_type_is('provider_unavailability', 'ends_at', 'timestamp with time zone',
    'provider_unavailability.ends_at timestamptz');

SELECT has_column('provider_unavailability', 'reason',
    'provider_unavailability.reason présent');
SELECT col_is_null('provider_unavailability', 'reason',
    'provider_unavailability.reason nullable (text)');

-- RLS : activée + FORCE + policy présente
SELECT ok(
    (SELECT relrowsecurity FROM pg_class WHERE relname = 'provider_unavailability'),
    'provider_unavailability : ROW LEVEL SECURITY activée (0116)');
SELECT ok(
    (SELECT relforcerowsecurity FROM pg_class WHERE relname = 'provider_unavailability'),
    'provider_unavailability : FORCE ROW LEVEL SECURITY (0116)');
SELECT ok(
    EXISTS(SELECT 1 FROM pg_policies
           WHERE tablename  = 'provider_unavailability'
             AND policyname = 'provider_unavailability_cabinet_isolation'),
    'provider_unavailability : policy provider_unavailability_cabinet_isolation présente');

-- ===========================================================================
-- Fixtures : cabinet A + provider A (pour tests 2-5)
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '25140000-0000-0000-0000-000000000001';

INSERT INTO cabinet (id, raison_sociale)
    VALUES ('25140000-0000-0000-0000-000000000001', 'Cabinet Unavail-A');

INSERT INTO app_user (id, email, password_hash, kind)
    VALUES ('25140000-0000-0000-0000-0000000000a1',
            'dr.unavail.a2514@nubia.test', '$argon2id$fixture', 'pro');

INSERT INTO provider (id, cabinet_id, user_id, display_name, rpps_verified, is_listed)
    VALUES ('25140000-0000-0000-0000-0000000000e1',
            '25140000-0000-0000-0000-000000000001',
            '25140000-0000-0000-0000-0000000000a1',
            'Dr Unavail A', true, true);

-- ===========================================================================
-- 2. CHECK : starts_at >= ends_at rejeté (23514)
-- ===========================================================================
SELECT throws_ok(
    $$ INSERT INTO provider_unavailability (provider_id, starts_at, ends_at)
       VALUES ('25140000-0000-0000-0000-0000000000e1',
               now() + interval '2 days',
               now() + interval '1 day') $$,
    '23514', NULL,
    'CHECK : starts_at >= ends_at rejeté (23514)');

-- Insertion valide dans cabinet A (référence pour les tests suivants)
INSERT INTO provider_unavailability (id, provider_id, starts_at, ends_at, reason)
    VALUES ('25140000-0000-0000-0000-000000000100',
            '25140000-0000-0000-0000-0000000000e1',
            now() + interval '7 days',
            now() + interval '14 days',
            'Vacances');

-- ===========================================================================
-- 3. Fail-closed sans GUC
-- ===========================================================================
RESET app.current_cabinet_id;
SELECT is(
    (SELECT count(*)::int FROM provider_unavailability
     WHERE id = '25140000-0000-0000-0000-000000000100'),
    0,
    '⭐ fail-closed : aucune indisponibilité visible sans app.current_cabinet_id');

-- ===========================================================================
-- 4. Cabinet isolation A↔B
-- ===========================================================================

-- Cabinet B + provider B
SET LOCAL app.current_cabinet_id = '25140000-0000-0000-0000-000000000002';
INSERT INTO cabinet (id, raison_sociale)
    VALUES ('25140000-0000-0000-0000-000000000002', 'Cabinet Unavail-B');
INSERT INTO app_user (id, email, password_hash, kind)
    VALUES ('25140000-0000-0000-0000-0000000000a2',
            'dr.unavail.b2514@nubia.test', '$argon2id$fixture', 'pro');
INSERT INTO provider (id, cabinet_id, user_id, display_name, rpps_verified, is_listed)
    VALUES ('25140000-0000-0000-0000-0000000000e2',
            '25140000-0000-0000-0000-000000000002',
            '25140000-0000-0000-0000-0000000000a2',
            'Dr Unavail B', true, true);

-- Non-fuite : contexte B ne voit aucune indisponibilité du cabinet A
SELECT is(
    (SELECT count(*)::int FROM provider_unavailability
     WHERE id = '25140000-0000-0000-0000-000000000100'),
    0,
    '⭐ non-fuite : contexte B ne voit aucune indisponibilité du cabinet A');

-- WITH CHECK : écriture cross-cabinet refusée (provider A depuis contexte B)
SELECT throws_ok(
    $$ INSERT INTO provider_unavailability (provider_id, starts_at, ends_at)
       VALUES ('25140000-0000-0000-0000-0000000000e1',
               now() + interval '30 days',
               now() + interval '31 days') $$,
    '42501', NULL,
    '⭐ WITH CHECK : insertion cross-cabinet refusée (provider A depuis contexte B)');

-- Même cabinet : contexte A voit bien sa propre indisponibilité
SET LOCAL app.current_cabinet_id = '25140000-0000-0000-0000-000000000001';
SELECT is(
    (SELECT count(*)::int FROM provider_unavailability
     WHERE id = '25140000-0000-0000-0000-000000000100'),
    1,
    'contexte A : 1 indisponibilité visible dans le bon cabinet');

-- ===========================================================================
-- 5. FK ON DELETE CASCADE → provider
-- ===========================================================================
SELECT fk_ok('provider_unavailability', 'provider_id', 'provider', 'id',
    'provider_unavailability.provider_id FK → provider.id');

-- Vérifier ON DELETE CASCADE via pg_constraint (confdeltype = 'c')
SELECT ok(
    EXISTS(SELECT 1 FROM pg_constraint c
           JOIN pg_class cl ON cl.oid = c.conrelid
           WHERE cl.relname  = 'provider_unavailability'
             AND c.contype   = 'f'
             AND c.confdeltype = 'c'),
    'provider_unavailability : FK ON DELETE CASCADE confirmé (pg_constraint)');

-- Tester le comportement CASCADE : provider supprimé → indisponibilités supprimées
INSERT INTO app_user (id, email, password_hash, kind)
    VALUES ('25140000-0000-0000-0000-0000000000a3',
            'dr.cascade.c2514@nubia.test', '$argon2id$fixture', 'pro');
INSERT INTO provider (id, cabinet_id, user_id, display_name, rpps_verified, is_listed)
    VALUES ('25140000-0000-0000-0000-0000000000e3',
            '25140000-0000-0000-0000-000000000001',
            '25140000-0000-0000-0000-0000000000a3',
            'Dr Cascade C', true, true);
INSERT INTO provider_unavailability (id, provider_id, starts_at, ends_at)
    VALUES ('25140000-0000-0000-0000-000000000200',
            '25140000-0000-0000-0000-0000000000e3',
            now() + interval '30 days',
            now() + interval '37 days');

DELETE FROM provider WHERE id = '25140000-0000-0000-0000-0000000000e3';

SELECT is(
    (SELECT count(*)::int FROM provider_unavailability
     WHERE id = '25140000-0000-0000-0000-000000000200'),
    0,
    'FK CASCADE : suppression provider entraîne suppression des indisponibilités liées');

SELECT * FROM finish();
ROLLBACK;
