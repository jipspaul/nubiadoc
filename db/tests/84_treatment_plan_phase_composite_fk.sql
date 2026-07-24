-- 84_treatment_plan_phase_composite_fk.sql
-- pgTAP : FK composite tenant-scopée treatment_phase.plan_id →
-- treatment_plan(id, cabinet_id) et quote_item.phase_id →
-- treatment_phase(id, cabinet_id) — migration 0200, audit #4291.
--   TP1. Cabinet A crée un plan + une phase + une ligne de devis rattachée.
--   TP2. Rattacher une phase à un treatment_plan d'un AUTRE cabinet refusé (23503).
--   TP3. Rattacher une ligne de devis à une treatment_phase d'un AUTRE cabinet refusé (23503).
--   TP4. RLS treatment_phase : cabinet B ne voit PAS la phase de A.
--   TP5. Fail-closed : sans GUC → 0 ligne sur treatment_phase.
-- Exécuté par pg_prove sous nubia_app (NOSUPERUSER, NOBYPASSRLS).
-- Fixtures auto-contenues (BEGIN…ROLLBACK). Préfixe UUID 42910000.
-- Issue : #4291

BEGIN;
SELECT plan(5);

-- ===========================================================================
-- Fixtures : 2 cabinets, cabinet A avec patient/treatment_plan/quote.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '42910000-0000-0000-0000-000000000c01';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('42910000-0000-0000-0000-000000000c01', 'Cabinet FK-4291-A');
INSERT INTO patient (id, cabinet_id, first_name, last_name) VALUES
  ('42910000-0000-0000-0000-0000000000e1', '42910000-0000-0000-0000-000000000c01',
   'Patient', 'FKAudit');
INSERT INTO treatment_plan (id, cabinet_id, patient_id, title) VALUES
  ('42910000-0000-0000-0000-00000000aa01', '42910000-0000-0000-0000-000000000c01',
   '42910000-0000-0000-0000-0000000000e1', 'Plan A');
INSERT INTO quote (id, cabinet_id, patient_id) VALUES
  ('42910000-0000-0000-0000-00000000cc01', '42910000-0000-0000-0000-000000000c01',
   '42910000-0000-0000-0000-0000000000e1');
RESET app.current_cabinet_id;

SET LOCAL app.current_cabinet_id = '42910000-0000-0000-0000-000000000c02';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('42910000-0000-0000-0000-000000000c02', 'Cabinet FK-4291-B');
RESET app.current_cabinet_id;

-- ===========================================================================
-- TP1. Cabinet A crée une phase sur son propre plan + une ligne de devis
-- rattachée à sa propre phase.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '42910000-0000-0000-0000-000000000c01';
INSERT INTO treatment_phase (id, cabinet_id, plan_id, position, title) VALUES
  ('42910000-0000-0000-0000-00000000bb01', '42910000-0000-0000-0000-000000000c01',
   '42910000-0000-0000-0000-00000000aa01', 1, 'Phase 1');
INSERT INTO quote_item (id, cabinet_id, quote_id, label, unit_amount, phase_id) VALUES
  ('42910000-0000-0000-0000-00000000dd01', '42910000-0000-0000-0000-000000000c01',
   '42910000-0000-0000-0000-00000000cc01', 'Acte phase A', 5000, '42910000-0000-0000-0000-00000000bb01');
SELECT is(
  (SELECT count(*)::int FROM quote_item
   WHERE id = '42910000-0000-0000-0000-00000000dd01'),
  1,
  'TP1 treatment_phase/quote_item : création cabinet A, phase + ligne devis rattachées OK');

-- ===========================================================================
-- TP2. Rattacher une phase à un treatment_plan d'un AUTRE cabinet refusé
-- (23503) — treatment_plan a RLS+FORCE RLS (migration 0011) : la ligne du
-- cabinet A est invisible sous le GUC B, la FK échoue avant toute policy.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '42910000-0000-0000-0000-000000000c02';
SELECT throws_ok(
  $$ INSERT INTO treatment_phase (cabinet_id, plan_id, position, title)
     VALUES ('42910000-0000-0000-0000-000000000c02',
             '42910000-0000-0000-0000-00000000aa01', 1, 'Phase B') $$,
  '23503', NULL,
  '⭐ TP2 treatment_phase : rattacher un plan d''un autre cabinet refusé (23503, RLS FK)');

-- ===========================================================================
-- TP3. Rattacher une ligne de devis à une treatment_phase d'un AUTRE
-- cabinet refusé (23503).
-- ===========================================================================
INSERT INTO patient (id, cabinet_id, first_name, last_name) VALUES
  ('42910000-0000-0000-0000-0000000000e2', '42910000-0000-0000-0000-000000000c02',
   'Patient', 'FKAuditB');
INSERT INTO quote (id, cabinet_id, patient_id) VALUES
  ('42910000-0000-0000-0000-00000000cc02', '42910000-0000-0000-0000-000000000c02',
   '42910000-0000-0000-0000-0000000000e2');
SELECT throws_ok(
  $$ INSERT INTO quote_item (cabinet_id, quote_id, label, unit_amount, phase_id)
     VALUES ('42910000-0000-0000-0000-000000000c02',
             '42910000-0000-0000-0000-00000000cc02', 'Acte cross-tenant', 5000,
             '42910000-0000-0000-0000-00000000bb01') $$,
  '23503', NULL,
  '⭐ TP3 quote_item : rattacher une phase d''un autre cabinet refusé (23503, RLS FK)');

-- ===========================================================================
-- TP4. RLS treatment_phase : cabinet B ne voit PAS la phase de A.
-- ===========================================================================
SELECT is(
  (SELECT count(*)::int FROM treatment_phase
   WHERE id = '42910000-0000-0000-0000-00000000bb01'),
  0,
  '⭐ TP4 tenant_isolation treatment_phase : cabinet B ne voit PAS la phase de A');

-- ===========================================================================
-- TP5. Fail-closed : sans GUC → 0 ligne sur treatment_phase.
-- ===========================================================================
RESET app.current_cabinet_id;
SELECT is(
  (SELECT count(*)::int FROM treatment_phase),
  0,
  '⭐ TP5 fail-closed : 0 ligne treatment_phase sans GUC positionné');

SELECT * FROM finish();
ROLLBACK;
