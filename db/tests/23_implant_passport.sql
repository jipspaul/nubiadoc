-- 23_implant_passport.sql — Tests implant_passport : structure, FK, RLS, soft-delete.
-- Vérifie : colonnes, FK → patient, fail-closed, non-fuite inter-cabinet, WITH CHECK.
-- Issue : #699
BEGIN;
SELECT * FROM no_plan();

-- ===========================================================================
-- 1. STRUCTURE : table, colonnes, types, défauts
-- ===========================================================================
SELECT has_table('implant_passport',
    'implant_passport : table présente (0072)');

SELECT has_column('implant_passport', 'id',
    'implant_passport.id présent');
SELECT col_type_is('implant_passport', 'id', 'uuid',
    'implant_passport.id uuid');
SELECT col_has_default('implant_passport', 'id',
    'implant_passport.id a un défaut (gen_random_uuid)');

SELECT has_column('implant_passport', 'cabinet_id',
    'implant_passport.cabinet_id présent (tenant)');
SELECT col_not_null('implant_passport', 'cabinet_id',
    'implant_passport.cabinet_id NOT NULL');

SELECT has_column('implant_passport', 'patient_id',
    'implant_passport.patient_id présent');
SELECT col_not_null('implant_passport', 'patient_id',
    'implant_passport.patient_id NOT NULL');

SELECT has_column('implant_passport', 'implant_ref',
    'implant_passport.implant_ref présent');
SELECT col_not_null('implant_passport', 'implant_ref',
    'implant_passport.implant_ref NOT NULL');

SELECT has_column('implant_passport', 'brand',
    'implant_passport.brand présent');
SELECT col_not_null('implant_passport', 'brand',
    'implant_passport.brand NOT NULL');

SELECT has_column('implant_passport', 'lot_number',
    'implant_passport.lot_number présent (nullable)');
SELECT col_is_null('implant_passport', 'lot_number',
    'implant_passport.lot_number nullable');

SELECT has_column('implant_passport', 'placement_date',
    'implant_passport.placement_date présent (nullable)');

SELECT has_column('implant_passport', 'tooth_position',
    'implant_passport.tooth_position présent (nullable)');

SELECT has_column('implant_passport', 'notes',
    'implant_passport.notes présent (nullable)');

SELECT has_column('implant_passport', 'created_at',
    'implant_passport.created_at présent');
SELECT col_type_is('implant_passport', 'created_at',
    'timestamp with time zone',
    'implant_passport.created_at timestamptz');

SELECT has_column('implant_passport', 'deleted_at',
    'implant_passport.deleted_at présent (soft-delete)');
SELECT col_is_null('implant_passport', 'deleted_at',
    'implant_passport.deleted_at nullable');

-- ===========================================================================
-- 2. CLÉS ÉTRANGÈRES
-- ===========================================================================
SELECT fk_ok('implant_passport', 'cabinet_id', 'cabinet', 'id',
    'implant_passport.cabinet_id FK → cabinet.id');
SELECT fk_ok('implant_passport', 'patient_id', 'patient', 'id',
    'implant_passport.patient_id FK → patient.id');

-- ===========================================================================
-- 3. RLS : activation + FORCE
-- ===========================================================================
SELECT ok( (SELECT relrowsecurity FROM pg_class WHERE relname = 'implant_passport'),
    'implant_passport : ROW LEVEL SECURITY activée (0073)');
SELECT ok( (SELECT relforcerowsecurity FROM pg_class WHERE relname = 'implant_passport'),
    'implant_passport : FORCE ROW LEVEL SECURITY (0073)');
SELECT ok(
    EXISTS(SELECT 1 FROM pg_policies
           WHERE tablename = 'implant_passport'
             AND policyname = 'implant_passport_tenant_isolation'),
    'implant_passport : policy implant_passport_tenant_isolation présente');

-- ===========================================================================
-- 4. RLS : fail-closed + non-fuite inter-cabinet + WITH CHECK
-- ===========================================================================

-- Fixtures pour les tests RLS (prefix 69000000 propre à cette suite)
INSERT INTO app_user (id, email, password_hash, kind)
    VALUES ('69000000-0000-0000-0000-0000000000a1',
            'prat.699@example.test', '$argon2id$fixture', 'pro');

SET LOCAL app.current_cabinet_id = '69000000-0000-0000-0000-000000000001';
INSERT INTO cabinet (id, raison_sociale)
    VALUES ('69000000-0000-0000-0000-000000000001', 'Cabinet 699-A');

INSERT INTO patient (id, cabinet_id, first_name, last_name)
    VALUES ('69000000-0000-0000-0000-0000000000b1',
            '69000000-0000-0000-0000-000000000001', 'Alice', '699A');

-- INSERT un implant dans le cabinet 699-A
SELECT lives_ok(
    $$ INSERT INTO implant_passport
           (id, cabinet_id, patient_id, implant_ref, brand, tooth_position)
       VALUES (
           '69000000-0000-0000-0000-0000000000e1',
           '69000000-0000-0000-0000-000000000001',
           '69000000-0000-0000-0000-0000000000b1',
           'STR-4.1-10', 'Straumann', '26'
       ) $$,
    'implant_passport : INSERT sous contexte 699-A OK');

-- Fail-closed : sans GUC → 0 implant visible
RESET app.current_cabinet_id;
SELECT is(
    (SELECT count(*)::int FROM implant_passport
     WHERE id = '69000000-0000-0000-0000-0000000000e1'),
    0,
    '⭐ fail-closed : aucun implant visible sans app.current_cabinet_id');

-- Même-tenant : contexte 699-A → implant visible
SET LOCAL app.current_cabinet_id = '69000000-0000-0000-0000-000000000001';
SELECT is(
    (SELECT count(*)::int FROM implant_passport
     WHERE cabinet_id = '69000000-0000-0000-0000-000000000001'),
    1,
    'contexte 699-A : 1 implant visible dans le bon cabinet');

-- Cabinet 699-B pour le test cross-tenant
SET LOCAL app.current_cabinet_id = '69000000-0000-0000-0000-000000000002';
INSERT INTO cabinet (id, raison_sociale)
    VALUES ('69000000-0000-0000-0000-000000000002', 'Cabinet 699-B');

-- Non-fuite : contexte 699-B → 0 implant de 699-A
SELECT is(
    (SELECT count(*)::int FROM implant_passport
     WHERE cabinet_id = '69000000-0000-0000-0000-000000000001'),
    0,
    '⭐ non-fuite : contexte 699-B ne voit aucun implant du cabinet 699-A');

-- WITH CHECK : insertion cross-tenant refusée
SELECT throws_ok(
    $$ INSERT INTO implant_passport
           (cabinet_id, patient_id, implant_ref, brand)
       VALUES (
           '69000000-0000-0000-0000-000000000001',
           '69000000-0000-0000-0000-0000000000b1',
           'STR-4.1-10', 'Straumann'
       ) $$,
    '42501', NULL,
    '⭐ WITH CHECK : insertion implant_passport cross-tenant refusée');

SELECT * FROM finish();
ROLLBACK;
