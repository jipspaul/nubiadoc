-- 21_marketplace_rls.sql — RLS publique availability_slot + review (issue #825).
-- pgTAP. Exécuté par pg_prove sous nubia_app. Réf. docs/05 §9.2-§9.3, migration 0059.
BEGIN;
SELECT plan(16);

-- ===========================================================================
-- 1. RLS activée et forcée sur availability_slot
-- ===========================================================================
SELECT ok( (SELECT relrowsecurity FROM pg_class WHERE relname='availability_slot'),
  'availability_slot : ROW LEVEL SECURITY activée');
SELECT ok( (SELECT relforcerowsecurity FROM pg_class WHERE relname='availability_slot'),
  'availability_slot : FORCE ROW LEVEL SECURITY activée');

-- ===========================================================================
-- 2. RLS activée et forcée sur review
-- ===========================================================================
SELECT ok( (SELECT relrowsecurity FROM pg_class WHERE relname='review'),
  'review : ROW LEVEL SECURITY activée');
SELECT ok( (SELECT relforcerowsecurity FROM pg_class WHERE relname='review'),
  'review : FORCE ROW LEVEL SECURITY activée');

-- ===========================================================================
-- 3. Policies de lecture publique présentes
-- ===========================================================================
SELECT ok(
  EXISTS(SELECT 1 FROM pg_policies WHERE tablename='availability_slot' AND policyname='slot_public_read'),
  'availability_slot : policy slot_public_read présente');
SELECT ok(
  EXISTS(SELECT 1 FROM pg_policies WHERE tablename='availability_slot' AND policyname='slot_app_insert'),
  'availability_slot : policy slot_app_insert présente');
SELECT ok(
  EXISTS(SELECT 1 FROM pg_policies WHERE tablename='review' AND policyname='review_public_read'),
  'review : policy review_public_read présente');
SELECT ok(
  EXISTS(SELECT 1 FROM pg_policies WHERE tablename='review' AND policyname='review_app_insert'),
  'review : policy review_app_insert présente');

-- ===========================================================================
-- 4. Fixtures : un provider fictif + patient_account pour les tests
-- ===========================================================================
-- On injecte le contexte cabinet pour pouvoir créer le provider (policy provider_cabinet_manage).
SET LOCAL app.current_cabinet_id = 'f1111111-0000-0000-0000-000000000000';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('f1111111-0000-0000-0000-000000000000', 'Cabinet Test RLS 825');

INSERT INTO app_user (id, email, password_hash, kind) VALUES
  ('f2111111-0000-0000-0000-000000000001', 'provider.rls825@test.local', 'FIXTURE', 'pro');

INSERT INTO provider (id, cabinet_id, user_id, display_name, rpps_verified, is_listed) VALUES
  ('f3111111-0000-0000-0000-000000000001', 'f1111111-0000-0000-0000-000000000000',
   'f2111111-0000-0000-0000-000000000001', 'Dr RLS Test 825', true, true);

INSERT INTO app_user (id, email, password_hash, kind) VALUES
  ('f2111111-0000-0000-0000-000000000002', 'patient.rls825@test.local', 'FIXTURE', 'patient');

INSERT INTO patient_account (id, app_user_id, first_name, last_name) VALUES
  ('f4111111-0000-0000-0000-000000000001', 'f2111111-0000-0000-0000-000000000002', 'Patient', 'RLS825');

-- Créneaux : 1 open, 1 held, 1 booked
INSERT INTO availability_slot (id, provider_id, starts_at, ends_at, motif, status) VALUES
  ('f5111111-0000-0000-0000-000000000001', 'f3111111-0000-0000-0000-000000000001',
   now() + interval '1 day', now() + interval '1 day' + interval '30 min', 'Test', 'open'),
  ('f5111111-0000-0000-0000-000000000002', 'f3111111-0000-0000-0000-000000000001',
   now() + interval '2 days', now() + interval '2 days' + interval '30 min', 'Test', 'held'),
  ('f5111111-0000-0000-0000-000000000003', 'f3111111-0000-0000-0000-000000000001',
   now() + interval '3 days', now() + interval '3 days' + interval '30 min', 'Test', 'booked');

-- Avis : 1 published, 1 pending, 1 rejected
INSERT INTO review (id, provider_id, patient_account_id, rating, comment, status, created_at) VALUES
  ('f6111111-0000-0000-0000-000000000001', 'f3111111-0000-0000-0000-000000000001',
   'f4111111-0000-0000-0000-000000000001', 5, 'Excellent', 'published', now()),
  ('f6111111-0000-0000-0000-000000000002', 'f3111111-0000-0000-0000-000000000001',
   'f4111111-0000-0000-0000-000000000001', 3, 'En attente', 'pending', now()),
  ('f6111111-0000-0000-0000-000000000003', 'f3111111-0000-0000-0000-000000000001',
   'f4111111-0000-0000-0000-000000000001', 1, 'Rejeté', 'rejected', now());

-- ===========================================================================
-- 5. Lecture publique availability_slot : seuls les 'open' visibles
-- ===========================================================================
RESET app.current_cabinet_id;

SELECT is(
  (SELECT count(*)::int FROM availability_slot
   WHERE id IN (
     'f5111111-0000-0000-0000-000000000001',
     'f5111111-0000-0000-0000-000000000002',
     'f5111111-0000-0000-0000-000000000003'
   )),
  1,
  '⭐ slot public-read : seul le slot open (1/3) est visible');

SELECT is(
  (SELECT count(*)::int FROM availability_slot
   WHERE id = 'f5111111-0000-0000-0000-000000000001' AND status = 'open'),
  1,
  'slot open visible en lecture publique');

SELECT is(
  (SELECT count(*)::int FROM availability_slot
   WHERE id = 'f5111111-0000-0000-0000-000000000002'),
  0,
  '⭐ slot held invisible (non-public)');

SELECT is(
  (SELECT count(*)::int FROM availability_slot
   WHERE id = 'f5111111-0000-0000-0000-000000000003'),
  0,
  '⭐ slot booked invisible (non-public)');

-- ===========================================================================
-- 6. Lecture publique review : seuls les 'published' visibles
-- ===========================================================================
SELECT is(
  (SELECT count(*)::int FROM review
   WHERE id IN (
     'f6111111-0000-0000-0000-000000000001',
     'f6111111-0000-0000-0000-000000000002',
     'f6111111-0000-0000-0000-000000000003'
   )),
  1,
  '⭐ review public-read : seul l''avis published (1/3) est visible');

SELECT is(
  (SELECT count(*)::int FROM review
   WHERE id = 'f6111111-0000-0000-0000-000000000001' AND status = 'published'),
  1,
  'review published visible en lecture publique');

SELECT is(
  (SELECT count(*)::int FROM review
   WHERE id = 'f6111111-0000-0000-0000-000000000002'),
  0,
  '⭐ review pending invisible (non-public)');

SELECT is(
  (SELECT count(*)::int FROM review
   WHERE id = 'f6111111-0000-0000-0000-000000000003'),
  0,
  '⭐ review rejected invisible (non-public)');

SELECT finish();
ROLLBACK;
