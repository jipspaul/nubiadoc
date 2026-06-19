-- 33_appointment_strong.sql — TDD audit pgTAP Appointment scheduling integrity.
-- Issue #1832 — T-DB-D006.
--
-- Invariants couverts :
--   FORCE1. appointment : FORCE ROW LEVEL SECURITY activée.
--   FORCE2. appointment : policy tenant_isolation présente.
--   AR1.    appointment : fail-closed sans app.current_cabinet_id.
--   AR2a.   appointment : contexte A → 1 RDV visible (même-tenant).
--   AR2b.   appointment : contexte A → 0 RDV de B visible (non-fuite).
--   AR3.    appointment : WITH CHECK — insertion cross-tenant refusée (42501).
--   AC1.    EXCLUDE anti-double-booking : créneau chevauchant rejeté (23P01).
--   AC2.    EXCLUDE : créneau cancelled sur même slot accepté (clause WHERE).
--   AC3.    checkin_method CHECK : valeur invalide rejetée (23514).
--   AC4a.   idempotency_key UNIQUE partiel : première insertion acceptée.
--   AC4b.   idempotency_key UNIQUE partiel : doublon cabinet rejeté (23505).
--   AC5.    callback_requested_at : mise à jour timestamptz acceptée.
--   AC5b.   callback_requested_at : valeur persistée correctement.
--   AC6.    cancelled_at : soft-delete (status + cancelled_at) accepté.
--
-- Exécuté par pg_prove sous nubia_app (NOSUPERUSER, NOBYPASSRLS).
-- Fixtures auto-containées (BEGIN…ROLLBACK). Préfixe UUID 18320000.

BEGIN;
SELECT * FROM no_plan();

-- ===========================================================================
-- Pré-conditions : rôle et attributs RLS
-- ===========================================================================
SELECT is(current_user::text, 'nubia_app',
    '⭐ tests appointment_strong exécutés sous nubia_app');

SELECT ok(NOT (SELECT rolbypassrls FROM pg_roles WHERE rolname = 'nubia_app'),
    '⭐ nubia_app NOBYPASSRLS confirmé');

-- ===========================================================================
-- FORCE1. FORCE ROW LEVEL SECURITY activée sur appointment
-- ===========================================================================
SELECT ok(
    (SELECT relforcerowsecurity FROM pg_class WHERE relname = 'appointment'),
    'FORCE1 appointment : FORCE ROW LEVEL SECURITY activée');

-- ===========================================================================
-- FORCE2. Policy tenant_isolation présente sur appointment
-- ===========================================================================
SELECT ok(
    EXISTS(SELECT 1 FROM pg_policies
           WHERE tablename  = 'appointment'
             AND policyname = 'tenant_isolation'),
    'FORCE2 appointment : policy tenant_isolation présente');

-- ===========================================================================
-- Fixtures : 2 cabinets, 2 praticiens, 2 patients, 1 RDV chacun.
-- Préfixe UUID 18320000 (propre à cette suite, hors des autres fixtures seed/tests).
-- ===========================================================================

-- Cabinet A
SET LOCAL app.current_cabinet_id = '18320000-0000-0000-0000-000000000001';
INSERT INTO cabinet (id, raison_sociale)
    VALUES ('18320000-0000-0000-0000-000000000001', 'Cabinet Appt-Strong-A');

INSERT INTO app_user (id, email, password_hash, kind)
    VALUES ('18320000-0000-0000-0000-0000000000a1', 'prat.1832a@nubia.test', '$argon2id$fixture', 'pro');

INSERT INTO practitioner (id, cabinet_id, user_id)
    VALUES ('18320000-0000-0000-0000-0000000000b1',
            '18320000-0000-0000-0000-000000000001',
            '18320000-0000-0000-0000-0000000000a1');

INSERT INTO patient (id, cabinet_id, first_name, last_name)
    VALUES ('18320000-0000-0000-0000-0000000000c1',
            '18320000-0000-0000-0000-000000000001', 'Alice', 'Scheduling');

INSERT INTO appointment (id, cabinet_id, patient_id, practitioner_id,
                         starts_at, ends_at, status)
    VALUES ('18320000-0000-0000-0000-0000000000d1',
            '18320000-0000-0000-0000-000000000001',
            '18320000-0000-0000-0000-0000000000c1',
            '18320000-0000-0000-0000-0000000000b1',
            '2027-06-20 09:00+00', '2027-06-20 09:30+00', 'confirmed');

-- Cabinet B
SET LOCAL app.current_cabinet_id = '18320000-0000-0000-0000-000000000002';
INSERT INTO cabinet (id, raison_sociale)
    VALUES ('18320000-0000-0000-0000-000000000002', 'Cabinet Appt-Strong-B');

INSERT INTO app_user (id, email, password_hash, kind)
    VALUES ('18320000-0000-0000-0000-0000000000a2', 'prat.1832b@nubia.test', '$argon2id$fixture', 'pro');

INSERT INTO practitioner (id, cabinet_id, user_id)
    VALUES ('18320000-0000-0000-0000-0000000000b2',
            '18320000-0000-0000-0000-000000000002',
            '18320000-0000-0000-0000-0000000000a2');

INSERT INTO patient (id, cabinet_id, first_name, last_name)
    VALUES ('18320000-0000-0000-0000-0000000000c2',
            '18320000-0000-0000-0000-000000000002', 'Bob', 'Scheduling');

INSERT INTO appointment (id, cabinet_id, patient_id, practitioner_id,
                         starts_at, ends_at, status)
    VALUES ('18320000-0000-0000-0000-0000000000d2',
            '18320000-0000-0000-0000-000000000002',
            '18320000-0000-0000-0000-0000000000c2',
            '18320000-0000-0000-0000-0000000000b2',
            '2027-06-20 09:00+00', '2027-06-20 09:30+00', 'confirmed');

-- ===========================================================================
-- AR1. FAIL-CLOSED : sans GUC → 0 RDV visible
-- ===========================================================================
RESET app.current_cabinet_id;
SELECT is(
    (SELECT count(*)::int FROM appointment
     WHERE id IN ('18320000-0000-0000-0000-0000000000d1',
                  '18320000-0000-0000-0000-0000000000d2')),
    0,
    '⭐ AR1 fail-closed appointment : aucun RDV visible sans app.current_cabinet_id');

-- ===========================================================================
-- AR2. ISOLATION : contexte A → 1 RDV propre, 0 RDV de B
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '18320000-0000-0000-0000-000000000001';
SELECT is(
    (SELECT count(*)::int FROM appointment
     WHERE cabinet_id = '18320000-0000-0000-0000-000000000001'),
    1,
    'AR2a contexte A : 1 RDV visible (cabinet A)');

SELECT is(
    (SELECT count(*)::int FROM appointment
     WHERE cabinet_id = '18320000-0000-0000-0000-000000000002'),
    0,
    '⭐ AR2b non-fuite appointment : contexte A ne voit PAS les RDV de B');

-- ===========================================================================
-- AR3. WITH CHECK : insertion cross-tenant refusée (contexte B, cible cabinet A)
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '18320000-0000-0000-0000-000000000002';
SELECT throws_ok(
    $$ INSERT INTO appointment (cabinet_id, patient_id, practitioner_id,
                                starts_at, ends_at, status)
       VALUES (
           '18320000-0000-0000-0000-000000000001',
           '18320000-0000-0000-0000-0000000000c1',
           '18320000-0000-0000-0000-0000000000b1',
           '2027-06-21 10:00+00', '2027-06-21 10:30+00', 'confirmed'
       ) $$,
    '42501', NULL,
    '⭐ AR3 WITH CHECK appointment : insertion cross-tenant (B→A) refusée');

-- ===========================================================================
-- AC1. EXCLUDE anti-double-booking : créneau chevauchant rejeté (contexte A)
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '18320000-0000-0000-0000-000000000001';
SELECT throws_ok(
    $$ INSERT INTO appointment (cabinet_id, patient_id, practitioner_id,
                                starts_at, ends_at, status)
       VALUES (
           '18320000-0000-0000-0000-000000000001',
           '18320000-0000-0000-0000-0000000000c1',
           '18320000-0000-0000-0000-0000000000b1',
           '2027-06-20 09:15+00', '2027-06-20 09:45+00', 'confirmed'
       ) $$,
    '23P01', NULL,
    '⭐ AC1 EXCLUDE anti-double-booking : créneau chevauchant (09:15-09:45) rejeté');

-- ===========================================================================
-- AC2. EXCLUDE : créneau cancelled sur même plage accepté (clause WHERE exclus)
-- ===========================================================================
SELECT lives_ok(
    $$ INSERT INTO appointment (cabinet_id, patient_id, practitioner_id,
                                starts_at, ends_at, status)
       VALUES (
           '18320000-0000-0000-0000-000000000001',
           '18320000-0000-0000-0000-0000000000c1',
           '18320000-0000-0000-0000-0000000000b1',
           '2027-06-20 09:10+00', '2027-06-20 09:25+00', 'cancelled'
       ) $$,
    'AC2 EXCLUDE : RDV cancelled sur créneau occupé accepté (hors contrainte EXCLUDE)');

-- ===========================================================================
-- AC3. checkin_method CHECK : valeur hors ('qr','geo','manual') rejetée (0030)
-- ===========================================================================
SELECT throws_ok(
    $$ INSERT INTO appointment (cabinet_id, patient_id, practitioner_id,
                                starts_at, ends_at, status, checkin_method)
       VALUES (
           '18320000-0000-0000-0000-000000000001',
           '18320000-0000-0000-0000-0000000000c1',
           '18320000-0000-0000-0000-0000000000b1',
           '2027-06-22 09:00+00', '2027-06-22 09:30+00', 'confirmed',
           'telepathie'
       ) $$,
    '23514', NULL,
    '⭐ AC3 checkin_method CHECK : valeur invalide rejetée (23514)');

-- ===========================================================================
-- AC4. idempotency_key UNIQUE partiel (cabinet_id, idempotency_key) — 0068
-- ===========================================================================
SELECT lives_ok(
    $$ INSERT INTO appointment (id, cabinet_id, patient_id, practitioner_id,
                                starts_at, ends_at, status, idempotency_key)
       VALUES (
           '18320000-0000-0000-0000-0000000000d3',
           '18320000-0000-0000-0000-000000000001',
           '18320000-0000-0000-0000-0000000000c1',
           '18320000-0000-0000-0000-0000000000b1',
           '2027-06-23 09:00+00', '2027-06-23 09:30+00', 'confirmed',
           'idem-key-1832'
       ) $$,
    'AC4a idempotency_key : première insertion avec clé acceptée');

SELECT throws_ok(
    $$ INSERT INTO appointment (cabinet_id, patient_id, practitioner_id,
                                starts_at, ends_at, status, idempotency_key)
       VALUES (
           '18320000-0000-0000-0000-000000000001',
           '18320000-0000-0000-0000-0000000000c1',
           '18320000-0000-0000-0000-0000000000b1',
           '2027-06-24 09:00+00', '2027-06-24 09:30+00', 'confirmed',
           'idem-key-1832'
       ) $$,
    '23505', NULL,
    '⭐ AC4b idempotency_key UNIQUE partiel : doublon dans le même cabinet rejeté (23505)');

-- ===========================================================================
-- AC5. callback_requested_at : colonne timestamptz nullable, mise à jour OK (0067)
-- ===========================================================================
SELECT lives_ok(
    $$ UPDATE appointment
       SET callback_requested_at = '2027-06-20 08:00+00'
       WHERE id = '18320000-0000-0000-0000-0000000000d1' $$,
    'AC5 callback_requested_at : mise à jour timestamptz acceptée');

SELECT is(
    (SELECT callback_requested_at FROM appointment
     WHERE id = '18320000-0000-0000-0000-0000000000d1'),
    '2027-06-20 08:00:00+00'::timestamptz,
    'AC5b callback_requested_at : valeur persistée correctement');

-- ===========================================================================
-- AC6. cancelled_at : soft-delete (status + cancelled_at) accepté (0031)
-- ===========================================================================
SELECT lives_ok(
    $$ UPDATE appointment
       SET cancelled_at = '2027-06-20 07:00+00',
           status       = 'cancelled'
       WHERE id = '18320000-0000-0000-0000-0000000000d1' $$,
    'AC6 cancelled_at : soft-delete (cancelled_at + status=cancelled) accepté');

SELECT * FROM finish();
ROLLBACK;
