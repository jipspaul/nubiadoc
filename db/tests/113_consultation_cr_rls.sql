-- 113_consultation_cr_rls.sql
-- pgTAP : RLS consultation_cr (CR structuré, #7154, migration 0297).
--   CR1. Le cabinet A voit son propre brouillon de CR structuré.
--   CR2. RLS tenant : cabinet B ne voit PAS le CR structuré de A.
--   CR3. Fail-closed : sans GUC app.current_cabinet_id → 0 ligne.
-- Exécuté par pg_prove sous nubia_app (NOSUPERUSER, NOBYPASSRLS).
-- Fixtures auto-contenues (BEGIN…ROLLBACK). Préfixe UUID 71540000.
-- Issue : #7154

BEGIN;
SELECT plan(3);

-- ===========================================================================
-- Fixtures : 2 cabinets, 1 praticien/patient/RDV par cabinet, 1 CR structuré
-- brouillon pour le cabinet A.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '71540000-0000-0000-0000-000000000c01';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('71540000-0000-0000-0000-000000000c01', 'Cabinet ConsultationCr-7154-A');
RESET app.current_cabinet_id;

SET LOCAL app.current_cabinet_id = '71540000-0000-0000-0000-000000000c02';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('71540000-0000-0000-0000-000000000c02', 'Cabinet ConsultationCr-7154-B');
RESET app.current_cabinet_id;

SET LOCAL app.current_cabinet_id = '71540000-0000-0000-0000-000000000c01';

INSERT INTO app_user (id, email, password_hash, kind) VALUES
  ('71540000-0000-0000-0000-000000000a01', 'prat.7154@nubia.test', '$argon2id$fixture', 'pro');

INSERT INTO practitioner (id, cabinet_id, user_id) VALUES
  ('71540000-0000-0000-0000-000000000d01',
   '71540000-0000-0000-0000-000000000c01',
   '71540000-0000-0000-0000-000000000a01');

INSERT INTO patient (id, cabinet_id, first_name, last_name) VALUES
  ('71540000-0000-0000-0000-000000000030',
   '71540000-0000-0000-0000-000000000c01', 'Patient', 'ConsultationCr7154');

INSERT INTO appointment (id, cabinet_id, patient_id, practitioner_id,
                         starts_at, ends_at, status) VALUES
  ('71540000-0000-0000-0000-000000000050',
   '71540000-0000-0000-0000-000000000c01',
   '71540000-0000-0000-0000-000000000030',
   '71540000-0000-0000-0000-000000000d01',
   now() - interval '1 hour', now(), 'in_progress');

INSERT INTO consultation_cr (id, cabinet_id, appointment_id, practitioner_id, status) VALUES
  ('71540000-0000-0000-0000-000000000060',
   '71540000-0000-0000-0000-000000000c01',
   '71540000-0000-0000-0000-000000000050',
   '71540000-0000-0000-0000-000000000d01',
   'draft');

-- ===========================================================================
-- CR1. Le cabinet A voit son propre brouillon.
-- ===========================================================================
SELECT is(
  (SELECT count(*)::int FROM consultation_cr
   WHERE id = '71540000-0000-0000-0000-000000000060'),
  1,
  'CR1 consultation_cr : le cabinet A voit son propre brouillon de CR structuré');

-- ===========================================================================
-- CR2. RLS : cabinet B ne voit PAS le CR structuré de A.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '71540000-0000-0000-0000-000000000c02';
SELECT is(
  (SELECT count(*)::int FROM consultation_cr
   WHERE id = '71540000-0000-0000-0000-000000000060'),
  0,
  '⭐ CR2 tenant_isolation : cabinet B ne voit PAS le CR structuré de A');

-- ===========================================================================
-- CR3. Fail-closed : sans GUC → 0 ligne visible.
-- ===========================================================================
RESET app.current_cabinet_id;
SELECT is(
  (SELECT count(*)::int FROM consultation_cr),
  0,
  '⭐ CR3 consultation_cr : fail-closed, 0 ligne sans GUC positionné');

SELECT * FROM finish();
ROLLBACK;
