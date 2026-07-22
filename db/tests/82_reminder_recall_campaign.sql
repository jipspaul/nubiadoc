-- 82_reminder_recall_campaign.sql
-- pgTAP : rappels de campagne sans RDV associé (#4150, migration 0194).
--   RC1. appointment_id NULL + kind='recall_annual' réussit.
--   RC2. appointment_id NULL + kind='recall_detartrage' réussit.
--   RC3. kind hors énum toujours refusé (23514, non-régression).
--   RC4. RLS : cabinet B ne voit PAS le rappel de campagne de A.
--   RC5. Fail-closed : sans GUC → 0 ligne.
-- Exécuté par pg_prove sous nubia_app (NOSUPERUSER, NOBYPASSRLS).
-- Fixtures auto-contenues (BEGIN…ROLLBACK). Préfixe UUID 41500000.
-- Issue : #4150

BEGIN;
SELECT plan(5);

-- ===========================================================================
-- Fixtures : 2 cabinets, chacun avec un patient (aucun appointment requis —
-- c'est précisément le cas d'usage de #4150).
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '41500000-0000-0000-0000-000000000c01';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('41500000-0000-0000-0000-000000000c01', 'Cabinet Recall-4150-A');
INSERT INTO patient (id, cabinet_id, first_name, last_name) VALUES
  ('41500000-0000-0000-0000-0000000000e1', '41500000-0000-0000-0000-000000000c01',
   'Patient', 'RecallA');
RESET app.current_cabinet_id;

SET LOCAL app.current_cabinet_id = '41500000-0000-0000-0000-000000000c02';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('41500000-0000-0000-0000-000000000c02', 'Cabinet Recall-4150-B');
RESET app.current_cabinet_id;

-- ===========================================================================
-- RC1. appointment_id NULL + kind='recall_annual' réussit.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '41500000-0000-0000-0000-000000000c01';
INSERT INTO reminder (id, cabinet_id, appointment_id, patient_id, scheduled_at, kind) VALUES
  ('41500000-0000-0000-0000-000000000d01', '41500000-0000-0000-0000-000000000c01',
   NULL, '41500000-0000-0000-0000-0000000000e1', now() + interval '30 days', 'recall_annual');
SELECT is(
  (SELECT count(*)::int FROM reminder
   WHERE id = '41500000-0000-0000-0000-000000000d01' AND appointment_id IS NULL),
  1,
  '⭐ RC1 reminder : campagne recall_annual sans appointment_id réussit');

-- ===========================================================================
-- RC2. appointment_id NULL + kind='recall_detartrage' réussit.
-- ===========================================================================
INSERT INTO reminder (id, cabinet_id, appointment_id, patient_id, scheduled_at, kind) VALUES
  ('41500000-0000-0000-0000-000000000d02', '41500000-0000-0000-0000-000000000c01',
   NULL, '41500000-0000-0000-0000-0000000000e1', now() + interval '180 days', 'recall_detartrage');
SELECT is(
  (SELECT count(*)::int FROM reminder
   WHERE id = '41500000-0000-0000-0000-000000000d02' AND appointment_id IS NULL),
  1,
  '⭐ RC2 reminder : campagne recall_detartrage sans appointment_id réussit');

-- ===========================================================================
-- RC3. kind hors énum toujours refusé (23514, non-régression).
-- ===========================================================================
SELECT throws_ok(
  $$ INSERT INTO reminder (cabinet_id, patient_id, scheduled_at, kind)
     VALUES ('41500000-0000-0000-0000-000000000c01',
             '41500000-0000-0000-0000-0000000000e1', now(), 'invalide') $$,
  '23514', NULL,
  'RC3 reminder_kind_check : kind hors énum toujours refusé (23514)');

-- ===========================================================================
-- RC4. RLS : cabinet B ne voit PAS le rappel de campagne de A.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '41500000-0000-0000-0000-000000000c02';
SELECT is(
  (SELECT count(*)::int FROM reminder
   WHERE id IN ('41500000-0000-0000-0000-000000000d01', '41500000-0000-0000-0000-000000000d02')),
  0,
  '⭐ RC4 tenant_isolation : cabinet B ne voit PAS les rappels de campagne de A');

-- ===========================================================================
-- RC5. Fail-closed : sans GUC → 0 ligne.
-- ===========================================================================
RESET app.current_cabinet_id;
SELECT is(
  (SELECT count(*)::int FROM reminder
   WHERE id IN ('41500000-0000-0000-0000-000000000d01', '41500000-0000-0000-0000-000000000d02')),
  0,
  '⭐ RC5 fail-closed : 0 ligne sans GUC positionné');

SELECT * FROM finish();
ROLLBACK;
