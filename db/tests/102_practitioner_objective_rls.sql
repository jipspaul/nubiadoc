-- 102_practitioner_objective_rls.sql
-- pgTAP : RLS practitioner_objective — isolation cabinet (#7190).
-- Vérifie la policy tenant_isolation ajoutée par la migration 0282 :
--   PO1. Cabinet A voit l'objectif de son praticien
--   PO2. Cabinet B ne voit pas l'objectif du cabinet A (cross-tenant)
--   PO3. Fail-closed : sans GUC app.current_cabinet_id positionné → 0 ligne visible
--   PO4. UNIQUE(cabinet_id, provider_id, month) : un 2e objectif même mois refusé
--   PO5. month doit être le 1er du mois (CHECK practitioner_objective_month_is_first_day)
-- Exécuté par pg_prove sous nubia_app (NOSUPERUSER, NOBYPASSRLS).
-- Fixtures auto-contenues (BEGIN…ROLLBACK). Préfixe UUID 71900000.
-- Issue : #7190

BEGIN;
SELECT plan(5);

-- ===========================================================================
-- Fixtures : 2 cabinets (A, B), 1 utilisateur pro + 1 provider dans chacun.
-- ===========================================================================

SET LOCAL app.current_cabinet_id = '71900000-0000-0000-0000-000000000001';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('71900000-0000-0000-0000-000000000001', 'Cabinet Objectif-7190-A');

SET LOCAL app.current_cabinet_id = '71900000-0000-0000-0000-000000000002';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('71900000-0000-0000-0000-000000000002', 'Cabinet Objectif-7190-B');

SET LOCAL app.current_cabinet_id = '71900000-0000-0000-0000-000000000001';

INSERT INTO app_user (id, email, password_hash, kind) VALUES
  ('71900000-0000-0000-0000-000000000010', 'manager.7190@nubia.test', '$argon2id$fixture', 'pro');

INSERT INTO provider (id, cabinet_id, user_id, display_name) VALUES
  ('71900000-0000-0000-0000-000000000020',
   '71900000-0000-0000-0000-000000000001',
   '71900000-0000-0000-0000-000000000010', 'Dr Objectif-7190-A');

INSERT INTO practitioner_objective (id, cabinet_id, provider_id, month, target_cents, created_by) VALUES
  ('71900000-0000-0000-0000-000000000030',
   '71900000-0000-0000-0000-000000000001',
   '71900000-0000-0000-0000-000000000020',
   '2026-09-01', 1500000,
   '71900000-0000-0000-0000-000000000010');

-- ===========================================================================
-- PO1. Cabinet A voit l'objectif de son praticien.
-- ===========================================================================
SELECT is(
  (SELECT count(*)::int FROM practitioner_objective
   WHERE id = '71900000-0000-0000-0000-000000000030'),
  1,
  'PO1 practitioner_objective : cabinet A voit son propre objectif (tenant_isolation)');

-- ===========================================================================
-- PO2. Cabinet B ne voit pas l'objectif du cabinet A (cross-tenant).
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '71900000-0000-0000-0000-000000000002';
SELECT is(
  (SELECT count(*)::int FROM practitioner_objective
   WHERE id = '71900000-0000-0000-0000-000000000030'),
  0,
  'PO2 practitioner_objective : cabinet B ne voit PAS l''objectif du cabinet A (isolation cross-tenant)');

-- ===========================================================================
-- PO3. Fail-closed : sans GUC app.current_cabinet_id positionné → 0 ligne visible.
-- ===========================================================================
RESET app.current_cabinet_id;
SELECT is(
  (SELECT count(*)::int FROM practitioner_objective
   WHERE id = '71900000-0000-0000-0000-000000000030'),
  0,
  'PO3 practitioner_objective : fail-closed, 0 ligne visible sans GUC positionné');

-- ===========================================================================
-- PO4. UNIQUE(cabinet_id, provider_id, month) : un 2e objectif même mois refusé.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '71900000-0000-0000-0000-000000000001';
SELECT throws_ok(
  $$ INSERT INTO practitioner_objective (cabinet_id, provider_id, month, target_cents, created_by)
     VALUES ('71900000-0000-0000-0000-000000000001',
             '71900000-0000-0000-0000-000000000020',
             '2026-09-01', 2000000,
             '71900000-0000-0000-0000-000000000010') $$,
  '23505', NULL,
  'PO4 practitioner_objective_unique_cabinet_provider_month : doublon même mois refusé (23505)');

-- ===========================================================================
-- PO5. month doit être le 1er du mois (CHECK practitioner_objective_month_is_first_day).
-- ===========================================================================
SELECT throws_ok(
  $$ INSERT INTO practitioner_objective (cabinet_id, provider_id, month, target_cents, created_by)
     VALUES ('71900000-0000-0000-0000-000000000001',
             '71900000-0000-0000-0000-000000000020',
             '2026-09-15', 2000000,
             '71900000-0000-0000-0000-000000000010') $$,
  '23514', NULL,
  'PO5 practitioner_objective_month_is_first_day : month non aligné sur le 1er du mois refusé (23514)');

SELECT * FROM finish();
ROLLBACK;
