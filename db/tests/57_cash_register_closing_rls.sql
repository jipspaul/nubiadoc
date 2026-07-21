-- 57_cash_register_closing_rls.sql
-- pgTAP : RLS cash_register_closing — isolation cabinet (#4071).
-- Vérifie la policy tenant_isolation ajoutée par la migration 0165 :
--   CR1. Cabinet A voit sa propre clôture
--   CR2. Cabinet B ne voit pas la clôture du cabinet A (cross-tenant)
--   CR3. Fail-closed : sans GUC app.current_cabinet_id positionné → 0 ligne visible
--   CR4. Une deuxième clôture du même jour pour le même cabinet est refusée
--        (cash_register_closing_unique_per_day)
-- Exécuté par pg_prove sous nubia_app (NOSUPERUSER, NOBYPASSRLS).
-- Fixtures auto-contenues (BEGIN…ROLLBACK). Préfixe UUID 40710000.
-- Issue : #4071

BEGIN;
SELECT plan(4);

-- ===========================================================================
-- Fixtures : 2 cabinets (A, B), 1 utilisateur, 1 clôture pour le cabinet A.
-- ===========================================================================

SET LOCAL app.current_cabinet_id = '40710000-0000-0000-0000-000000000001';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('40710000-0000-0000-0000-000000000001', 'Cabinet CashRegister-4071-A');

SET LOCAL app.current_cabinet_id = '40710000-0000-0000-0000-000000000002';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('40710000-0000-0000-0000-000000000002', 'Cabinet CashRegister-4071-B');

SET LOCAL app.current_cabinet_id = '40710000-0000-0000-0000-000000000001';

INSERT INTO app_user (id, email, password_hash, kind) VALUES
  ('40710000-0000-0000-0000-000000000010', 'secretaire.4071@nubia.test', '$argon2id$fixture', 'pro');

INSERT INTO cash_register_closing
    (id, cabinet_id, closing_date, totals_by_method, total_amount, closed_by)
  VALUES
    ('40710000-0000-0000-0000-000000000020',
     '40710000-0000-0000-0000-000000000001',
     '2026-07-21',
     '{"cash": 5000, "card": 12000}',
     170.00,
     '40710000-0000-0000-0000-000000000010');

-- ===========================================================================
-- CR1. Cabinet A voit sa propre clôture.
-- ===========================================================================
SELECT is(
  (SELECT count(*)::int FROM cash_register_closing
   WHERE id = '40710000-0000-0000-0000-000000000020'),
  1,
  'CR1 cash_register_closing : cabinet A voit sa propre clôture (tenant_isolation)');

-- ===========================================================================
-- CR2. Cabinet B ne voit pas la clôture du cabinet A (cross-tenant).
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '40710000-0000-0000-0000-000000000002';
SELECT is(
  (SELECT count(*)::int FROM cash_register_closing
   WHERE id = '40710000-0000-0000-0000-000000000020'),
  0,
  'CR2 cash_register_closing : cabinet B ne voit PAS la clôture du cabinet A (isolation cross-tenant)');

-- ===========================================================================
-- CR3. Fail-closed : sans GUC app.current_cabinet_id positionné → 0 ligne visible.
-- ===========================================================================
RESET app.current_cabinet_id;
SELECT is(
  (SELECT count(*)::int FROM cash_register_closing
   WHERE id = '40710000-0000-0000-0000-000000000020'),
  0,
  'CR3 cash_register_closing : fail-closed, 0 ligne visible sans GUC positionné');

-- ===========================================================================
-- CR4. Une deuxième clôture du même jour pour le même cabinet est refusée.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '40710000-0000-0000-0000-000000000001';
SELECT throws_ok(
  $$ INSERT INTO cash_register_closing
       (cabinet_id, closing_date, totals_by_method, total_amount, closed_by)
     VALUES
       ('40710000-0000-0000-0000-000000000001',
        '2026-07-21',
        '{}',
        0,
        '40710000-0000-0000-0000-000000000010') $$,
  '23505', NULL,
  'CR4 cash_register_closing_unique_per_day : deuxième clôture du même jour refusée (23505)');

SELECT * FROM finish();
ROLLBACK;
