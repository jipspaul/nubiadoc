-- 24_webhook_event_log.sql — Tests webhook_event_log : structure, UNIQUE, append-only.
-- Vérifie : colonnes, défauts, UNIQUE (provider, event_id),
--           trigger UPDATE interdit, trigger DELETE interdit, grants nubia_app.
-- Issue : #698
BEGIN;
SELECT * FROM no_plan();

-- ===========================================================================
-- 1. STRUCTURE : table, colonnes, types, défauts
-- ===========================================================================
SELECT has_table('webhook_event_log',
    'webhook_event_log : table présente (0074)');

SELECT has_column('webhook_event_log', 'id',
    'webhook_event_log.id présent');
SELECT col_type_is('webhook_event_log', 'id', 'uuid',
    'webhook_event_log.id uuid');
SELECT col_has_default('webhook_event_log', 'id',
    'webhook_event_log.id a un défaut (gen_random_uuid)');

SELECT has_column('webhook_event_log', 'provider',
    'webhook_event_log.provider présent');
SELECT col_not_null('webhook_event_log', 'provider',
    'webhook_event_log.provider NOT NULL');

SELECT has_column('webhook_event_log', 'event_id',
    'webhook_event_log.event_id présent');
SELECT col_not_null('webhook_event_log', 'event_id',
    'webhook_event_log.event_id NOT NULL');

SELECT has_column('webhook_event_log', 'payload',
    'webhook_event_log.payload présent');
SELECT col_type_is('webhook_event_log', 'payload', 'jsonb',
    'webhook_event_log.payload jsonb');
SELECT col_not_null('webhook_event_log', 'payload',
    'webhook_event_log.payload NOT NULL');

SELECT has_column('webhook_event_log', 'status',
    'webhook_event_log.status présent');
SELECT col_not_null('webhook_event_log', 'status',
    'webhook_event_log.status NOT NULL');
SELECT col_has_default('webhook_event_log', 'status',
    'webhook_event_log.status a un défaut (pending)');

SELECT has_column('webhook_event_log', 'processed_at',
    'webhook_event_log.processed_at présent (nullable)');
SELECT col_is_null('webhook_event_log', 'processed_at',
    'webhook_event_log.processed_at nullable');

SELECT has_column('webhook_event_log', 'error',
    'webhook_event_log.error présent (nullable)');
SELECT col_is_null('webhook_event_log', 'error',
    'webhook_event_log.error nullable');

SELECT has_column('webhook_event_log', 'created_at',
    'webhook_event_log.created_at présent');
SELECT col_type_is('webhook_event_log', 'created_at',
    'timestamp with time zone',
    'webhook_event_log.created_at timestamptz');
SELECT col_not_null('webhook_event_log', 'created_at',
    'webhook_event_log.created_at NOT NULL');

-- ===========================================================================
-- 2. CONTRAINTE UNIQUE (provider, event_id) — idempotence
-- ===========================================================================

-- Premier INSERT : doit passer
SELECT lives_ok(
    $$ INSERT INTO webhook_event_log (id, provider, event_id)
       VALUES ('74000000-0000-0000-0000-000000000001', 'stripe', 'evt_001') $$,
    'webhook_event_log : premier INSERT OK');

-- Second INSERT avec même (provider, event_id) : doit échouer
SELECT throws_ok(
    $$ INSERT INTO webhook_event_log (id, provider, event_id)
       VALUES ('74000000-0000-0000-0000-000000000002', 'stripe', 'evt_001') $$,
    '23505', NULL,
    '⭐ UNIQUE (provider, event_id) : doublon refusé (idempotence)');

-- Même event_id mais provider différent : doit passer
SELECT lives_ok(
    $$ INSERT INTO webhook_event_log (id, provider, event_id)
       VALUES ('74000000-0000-0000-0000-000000000003', 'yousign', 'evt_001') $$,
    'webhook_event_log : même event_id provider différent OK');

-- ===========================================================================
-- 3. APPEND-ONLY : UPDATE et DELETE refusés sous nubia_app
-- Les triggers (webhook_event_log_no_update / no_delete) constituent une défense
-- en profondeur pour les rôles avec plus de privilèges ; sous nubia_app,
-- la révocation de UPDATE/DELETE (42501) s'applique avant même le trigger.
-- ===========================================================================

-- Triggers présents (vérification structurelle)
SELECT ok(
    EXISTS(SELECT 1 FROM pg_trigger
           WHERE tgrelid = 'webhook_event_log'::regclass
             AND tgname = 'webhook_event_log_no_update'),
    'trigger webhook_event_log_no_update présent');

SELECT ok(
    EXISTS(SELECT 1 FROM pg_trigger
           WHERE tgrelid = 'webhook_event_log'::regclass
             AND tgname = 'webhook_event_log_no_delete'),
    'trigger webhook_event_log_no_delete présent');

-- Sous nubia_app : UPDATE refusé par révocation de privilège (42501)
SELECT throws_ok(
    $$ UPDATE webhook_event_log
       SET status = 'processed'
       WHERE id = '74000000-0000-0000-0000-000000000001' $$,
    '42501', NULL,
    '⭐ append-only : UPDATE interdit (permission denied sous nubia_app)');

-- Sous nubia_app : DELETE refusé par révocation de privilège (42501)
SELECT throws_ok(
    $$ DELETE FROM webhook_event_log
       WHERE id = '74000000-0000-0000-0000-000000000001' $$,
    '42501', NULL,
    '⭐ append-only : DELETE interdit (permission denied sous nubia_app)');

-- ===========================================================================
-- 4. GRANTS nubia_app : INSERT + SELECT, pas UPDATE ni DELETE
-- ===========================================================================
SELECT ok(  has_table_privilege('nubia_app', 'webhook_event_log', 'INSERT'),
    'nubia_app a INSERT sur webhook_event_log');
SELECT ok(  has_table_privilege('nubia_app', 'webhook_event_log', 'SELECT'),
    'nubia_app a SELECT sur webhook_event_log');
SELECT ok( NOT has_table_privilege('nubia_app', 'webhook_event_log', 'UPDATE'),
    'nubia_app n''a PAS UPDATE sur webhook_event_log');
SELECT ok( NOT has_table_privilege('nubia_app', 'webhook_event_log', 'DELETE'),
    'nubia_app n''a PAS DELETE sur webhook_event_log');

SELECT * FROM finish();
ROLLBACK;
