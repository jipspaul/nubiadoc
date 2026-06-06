-- 22_consultation_session.sql — Tests consultation_session : structure, FK, RLS, statuts.
-- Vérifie : colonnes, chiffrement note, FK → appointment, fail-closed, non-fuite,
-- WITH CHECK cross-tenant, contrainte statut, RLS sur FORCE.
-- Issue : #700
BEGIN;
SELECT * FROM no_plan();

-- ===========================================================================
-- 1. STRUCTURE : table, colonnes, types, défauts
-- ===========================================================================
SELECT has_table('consultation_session',
    'consultation_session : table présente (0070)');

SELECT has_column('consultation_session', 'id',
    'consultation_session.id présent');
SELECT col_type_is('consultation_session', 'id', 'uuid',
    'consultation_session.id uuid');
SELECT col_has_default('consultation_session', 'id',
    'consultation_session.id a un défaut (gen_random_uuid)');

SELECT has_column('consultation_session', 'cabinet_id',
    'consultation_session.cabinet_id présent (tenant)');
SELECT col_not_null('consultation_session', 'cabinet_id',
    'consultation_session.cabinet_id NOT NULL');

SELECT has_column('consultation_session', 'appointment_id',
    'consultation_session.appointment_id présent');
SELECT col_not_null('consultation_session', 'appointment_id',
    'consultation_session.appointment_id NOT NULL');

SELECT has_column('consultation_session', 'practitioner_id',
    'consultation_session.practitioner_id présent');
SELECT col_not_null('consultation_session', 'practitioner_id',
    'consultation_session.practitioner_id NOT NULL');

SELECT has_column('consultation_session', 'status',
    'consultation_session.status présent');
SELECT col_not_null('consultation_session', 'status',
    'consultation_session.status NOT NULL');
SELECT col_has_default('consultation_session', 'status',
    'consultation_session.status défaut in_progress');

SELECT has_column('consultation_session', 'started_at',
    'consultation_session.started_at présent');
SELECT col_not_null('consultation_session', 'started_at',
    'consultation_session.started_at NOT NULL');

SELECT has_column('consultation_session', 'completed_at',
    'consultation_session.completed_at présent');
SELECT col_is_null('consultation_session', 'completed_at',
    'consultation_session.completed_at nullable');

-- chiffrement note clinique (PII)
SELECT has_column('consultation_session', 'note_ciphertext',
    'consultation_session.note_ciphertext présent (chiffrement PII)');
SELECT col_type_is('consultation_session', 'note_ciphertext', 'bytea',
    'consultation_session.note_ciphertext bytea');
SELECT has_column('consultation_session', 'note_key_ref',
    'consultation_session.note_key_ref présent (ref clé KMS)');
SELECT col_type_is('consultation_session', 'note_key_ref', 'text',
    'consultation_session.note_key_ref text');

SELECT has_column('consultation_session', 'created_at',
    'consultation_session.created_at présent');
SELECT col_type_is('consultation_session', 'created_at',
    'timestamp with time zone',
    'consultation_session.created_at timestamptz');

-- ===========================================================================
-- 2. CLÉS ÉTRANGÈRES
-- ===========================================================================
SELECT fk_ok('consultation_session', 'cabinet_id', 'cabinet', 'id',
    'consultation_session.cabinet_id FK → cabinet.id');
SELECT fk_ok('consultation_session', 'appointment_id', 'appointment', 'id',
    'consultation_session.appointment_id FK → appointment.id');
SELECT fk_ok('consultation_session', 'practitioner_id', 'practitioner', 'id',
    'consultation_session.practitioner_id FK → practitioner.id');

-- ===========================================================================
-- 3. RLS : activation + FORCE
-- ===========================================================================
SELECT ok( (SELECT relrowsecurity FROM pg_class WHERE relname = 'consultation_session'),
    'consultation_session : ROW LEVEL SECURITY activée (0071)');
SELECT ok( (SELECT relforcerowsecurity FROM pg_class WHERE relname = 'consultation_session'),
    'consultation_session : FORCE ROW LEVEL SECURITY (0071)');
SELECT ok(
    EXISTS(SELECT 1 FROM pg_policies
           WHERE tablename = 'consultation_session'
             AND policyname = 'consultation_session_tenant_isolation'),
    'consultation_session : policy consultation_session_tenant_isolation présente');

-- ===========================================================================
-- 4. STATUTS : contrainte CHECK — valeurs invalides refusées
-- ===========================================================================

-- Fixtures communes pour les tests de statuts et RLS
-- (prefix 70000000 propre à cette suite)
INSERT INTO app_user (id, email, password_hash, kind)
    VALUES ('70000000-0000-0000-0000-0000000000a1',
            'prat.700@example.test', '$argon2id$fixture', 'pro');

SET LOCAL app.current_cabinet_id = '70000000-0000-0000-0000-000000000001';
INSERT INTO cabinet (id, raison_sociale)
    VALUES ('70000000-0000-0000-0000-000000000001', 'Cabinet 700-A');

INSERT INTO practitioner (id, cabinet_id, user_id)
    VALUES ('70000000-0000-0000-0000-0000000000c1',
            '70000000-0000-0000-0000-000000000001',
            '70000000-0000-0000-0000-0000000000a1');

INSERT INTO patient (id, cabinet_id, first_name, last_name)
    VALUES ('70000000-0000-0000-0000-0000000000b1',
            '70000000-0000-0000-0000-000000000001', 'Claude', '700A');

INSERT INTO appointment (id, cabinet_id, patient_id, practitioner_id,
                         starts_at, ends_at, status)
    VALUES ('70000000-0000-0000-0000-0000000000d1',
            '70000000-0000-0000-0000-000000000001',
            '70000000-0000-0000-0000-0000000000b1',
            '70000000-0000-0000-0000-0000000000c1',
            '2026-07-01 09:00:00+00', '2026-07-01 10:00:00+00',
            'in_progress');

-- Statut valide : in_progress (défaut)
SELECT lives_ok(
    $$ INSERT INTO consultation_session
           (id, cabinet_id, appointment_id, practitioner_id)
       VALUES (
           '70000000-0000-0000-0000-0000000000e1',
           '70000000-0000-0000-0000-000000000001',
           '70000000-0000-0000-0000-0000000000d1',
           '70000000-0000-0000-0000-0000000000c1'
       ) $$,
    'consultation_session : INSERT avec statut défaut in_progress OK');

-- Vérification que le statut par défaut est bien 'in_progress'
SELECT is(
    (SELECT status FROM consultation_session
     WHERE id = '70000000-0000-0000-0000-0000000000e1'),
    'in_progress',
    'consultation_session : statut défaut = in_progress');

-- Statut valide : completed
SELECT lives_ok(
    $$ UPDATE consultation_session
       SET status = 'completed', completed_at = now()
       WHERE id = '70000000-0000-0000-0000-0000000000e1' $$,
    'consultation_session : UPDATE vers completed OK');

-- Statut valide : cancelled
SELECT lives_ok(
    $$ UPDATE consultation_session
       SET status = 'cancelled'
       WHERE id = '70000000-0000-0000-0000-0000000000e1' $$,
    'consultation_session : UPDATE vers cancelled OK');

-- Statut invalide : refusé par CHECK
SELECT throws_ok(
    $$ UPDATE consultation_session
       SET status = 'pending'
       WHERE id = '70000000-0000-0000-0000-0000000000e1' $$,
    '23514', NULL,
    '⭐ contrainte CHECK statut : valeur invalide refusée');

-- ===========================================================================
-- 5. RLS : fail-closed + non-fuite inter-cabinet + WITH CHECK
-- ===========================================================================

-- Cabinet 700-B pour les tests cross-tenant
SET LOCAL app.current_cabinet_id = '70000000-0000-0000-0000-000000000002';
INSERT INTO cabinet (id, raison_sociale)
    VALUES ('70000000-0000-0000-0000-000000000002', 'Cabinet 700-B');

-- Fail-closed : sans GUC → 0 session visible
RESET app.current_cabinet_id;
SELECT is(
    (SELECT count(*)::int FROM consultation_session
     WHERE id = '70000000-0000-0000-0000-0000000000e1'),
    0,
    '⭐ fail-closed : aucune session visible sans app.current_cabinet_id');

-- Même-tenant : contexte 700-A → session visible
SET LOCAL app.current_cabinet_id = '70000000-0000-0000-0000-000000000001';
SELECT is(
    (SELECT count(*)::int FROM consultation_session
     WHERE cabinet_id = '70000000-0000-0000-0000-000000000001'),
    1,
    'contexte 700-A : 1 session visible dans le bon cabinet');

-- Non-fuite : contexte 700-B → 0 session de 700-A
SET LOCAL app.current_cabinet_id = '70000000-0000-0000-0000-000000000002';
SELECT is(
    (SELECT count(*)::int FROM consultation_session
     WHERE cabinet_id = '70000000-0000-0000-0000-000000000001'),
    0,
    '⭐ non-fuite : contexte 700-B ne voit aucune session du cabinet 700-A');

-- WITH CHECK : insertion cross-tenant refusée
SELECT throws_ok(
    $$ INSERT INTO consultation_session
           (cabinet_id, appointment_id, practitioner_id)
       VALUES (
           '70000000-0000-0000-0000-000000000001',
           '70000000-0000-0000-0000-0000000000d1',
           '70000000-0000-0000-0000-0000000000c1'
       ) $$,
    '42501', NULL,
    '⭐ WITH CHECK : insertion consultation_session cross-tenant refusée');

SELECT * FROM finish();
ROLLBACK;
