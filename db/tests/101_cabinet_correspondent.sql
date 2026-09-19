-- 101_cabinet_correspondent.sql
-- pgTAP : cabinet_correspondent + lien patient.referred_by_correspondent_id
-- (#7195, migration 0280).
--   CC1. Un cabinet peut créer et voir son propre correspondant.
--   CC2. RLS : un autre cabinet ne voit pas ce correspondant (isolation cross-tenant).
--   CC3. Fail-closed : sans GUC app.current_cabinet_id → 0 ligne visible.
--   CC4. display_name vide (après trim) refusé par le CHECK.
--   CC5. patient.referred_by_correspondent_id : lien légitime (même cabinet) accepté.
--   CC6. FK composite : un patient ne peut pas référencer un correspondant
--        d'un AUTRE cabinet (exploit cross-tenant bloqué, 23503).
-- Exécuté par pg_prove sous nubia_app (NOSUPERUSER, NOBYPASSRLS).
-- Fixtures auto-contenues (BEGIN…ROLLBACK). Préfixe UUID 71950000.
-- Issue : #7195

BEGIN;
SELECT plan(6);

-- ===========================================================================
-- Fixtures : 2 cabinets (A, B), 1 correspondant dans le cabinet A.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '71950000-0000-0000-0000-000000000c01';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('71950000-0000-0000-0000-000000000c01', 'Cabinet Correspondent-7195-A');

SET LOCAL app.current_cabinet_id = '71950000-0000-0000-0000-000000000c02';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('71950000-0000-0000-0000-000000000c02', 'Cabinet Correspondent-7195-B');

SET LOCAL app.current_cabinet_id = '71950000-0000-0000-0000-000000000c01';
INSERT INTO cabinet_correspondent (id, cabinet_id, display_name, specialty, email, phone, rpps) VALUES
  ('71950000-0000-0000-0000-000000000030',
   '71950000-0000-0000-0000-000000000c01',
   'Dr Adressage Test', 'Cardiologie', 'correspondent.7195@nubia.test', '0102030405', '12345678901');

-- ===========================================================================
-- CC1. Cabinet A voit son propre correspondant.
-- ===========================================================================
SELECT is(
  (SELECT count(*)::int FROM cabinet_correspondent
   WHERE id = '71950000-0000-0000-0000-000000000030'),
  1,
  'CC1 cabinet_correspondent : cabinet A voit son propre correspondant (tenant_isolation)');

-- ===========================================================================
-- CC2. Cabinet B ne voit pas le correspondant du cabinet A (cross-tenant).
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '71950000-0000-0000-0000-000000000c02';
SELECT is(
  (SELECT count(*)::int FROM cabinet_correspondent
   WHERE id = '71950000-0000-0000-0000-000000000030'),
  0,
  '⭐ CC2 cabinet_correspondent : cabinet B ne voit PAS le correspondant du cabinet A (isolation cross-tenant)');

-- ===========================================================================
-- CC3. Fail-closed : sans GUC app.current_cabinet_id → 0 ligne visible.
-- ===========================================================================
RESET app.current_cabinet_id;
SELECT is(
  (SELECT count(*)::int FROM cabinet_correspondent
   WHERE id = '71950000-0000-0000-0000-000000000030'),
  0,
  '⭐ CC3 cabinet_correspondent : fail-closed, 0 ligne visible sans GUC positionné');

-- ===========================================================================
-- CC4. display_name vide (après trim) refusé par le CHECK.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '71950000-0000-0000-0000-000000000c01';
SELECT throws_ok(
  $$ INSERT INTO cabinet_correspondent (cabinet_id, display_name)
     VALUES ('71950000-0000-0000-0000-000000000c01', '   ') $$,
  '23514', NULL,
  'CC4 cabinet_correspondent_display_name_not_blank : display_name vide refusé (23514)');

-- ===========================================================================
-- CC5. patient.referred_by_correspondent_id : lien légitime (même cabinet) accepté.
-- ===========================================================================
INSERT INTO patient (id, cabinet_id, first_name, last_name, referred_by_correspondent_id) VALUES
  ('71950000-0000-0000-0000-000000000020',
   '71950000-0000-0000-0000-000000000c01', 'Marc', 'Adresse7195',
   '71950000-0000-0000-0000-000000000030');
SELECT is(
  (SELECT referred_by_correspondent_id FROM patient
   WHERE id = '71950000-0000-0000-0000-000000000020')::text,
  '71950000-0000-0000-0000-000000000030',
  'CC5 patient.referred_by_correspondent_id : lien légitime (même cabinet) accepté');

-- ===========================================================================
-- CC6. FK composite : un patient du cabinet B ne peut pas référencer un
-- correspondant du cabinet A (exploit cross-tenant bloqué).
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '71950000-0000-0000-0000-000000000c02';
SELECT throws_ok(
  $$ INSERT INTO patient (id, cabinet_id, first_name, last_name, referred_by_correspondent_id)
     VALUES ('71950000-0000-0000-0000-000000000021',
             '71950000-0000-0000-0000-000000000c02', 'Eve', 'Exploit7195',
             '71950000-0000-0000-0000-000000000030') $$,
  '23503', NULL,
  '⭐ CC6 patient_referred_by_correspondent_cabinet_fkey : correspondant d''un autre cabinet refusé (23503)');

SELECT * FROM finish();
ROLLBACK;
