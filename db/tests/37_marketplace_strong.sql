-- 37_marketplace_strong.sql -- TDD audit pgTAP : Marketplace search + booking holds (approfondi).
-- Issue #1833 -- T-DB-D007.
--
-- Invariants couverts (complementaires a 07_marketplace_slots_reviews.sql
-- et 21_marketplace_rls.sql) :
--   PRE1.  execute sous nubia_app (NOSUPERUSER).
--   PRE2.  nubia_app NOBYPASSRLS confirme.
--   FORCE1. slot_holds : FORCE ROW LEVEL SECURITY activee (0095).
--   POL1.  slot_holds_app : policy presente (0095).
--   FN1.   try_claim_slot : fonction presente dans le schema public (0095).
--   C1.    review rating > 5 : CHECK rejete (23514).
--   C2.    review rating < 1 : CHECK rejete (23514).
--   C3.    availability_slot status invalide : CHECK rejete (23514).
--   C4.    availability_slot ends_at <= starts_at : CHECK rejete (23514).
--   C5.    provider is_listed=true + rpps_verified=false : CHECK rejete (23514).
--   C6.    slot_holds UNIQUE(slot_id) : double hold sur meme slot rejete (23505).
--   C7.    review idempotency_key UNIQUE partiel : doublon (patient_account_id, key) rejete (23505).
--   N1.    try_claim_slot sur slot open → retourne 'held'.
--   N2.    slot n'est plus visible via SELECT apres claim (status=held, non-public).
--   N3.    try_claim_slot sur UUID inexistant → NULL (404).
--   N4.    try_claim_slot sur slot deja held → retourne 'held' (pas de double-transition, 409).
--   N5.    review patient_read : avis pending visible avec GUC patient_account_id correct.
--   N6.    review pending invisible sans GUC (review_public_read = published seulement).
--
-- Execute par pg_prove sous nubia_app (NOSUPERUSER, NOBYPASSRLS).
-- Fixtures auto-contenues (BEGIN...ROLLBACK). Prefixe UUID 18330000.

BEGIN;
SELECT * FROM no_plan();

-- ===========================================================================
-- Pre-conditions : role et attributs RLS
-- ===========================================================================
SELECT is(current_user::text, 'nubia_app',
    'PRE1 marketplace_strong : execute sous nubia_app');

SELECT ok(NOT (SELECT rolbypassrls FROM pg_roles WHERE rolname = 'nubia_app'),
    'PRE2 nubia_app NOBYPASSRLS confirme');

-- ===========================================================================
-- FORCE1. FORCE ROW LEVEL SECURITY activee sur slot_holds (0095)
-- ===========================================================================
SELECT ok(
    (SELECT relforcerowsecurity FROM pg_class WHERE relname = 'slot_holds'),
    'FORCE1 slot_holds : FORCE ROW LEVEL SECURITY activee (0095)');

-- ===========================================================================
-- POL1. Policy slot_holds_app presente (0095)
-- ===========================================================================
SELECT ok(
    EXISTS(SELECT 1 FROM pg_policies
           WHERE tablename  = 'slot_holds'
             AND policyname = 'slot_holds_app'),
    'POL1 slot_holds : policy slot_holds_app presente (0095)');

-- ===========================================================================
-- FN1. try_claim_slot : fonction presente dans le schema public (0095)
-- ===========================================================================
SELECT ok(
    EXISTS(SELECT 1 FROM pg_proc p
           JOIN pg_namespace n ON n.oid = p.pronamespace
           WHERE n.nspname = 'public' AND p.proname = 'try_claim_slot'),
    'FN1 try_claim_slot : fonction presente dans le schema public (0095)');

-- ===========================================================================
-- Fixtures : cabinet, provider, slots, patient_account, app_user.
-- Prefixe UUID 18330000 (propre a cette suite, hors des autres fixtures).
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '18330000-0000-0000-0000-000000000001';

INSERT INTO cabinet (id, raison_sociale)
    VALUES ('18330000-0000-0000-0000-000000000001', 'Cabinet Marketplace Strong');

-- Compte pro : proprietaire du profil provider
INSERT INTO app_user (id, email, password_hash, kind)
    VALUES ('18330000-0000-0000-0000-0000000000a1',
            'dr.strong1833@nubia.test', '$argon2id$fixture', 'pro');

-- Compte patient : titulaire des slot_holds
INSERT INTO app_user (id, email, password_hash, kind)
    VALUES ('18330000-0000-0000-0000-0000000000a2',
            'pat.strong1833@nubia.test', '$argon2id$fixture', 'patient');

-- Provider liste (rpps_verified=true, is_listed=true — regle 0058)
INSERT INTO provider (id, cabinet_id, user_id, display_name, rpps_verified, is_listed)
    VALUES ('18330000-0000-0000-0000-0000000000e1',
            '18330000-0000-0000-0000-000000000001',
            '18330000-0000-0000-0000-0000000000a1',
            'Dr Marketplace Strong', true, true);

-- Compte patient plateforme (auteur des reviews)
-- app_user_id NOT NULL (contrainte ajoutee post-0009) → l'app_user patient existe deja.
INSERT INTO patient_account (id, app_user_id, first_name, last_name)
    VALUES ('18330000-0000-0000-0000-0000000000d1',
            '18330000-0000-0000-0000-0000000000a2', 'Patient', 'Strong1833');

-- Slot ALPHA : open (sera claime par try_claim_slot dans N1-N4)
INSERT INTO availability_slot (id, provider_id, starts_at, ends_at, status)
    VALUES ('18330000-0000-0000-0000-0000000000f1',
            '18330000-0000-0000-0000-0000000000e1',
            now() + interval '1 day',
            now() + interval '1 day'  + interval '30 min',
            'open');

-- Slot BETA : open (setup pour le test de doublon slot_holds C6)
INSERT INTO availability_slot (id, provider_id, starts_at, ends_at, status)
    VALUES ('18330000-0000-0000-0000-0000000000f2',
            '18330000-0000-0000-0000-0000000000e1',
            now() + interval '2 days',
            now() + interval '2 days' + interval '30 min',
            'open');

-- Premier hold sur slot BETA (pour que le doublon de C6 soit testable)
INSERT INTO slot_holds (id, slot_id, user_id, hold_token, expires_at)
    VALUES ('18330000-0000-0000-0000-000000000100',
            '18330000-0000-0000-0000-0000000000f2',
            '18330000-0000-0000-0000-0000000000a2',
            'hold-beta-first',
            now() + interval '5 minutes');

-- Review pending (pour N5/N6 : patient_read + fail-closed sans GUC)
INSERT INTO review (id, provider_id, patient_account_id, rating, status, author_display)
    VALUES ('18330000-0000-0000-0000-000000000201',
            '18330000-0000-0000-0000-0000000000e1',
            '18330000-0000-0000-0000-0000000000d1',
            4, 'pending', 'Patient S.');

-- Review published avec idempotency_key (setup pour le doublon de C7)
INSERT INTO review (id, provider_id, patient_account_id, rating, status, author_display,
                    idempotency_key)
    VALUES ('18330000-0000-0000-0000-000000000202',
            '18330000-0000-0000-0000-0000000000e1',
            '18330000-0000-0000-0000-0000000000d1',
            5, 'published', 'Patient S.', 'idemp-mkt-1833-01');

-- ===========================================================================
-- C1. review rating > 5 : CHECK rejete (23514)
-- ===========================================================================
SELECT throws_ok(
    $$ INSERT INTO review (provider_id, patient_account_id, rating, status, author_display)
       VALUES ('18330000-0000-0000-0000-0000000000e1',
               '18330000-0000-0000-0000-0000000000d1',
               6, 'pending', 'Patient S.') $$,
    '23514', NULL,
    'C1 review : rating=6 rejete (CHECK rating BETWEEN 1 AND 5)');

-- ===========================================================================
-- C2. review rating < 1 : CHECK rejete (23514)
-- ===========================================================================
SELECT throws_ok(
    $$ INSERT INTO review (provider_id, patient_account_id, rating, status, author_display)
       VALUES ('18330000-0000-0000-0000-0000000000e1',
               '18330000-0000-0000-0000-0000000000d1',
               0, 'pending', 'Patient S.') $$,
    '23514', NULL,
    'C2 review : rating=0 rejete (CHECK rating BETWEEN 1 AND 5)');

-- ===========================================================================
-- C3. availability_slot status invalide : CHECK rejete (23514)
-- ===========================================================================
SELECT throws_ok(
    $$ INSERT INTO availability_slot (provider_id, starts_at, ends_at, status)
       VALUES ('18330000-0000-0000-0000-0000000000e1',
               now() + interval '3 days',
               now() + interval '3 days' + interval '30 min',
               'cancelled') $$,
    '23514', NULL,
    'C3 availability_slot : status=cancelled rejete (CHECK open/held/booked)');

-- ===========================================================================
-- C4. availability_slot ends_at = starts_at : CHECK rejete (23514)
-- ===========================================================================
SELECT throws_ok(
    $$ INSERT INTO availability_slot (provider_id, starts_at, ends_at, status)
       VALUES ('18330000-0000-0000-0000-0000000000e1',
               now() + interval '4 days',
               now() + interval '4 days',
               'open') $$,
    '23514', NULL,
    'C4 availability_slot : ends_at=starts_at rejete (CHECK ends_at > starts_at)');

-- ===========================================================================
-- C5. provider is_listed=true + rpps_verified=false : CHECK rejete (23514)
-- Regle metier enforced par contrainte DB (0058).
-- ===========================================================================
SELECT throws_ok(
    $$ INSERT INTO provider (cabinet_id, user_id, display_name, rpps_verified, is_listed)
       VALUES ('18330000-0000-0000-0000-000000000001',
               '18330000-0000-0000-0000-0000000000a1',
               'Dr Fraude', false, true) $$,
    '23514', NULL,
    'C5 provider : is_listed=true + rpps_verified=false rejete (CHECK 0058)');

-- ===========================================================================
-- C6. slot_holds UNIQUE(slot_id) : double hold sur slot BETA rejete (23505)
-- ===========================================================================
SELECT throws_ok(
    $$ INSERT INTO slot_holds (slot_id, user_id, hold_token, expires_at)
       VALUES ('18330000-0000-0000-0000-0000000000f2',
               '18330000-0000-0000-0000-0000000000a2',
               'hold-beta-second',
               now() + interval '5 minutes') $$,
    '23505', NULL,
    'C6 slot_holds : double hold sur meme slot rejete (UNIQUE slot_id, 0095)');

-- ===========================================================================
-- C7. review idempotency_key UNIQUE partiel : doublon (patient_account_id, key) rejete (23505)
-- ===========================================================================
SELECT throws_ok(
    $$ INSERT INTO review (provider_id, patient_account_id, rating, status, author_display,
                           idempotency_key)
       VALUES ('18330000-0000-0000-0000-0000000000e1',
               '18330000-0000-0000-0000-0000000000d1',
               5, 'published', 'Patient S.', 'idemp-mkt-1833-01') $$,
    '23505', NULL,
    'C7 review : doublon idempotency_key rejete (UNIQUE patient_account_id+key, 0076)');

-- ===========================================================================
-- N1. try_claim_slot sur slot ALPHA (open) → retourne 'held'
-- ===========================================================================
SELECT is(
    try_claim_slot('18330000-0000-0000-0000-0000000000f1'),
    'held',
    'N1 try_claim_slot : slot open → retourne held');

-- ===========================================================================
-- N2. Slot ALPHA n'est plus visible via SELECT apres claim
--     (status=held filtre par slot_public_read : USING (status = ''open''))
-- ===========================================================================
SELECT is(
    (SELECT count(*)::int FROM availability_slot
     WHERE id = '18330000-0000-0000-0000-0000000000f1'),
    0,
    'N2 try_claim_slot : slot non visible apres claim (status=held, hors slot_public_read)');

-- ===========================================================================
-- N3. try_claim_slot sur UUID inexistant → NULL (404)
-- ===========================================================================
SELECT is(
    try_claim_slot('00000000-0000-0000-0000-000000000000'),
    NULL,
    'N3 try_claim_slot : UUID inexistant → NULL');

-- ===========================================================================
-- N4. try_claim_slot sur slot ALPHA deja held → retourne 'held' sans transition (409)
-- ===========================================================================
SELECT is(
    try_claim_slot('18330000-0000-0000-0000-0000000000f1'),
    'held',
    'N4 try_claim_slot : slot deja held → retourne held (pas de double-transition, 409)');

-- ===========================================================================
-- N5. review patient_read : avis pending visible avec GUC patient_account_id correct
-- Policy review_patient_read (0076) : USING (patient_account_id = nullif(GUC, '')::uuid)
-- ===========================================================================
SET LOCAL app.patient_account_id = '18330000-0000-0000-0000-0000000000d1';

SELECT is(
    (SELECT count(*)::int FROM review
     WHERE id = '18330000-0000-0000-0000-000000000201' AND status = 'pending'),
    1,
    'N5 review patient_read : pending visible avec GUC patient_account_id correct');

-- ===========================================================================
-- N6. review pending invisible sans GUC (review_public_read = published seulement)
-- ===========================================================================
RESET app.patient_account_id;

SELECT is(
    (SELECT count(*)::int FROM review
     WHERE id = '18330000-0000-0000-0000-000000000201' AND status = 'pending'),
    0,
    'N6 review : pending invisible sans GUC (review_public_read = published only)');

SELECT * FROM finish();
ROLLBACK;
