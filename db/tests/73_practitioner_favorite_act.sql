-- 73_practitioner_favorite_act.sql
-- pgTAP : practitioner_favorite_act (#4111, migration 0181).
--   PF1. Un praticien peut ajouter un acte CCAM favori.
--   PF2. RLS tenant : cabinet B ne voit PAS les favoris de A.
--   PF3. Fail-closed : sans GUC app.current_cabinet_id → 0 ligne.
--   PF4. UNIQUE (practitioner_id, ccam_code) : doublon refusé.
--   PF5. ccam_code doit référencer un code du catalogue ccam_act (FK).
-- Exécuté par pg_prove sous nubia_app (NOSUPERUSER, NOBYPASSRLS).
-- Fixtures auto-contenues (BEGIN…ROLLBACK). Préfixe UUID 41110000.
-- Issue : #4111

BEGIN;
SELECT plan(5);

-- ===========================================================================
-- Fixtures : 2 cabinets + 1 praticien chacun.
-- ===========================================================================
INSERT INTO app_user (id, email, password_hash, kind) VALUES
  ('41110000-0000-0000-0000-0000000000a1', 'pfa.a@nubia.test', '$argon2id$fixture', 'pro');
INSERT INTO app_user (id, email, password_hash, kind) VALUES
  ('41110000-0000-0000-0000-0000000000a2', 'pfa.b@nubia.test', '$argon2id$fixture', 'pro');

SET LOCAL app.current_cabinet_id = '41110000-0000-0000-0000-000000000c01';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('41110000-0000-0000-0000-000000000c01', 'Cabinet Favorite-4111-A');
INSERT INTO practitioner (id, cabinet_id, user_id) VALUES
  ('41110000-0000-0000-0000-000000000d01', '41110000-0000-0000-0000-000000000c01',
   '41110000-0000-0000-0000-0000000000a1');
RESET app.current_cabinet_id;

SET LOCAL app.current_cabinet_id = '41110000-0000-0000-0000-000000000c02';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('41110000-0000-0000-0000-000000000c02', 'Cabinet Favorite-4111-B');
INSERT INTO practitioner (id, cabinet_id, user_id) VALUES
  ('41110000-0000-0000-0000-000000000d02', '41110000-0000-0000-0000-000000000c02',
   '41110000-0000-0000-0000-0000000000a2');
RESET app.current_cabinet_id;

-- ===========================================================================
-- PF1. Le praticien A ajoute un acte CCAM favori.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '41110000-0000-0000-0000-000000000c01';
INSERT INTO practitioner_favorite_act (id, practitioner_id, cabinet_id, ccam_code, position) VALUES
  ('41110000-0000-0000-0000-000000000f01',
   '41110000-0000-0000-0000-000000000d01',
   '41110000-0000-0000-0000-000000000c01',
   'HBQK002', 1);
SELECT is(
  (SELECT count(*)::int FROM practitioner_favorite_act
   WHERE practitioner_id = '41110000-0000-0000-0000-000000000d01'),
  1,
  'PF1 practitioner_favorite_act : le praticien A ajoute un favori');

-- ===========================================================================
-- PF2. RLS : cabinet B ne voit PAS les favoris de A.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '41110000-0000-0000-0000-000000000c02';
SELECT is(
  (SELECT count(*)::int FROM practitioner_favorite_act
   WHERE practitioner_id = '41110000-0000-0000-0000-000000000d01'),
  0,
  '⭐ PF2 practitioner_favorite_act_tenant_isolation : cabinet B ne voit PAS les favoris de A');

-- ===========================================================================
-- PF3. Fail-closed : sans GUC → 0 ligne visible.
-- ===========================================================================
RESET app.current_cabinet_id;
SELECT is(
  (SELECT count(*)::int FROM practitioner_favorite_act),
  0,
  '⭐ PF3 practitioner_favorite_act : fail-closed, 0 ligne sans GUC positionné');

-- ===========================================================================
-- PF4. UNIQUE (practitioner_id, ccam_code) : doublon refusé.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '41110000-0000-0000-0000-000000000c01';
SELECT throws_ok(
  $$ INSERT INTO practitioner_favorite_act (practitioner_id, cabinet_id, ccam_code, position)
     VALUES ('41110000-0000-0000-0000-000000000d01',
             '41110000-0000-0000-0000-000000000c01', 'HBQK002', 2) $$,
  '23505', NULL,
  'PF4 practitioner_favorite_act_practitioner_id_ccam_code_key : doublon refusé (23505)');

-- ===========================================================================
-- PF5. ccam_code doit exister dans le catalogue ccam_act (FK).
-- ===========================================================================
SELECT throws_ok(
  $$ INSERT INTO practitioner_favorite_act (practitioner_id, cabinet_id, ccam_code, position)
     VALUES ('41110000-0000-0000-0000-000000000d01',
             '41110000-0000-0000-0000-000000000c01', 'CODE_INEXISTANT', 3) $$,
  '23503', NULL,
  'PF5 practitioner_favorite_act_ccam_code_fkey : code CCAM inexistant refusé (23503)');

SELECT * FROM finish();
ROLLBACK;
