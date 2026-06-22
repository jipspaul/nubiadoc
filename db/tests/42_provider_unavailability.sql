-- 41_provider_unavailability.sql — pgTAP : provider_unavailability (DB-T032).
-- Issue #2514.
--
-- Invariants couverts :
--   STR1.  Colonnes id, provider_id, starts_at, ends_at, reason presentes.
--   STR2.  FORCE ROW LEVEL SECURITY activee.
--   STR3.  Policy provider_unavailability_cabinet_isolation presente.
--   CHK1.  CHECK starts_at < ends_at : starts_at = ends_at rejete (23514).
--   FK1.   FK provider_id → provider : orphelin rejete (23503).
--   RLS1.  Fail-closed : aucune ligne visible sans GUC app.current_cabinet_id.
--   RLS2.  Isolation A↔B : contexte B ne voit pas les indisponibilites de A.
--
-- Execute par pg_prove sous nubia_app (NOSUPERUSER, NOBYPASSRLS).
-- Fixtures auto-contenues (BEGIN…ROLLBACK). Prefixe UUID 25140000.

BEGIN;
SELECT * FROM no_plan();

-- ===========================================================================
-- Pre-conditions
-- ===========================================================================
SELECT is(current_user::text, 'nubia_app',
    'PRE : execute sous nubia_app');

SELECT ok(NOT (SELECT rolbypassrls FROM pg_roles WHERE rolname = 'nubia_app'),
    'PRE nubia_app : NOBYPASSRLS confirme');

-- ===========================================================================
-- STR1. Colonnes presentes avec les bons types
-- ===========================================================================
SELECT has_column('provider_unavailability', 'id',
    'STR1a provider_unavailability.id present');
SELECT col_type_is('provider_unavailability', 'id', 'uuid',
    'STR1b provider_unavailability.id uuid');
SELECT col_has_default('provider_unavailability', 'id',
    'STR1c provider_unavailability.id default gen_random_uuid');

SELECT has_column('provider_unavailability', 'provider_id',
    'STR1d provider_unavailability.provider_id present');
SELECT col_not_null('provider_unavailability', 'provider_id',
    'STR1e provider_unavailability.provider_id NOT NULL');

SELECT has_column('provider_unavailability', 'starts_at',
    'STR1f provider_unavailability.starts_at present');
SELECT col_type_is('provider_unavailability', 'starts_at', 'timestamp with time zone',
    'STR1g provider_unavailability.starts_at timestamptz');
SELECT col_not_null('provider_unavailability', 'starts_at',
    'STR1h provider_unavailability.starts_at NOT NULL');

SELECT has_column('provider_unavailability', 'ends_at',
    'STR1i provider_unavailability.ends_at present');
SELECT col_type_is('provider_unavailability', 'ends_at', 'timestamp with time zone',
    'STR1j provider_unavailability.ends_at timestamptz');
SELECT col_not_null('provider_unavailability', 'ends_at',
    'STR1k provider_unavailability.ends_at NOT NULL');

SELECT has_column('provider_unavailability', 'reason',
    'STR1l provider_unavailability.reason present (nullable)');
SELECT col_is_null('provider_unavailability', 'reason',
    'STR1m provider_unavailability.reason nullable');

-- ===========================================================================
-- STR2. FORCE ROW LEVEL SECURITY
-- ===========================================================================
SELECT ok(
    (SELECT relforcerowsecurity FROM pg_class WHERE relname = 'provider_unavailability'),
    'STR2 provider_unavailability : FORCE ROW LEVEL SECURITY activee');

-- ===========================================================================
-- STR3. Policy presente
-- ===========================================================================
SELECT ok(
    EXISTS(SELECT 1 FROM pg_policies
           WHERE tablename  = 'provider_unavailability'
             AND policyname = 'provider_unavailability_cabinet_isolation'),
    'STR3 provider_unavailability : policy provider_unavailability_cabinet_isolation presente');

-- ===========================================================================
-- Fixtures : 2 cabinets A et B, 2 providers, 1 indisponibilite dans A.
-- Prefixe UUID 25140000 (propre a cette suite).
-- ===========================================================================

-- Cabinet A
SET LOCAL app.current_cabinet_id = '25140000-0000-0000-0000-000000000001';
INSERT INTO cabinet (id, raison_sociale)
    VALUES ('25140000-0000-0000-0000-000000000001', 'Cabinet Unavail-A');

INSERT INTO app_user (id, email, password_hash, kind)
    VALUES ('25140000-0000-0000-0000-0000000000a1',
            'dr.2514a@nubia.test', '$argon2id$fixture', 'pro');

INSERT INTO provider (id, cabinet_id, user_id, display_name, rpps_verified, is_listed)
    VALUES ('25140000-0000-0000-0000-0000000000b1',
            '25140000-0000-0000-0000-000000000001',
            '25140000-0000-0000-0000-0000000000a1',
            'Dr Unavail-A', false, false);

INSERT INTO provider_unavailability (id, provider_id, starts_at, ends_at, reason)
    VALUES ('25140000-0000-0000-0000-0000000000c1',
            '25140000-0000-0000-0000-0000000000b1',
            '2026-07-01 00:00:00+00', '2026-07-15 00:00:00+00',
            'Vacances ete');

-- Cabinet B
SET LOCAL app.current_cabinet_id = '25140000-0000-0000-0000-000000000002';
INSERT INTO cabinet (id, raison_sociale)
    VALUES ('25140000-0000-0000-0000-000000000002', 'Cabinet Unavail-B');

INSERT INTO app_user (id, email, password_hash, kind)
    VALUES ('25140000-0000-0000-0000-0000000000a2',
            'dr.2514b@nubia.test', '$argon2id$fixture', 'pro');

INSERT INTO provider (id, cabinet_id, user_id, display_name, rpps_verified, is_listed)
    VALUES ('25140000-0000-0000-0000-0000000000b2',
            '25140000-0000-0000-0000-000000000002',
            '25140000-0000-0000-0000-0000000000a2',
            'Dr Unavail-B', false, false);

-- ===========================================================================
-- CHK1. CHECK starts_at < ends_at : starts_at = ends_at rejete (23514)
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '25140000-0000-0000-0000-000000000001';
SELECT throws_ok(
    $$ INSERT INTO provider_unavailability (provider_id, starts_at, ends_at)
       VALUES ('25140000-0000-0000-0000-0000000000b1',
               '2026-08-01 10:00:00+00', '2026-08-01 10:00:00+00') $$,
    '23514', NULL,
    'CHK1 provider_unavailability : starts_at = ends_at rejete (23514)');

-- ===========================================================================
-- FK1. FK provider_id → provider : FK ON DELETE CASCADE verifiee par metadonnees
-- (sous nubia_app la RLS intercepte avant 23503 car EXISTS = false pour un
-- UUID inconnu ; on verifie donc la contrainte directement dans pg_constraint)
-- ===========================================================================
SELECT ok(
    EXISTS(
        SELECT 1
        FROM pg_constraint c
        JOIN pg_class t ON t.oid = c.conrelid
        JOIN pg_class r ON r.oid = c.confrelid
        WHERE t.relname = 'provider_unavailability'
          AND r.relname = 'provider'
          AND c.contype = 'f'
          AND c.confdeltype = 'c'
    ),
    'FK1 provider_unavailability.provider_id → provider FK ON DELETE CASCADE presente');

-- ===========================================================================
-- RLS1. Fail-closed : aucune ligne visible sans GUC
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '';
SELECT is(
    (SELECT count(*)::int FROM provider_unavailability),
    0,
    'RLS1 provider_unavailability : fail-closed sans GUC (0 ligne visible)');

-- ===========================================================================
-- RLS2. Isolation A↔B : contexte B ne voit pas les indisponibilites de A
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '25140000-0000-0000-0000-000000000002';
SELECT is(
    (SELECT count(*)::int FROM provider_unavailability),
    0,
    'RLS2 provider_unavailability : contexte B ne voit pas les donnees de A');

SELECT * FROM finish();
ROLLBACK;
