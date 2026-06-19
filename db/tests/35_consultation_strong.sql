-- 35_consultation_strong.sql -- TDD audit pgTAP : Consultation session + acts (approfondissement).
-- Issue #1836 -- T-DB-D010.
--
-- Invariants couverts (complementaires a 08_consultation_act.sql et 22_consultation_session.sql) :
--   FORCE1. consultation_act : FORCE ROW LEVEL SECURITY activee (0042).
--   FORCE2. consultation_act : policy consultation_act_tenant_isolation presente (0042).
--   FORCE3. consultation_session : FORCE ROW LEVEL SECURITY activee (0071).
--   FORCE4. consultation_session : policy consultation_session_tenant_isolation presente (0071).
--   CA1.   amount_cents CHECK : valeur negative rejetee (23514).
--   CA2.   consultation_act : ccam_code NOT NULL (23502).
--   CA3.   consultation_act : amount_cents NOT NULL (23502).
--   CS1.   status DEFAULT 'in_progress' : valeur injectee sans specification.
--   CS2.   status CHECK : valeur invalide (ex: 'open') rejetee (23514).
--   RLS1.  consultation_act fail-closed : sans GUC, 0 acte visible.
--   RLS2.  consultation_act non-fuite : contexte B ne voit pas les actes de A.
--   RLS3.  consultation_act WITH CHECK : insertion cross-tenant refusee (42501).
--   RLS4.  consultation_session fail-closed : sans GUC, 0 session visible.
--   RLS5.  consultation_session non-fuite : contexte B ne voit pas les sessions de A.
--   RLS6.  consultation_session WITH CHECK : insertion cross-tenant refusee (42501).
--   ACT1.  acte lie a session du meme cabinet : INSERT OK (workflow nominal).
--   ACT2.  completed_at NULL sur session in_progress, non-null apres UPDATE completed.
--
-- Execute par pg_prove sous nubia_app (NOSUPERUSER, NOBYPASSRLS).
-- Fixtures auto-containees (BEGIN...ROLLBACK). Prefixe UUID 18360000.

BEGIN;
SELECT * FROM no_plan();

-- ===========================================================================
-- Pre-conditions : role et attributs RLS
-- ===========================================================================
SELECT is(current_user::text, 'nubia_app',
    '* consultation_strong : execute sous nubia_app');

SELECT ok(NOT (SELECT rolbypassrls FROM pg_roles WHERE rolname = 'nubia_app'),
    '* nubia_app NOBYPASSRLS confirme');

-- ===========================================================================
-- FORCE1. FORCE ROW LEVEL SECURITY activee sur consultation_act (0042)
-- ===========================================================================
SELECT ok(
    (SELECT relforcerowsecurity FROM pg_class WHERE relname = 'consultation_act'),
    'FORCE1 consultation_act : FORCE ROW LEVEL SECURITY activee (0042)');

-- ===========================================================================
-- FORCE2. Policy consultation_act_tenant_isolation presente (0042)
-- ===========================================================================
SELECT ok(
    EXISTS(SELECT 1 FROM pg_policies
           WHERE tablename  = 'consultation_act'
             AND policyname = 'consultation_act_tenant_isolation'),
    'FORCE2 consultation_act : policy consultation_act_tenant_isolation presente (0042)');

-- ===========================================================================
-- FORCE3. FORCE ROW LEVEL SECURITY activee sur consultation_session (0071)
-- ===========================================================================
SELECT ok(
    (SELECT relforcerowsecurity FROM pg_class WHERE relname = 'consultation_session'),
    'FORCE3 consultation_session : FORCE ROW LEVEL SECURITY activee (0071)');

-- ===========================================================================
-- FORCE4. Policy consultation_session_tenant_isolation presente (0071)
-- ===========================================================================
SELECT ok(
    EXISTS(SELECT 1 FROM pg_policies
           WHERE tablename  = 'consultation_session'
             AND policyname = 'consultation_session_tenant_isolation'),
    'FORCE4 consultation_session : policy consultation_session_tenant_isolation presente (0071)');

-- ===========================================================================
-- Fixtures : 2 cabinets A et B, praticien, patient, appointment
-- Prefixe UUID 18360000 (propre a cette suite, hors des autres fixtures).
-- ===========================================================================

INSERT INTO app_user (id, email, password_hash, kind)
    VALUES ('18360000-0000-0000-0000-0000000000a1',
            'prat.1836@nubia.test', '$argon2id$fixture', 'pro');

-- Cabinet A
SET LOCAL app.current_cabinet_id = '18360000-0000-0000-0000-000000000001';
INSERT INTO cabinet (id, raison_sociale)
    VALUES ('18360000-0000-0000-0000-000000000001', 'Cabinet Consult-Strong-A');

INSERT INTO practitioner (id, cabinet_id, user_id)
    VALUES ('18360000-0000-0000-0000-0000000000c1',
            '18360000-0000-0000-0000-000000000001',
            '18360000-0000-0000-0000-0000000000a1');

INSERT INTO patient (id, cabinet_id, first_name, last_name)
    VALUES ('18360000-0000-0000-0000-0000000000b1',
            '18360000-0000-0000-0000-000000000001', 'Alice', 'ConsultStrong');

INSERT INTO appointment (id, cabinet_id, patient_id, practitioner_id,
                         starts_at, ends_at, status)
    VALUES ('18360000-0000-0000-0000-0000000000d1',
            '18360000-0000-0000-0000-000000000001',
            '18360000-0000-0000-0000-0000000000b1',
            '18360000-0000-0000-0000-0000000000c1',
            '2026-09-01 09:00:00+00', '2026-09-01 10:00:00+00',
            'in_progress');

-- Session cabinet A
INSERT INTO consultation_session
    (id, cabinet_id, appointment_id, practitioner_id)
    VALUES ('18360000-0000-0000-0000-0000000000e1',
            '18360000-0000-0000-0000-000000000001',
            '18360000-0000-0000-0000-0000000000d1',
            '18360000-0000-0000-0000-0000000000c1');

-- Acte CCAM cabinet A
INSERT INTO consultation_act
    (id, cabinet_id, appointment_id, patient_id, practitioner_id,
     ccam_code, label, amount_cents)
    VALUES ('18360000-0000-0000-0000-0000000000f1',
            '18360000-0000-0000-0000-000000000001',
            '18360000-0000-0000-0000-0000000000d1',
            '18360000-0000-0000-0000-0000000000b1',
            '18360000-0000-0000-0000-0000000000c1',
            'HBLD001', 'Detartrage supragingival', 7500);

-- Cabinet B (pour les tests cross-tenant)
SET LOCAL app.current_cabinet_id = '18360000-0000-0000-0000-000000000002';
INSERT INTO cabinet (id, raison_sociale)
    VALUES ('18360000-0000-0000-0000-000000000002', 'Cabinet Consult-Strong-B');

-- ===========================================================================
-- CA1. amount_cents CHECK : valeur negative rejetee (23514)
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '18360000-0000-0000-0000-000000000001';
SELECT throws_ok(
    $$ INSERT INTO consultation_act
           (cabinet_id, appointment_id, patient_id, practitioner_id,
            ccam_code, label, amount_cents)
       VALUES ('18360000-0000-0000-0000-000000000001',
               '18360000-0000-0000-0000-0000000000d1',
               '18360000-0000-0000-0000-0000000000b1',
               '18360000-0000-0000-0000-0000000000c1',
               'HBLD002', 'Acte negatif', -1) $$,
    '23514', NULL,
    'CA1 consultation_act : amount_cents negatif rejete (23514)');

-- ===========================================================================
-- CA2. ccam_code NOT NULL : INSERT sans ccam_code rejete (23502)
-- ===========================================================================
SELECT throws_ok(
    $$ INSERT INTO consultation_act
           (cabinet_id, appointment_id, patient_id, practitioner_id,
            label, amount_cents)
       VALUES ('18360000-0000-0000-0000-000000000001',
               '18360000-0000-0000-0000-0000000000d1',
               '18360000-0000-0000-0000-0000000000b1',
               '18360000-0000-0000-0000-0000000000c1',
               'Sans code CCAM', 1000) $$,
    '23502', NULL,
    'CA2 consultation_act : ccam_code NOT NULL -- INSERT sans ccam_code rejete (23502)');

-- ===========================================================================
-- CA3. amount_cents NOT NULL : INSERT sans amount_cents rejete (23502)
-- ===========================================================================
SELECT throws_ok(
    $$ INSERT INTO consultation_act
           (cabinet_id, appointment_id, patient_id, practitioner_id,
            ccam_code, label)
       VALUES ('18360000-0000-0000-0000-000000000001',
               '18360000-0000-0000-0000-0000000000d1',
               '18360000-0000-0000-0000-0000000000b1',
               '18360000-0000-0000-0000-0000000000c1',
               'HBLD003', 'Sans montant') $$,
    '23502', NULL,
    'CA3 consultation_act : amount_cents NOT NULL -- INSERT sans montant rejete (23502)');

-- ===========================================================================
-- CS1. status DEFAULT 'in_progress' : verifie la valeur par defaut
-- ===========================================================================
SELECT is(
    (SELECT status FROM consultation_session
     WHERE id = '18360000-0000-0000-0000-0000000000e1'),
    'in_progress',
    'CS1 consultation_session : statut defaut = in_progress');

-- ===========================================================================
-- CS2. status CHECK : valeur invalide rejetee (23514)
-- ===========================================================================
SELECT throws_ok(
    $$ UPDATE consultation_session
       SET status = 'open'
       WHERE id = '18360000-0000-0000-0000-0000000000e1' $$,
    '23514', NULL,
    'CS2 consultation_session : status invalide open rejete (23514)');

-- ===========================================================================
-- RLS1. consultation_act fail-closed : sans GUC -> 0 acte visible
-- ===========================================================================
RESET app.current_cabinet_id;
SELECT is(
    (SELECT count(*)::int FROM consultation_act
     WHERE id = '18360000-0000-0000-0000-0000000000f1'),
    0,
    '* RLS1 consultation_act fail-closed : 0 acte sans app.current_cabinet_id');

-- ===========================================================================
-- RLS2. consultation_act non-fuite : contexte B ne voit pas les actes de A
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '18360000-0000-0000-0000-000000000002';
SELECT is(
    (SELECT count(*)::int FROM consultation_act
     WHERE cabinet_id = '18360000-0000-0000-0000-000000000001'),
    0,
    '* RLS2 consultation_act non-fuite : contexte B ne voit pas les actes du cabinet A');

-- ===========================================================================
-- RLS3. consultation_act WITH CHECK : insertion cross-tenant refusee (42501)
-- ===========================================================================
SELECT throws_ok(
    $$ INSERT INTO consultation_act
           (cabinet_id, appointment_id, patient_id, practitioner_id,
            ccam_code, label, amount_cents)
       VALUES ('18360000-0000-0000-0000-000000000001',
               '18360000-0000-0000-0000-0000000000d1',
               '18360000-0000-0000-0000-0000000000b1',
               '18360000-0000-0000-0000-0000000000c1',
               'HBLD099', 'Pirate cross-tenant', 0) $$,
    '42501', NULL,
    '* RLS3 consultation_act WITH CHECK : insertion cross-tenant (contexte B -> cabinet A) refusee (42501)');

-- ===========================================================================
-- RLS4. consultation_session fail-closed : sans GUC -> 0 session visible
-- ===========================================================================
RESET app.current_cabinet_id;
SELECT is(
    (SELECT count(*)::int FROM consultation_session
     WHERE id = '18360000-0000-0000-0000-0000000000e1'),
    0,
    '* RLS4 consultation_session fail-closed : 0 session sans app.current_cabinet_id');

-- ===========================================================================
-- RLS5. consultation_session non-fuite : contexte B ne voit pas les sessions de A
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '18360000-0000-0000-0000-000000000002';
SELECT is(
    (SELECT count(*)::int FROM consultation_session
     WHERE cabinet_id = '18360000-0000-0000-0000-000000000001'),
    0,
    '* RLS5 consultation_session non-fuite : contexte B ne voit pas les sessions du cabinet A');

-- ===========================================================================
-- RLS6. consultation_session WITH CHECK : insertion cross-tenant refusee (42501)
-- ===========================================================================
SELECT throws_ok(
    $$ INSERT INTO consultation_session
           (cabinet_id, appointment_id, practitioner_id)
       VALUES ('18360000-0000-0000-0000-000000000001',
               '18360000-0000-0000-0000-0000000000d1',
               '18360000-0000-0000-0000-0000000000c1') $$,
    '42501', NULL,
    '* RLS6 consultation_session WITH CHECK : insertion cross-tenant (contexte B -> cabinet A) refusee (42501)');

-- ===========================================================================
-- ACT1. Acte lie a session du meme cabinet : INSERT OK (workflow nominal)
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '18360000-0000-0000-0000-000000000001';
SELECT lives_ok(
    $$ INSERT INTO consultation_act
           (id, cabinet_id, appointment_id, patient_id, practitioner_id,
            ccam_code, label, amount_cents)
       VALUES ('18360000-0000-0000-0000-0000000000f2',
               '18360000-0000-0000-0000-000000000001',
               '18360000-0000-0000-0000-0000000000d1',
               '18360000-0000-0000-0000-0000000000b1',
               '18360000-0000-0000-0000-0000000000c1',
               'AMMP001', 'Consultation parodontale', 2500) $$,
    'ACT1 acte nominal : INSERT dans cabinet A OK');

-- ===========================================================================
-- ACT2. completed_at NULL sur session in_progress ; non-null apres passage completed
-- ===========================================================================
SELECT is(
    (SELECT completed_at FROM consultation_session
     WHERE id = '18360000-0000-0000-0000-0000000000e1'),
    NULL::timestamptz,
    'ACT2a consultation_session : completed_at NULL quand status=in_progress');

SELECT lives_ok(
    $$ UPDATE consultation_session
       SET status = 'completed', completed_at = now()
       WHERE id = '18360000-0000-0000-0000-0000000000e1' $$,
    'ACT2b consultation_session : passage en completed avec completed_at OK');

SELECT ok(
    (SELECT completed_at IS NOT NULL FROM consultation_session
     WHERE id = '18360000-0000-0000-0000-0000000000e1'),
    'ACT2c consultation_session : completed_at non-null apres passage completed');

SELECT * FROM finish();
ROLLBACK;
