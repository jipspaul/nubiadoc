-- 62_conversation_platform_support_unique.sql
-- pgTAP : index unique conversation_uniq_platform_support_cabinet (#4169).
-- Vérifie la contrainte ajoutée par la migration 0170 :
--   CPSU1. 1er conversation platform_support d'un cabinet → OK
--   CPSU2. 2e conversation platform_support du MÊME cabinet → rejetée (23505)
--   CPSU3. conversation platform_support d'un AUTRE cabinet → OK (pas de
--          contrainte cross-tenant, l'index est scopé par cabinet_id)
-- Exécuté par pg_prove sous nubia_app (NOSUPERUSER, NOBYPASSRLS).
-- Fixtures auto-contenues (BEGIN…ROLLBACK). Préfixe UUID 41690000.
-- Issue : #4169

BEGIN;
SELECT plan(3);

SET LOCAL app.current_cabinet_id = '41690000-0000-0000-0000-000000000001';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('41690000-0000-0000-0000-000000000001', 'Cabinet ConvSupportUniq-4169-A');

SET LOCAL app.current_cabinet_id = '41690000-0000-0000-0000-000000000002';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('41690000-0000-0000-0000-000000000002', 'Cabinet ConvSupportUniq-4169-B');

SET LOCAL app.current_cabinet_id = '41690000-0000-0000-0000-000000000001';

-- ===========================================================================
-- CPSU1. 1re conversation platform_support du cabinet A → OK.
-- ===========================================================================
SELECT lives_ok(
  $$ INSERT INTO conversation (cabinet_id, scope, patient_id)
     VALUES ('41690000-0000-0000-0000-000000000001', 'platform_support', NULL) $$,
  'CPSU1 conversation : 1re conversation platform_support du cabinet A acceptée');

-- ===========================================================================
-- CPSU2. 2e conversation platform_support du MÊME cabinet A → rejetée (23505).
-- ===========================================================================
SELECT throws_ok(
  $$ INSERT INTO conversation (cabinet_id, scope, patient_id)
     VALUES ('41690000-0000-0000-0000-000000000001', 'platform_support', NULL) $$,
  '23505', NULL,
  'CPSU2 conversation_uniq_platform_support_cabinet : 2e conversation du même cabinet rejetée (23505)');

-- ===========================================================================
-- CPSU3. conversation platform_support du cabinet B (autre tenant) → OK.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '41690000-0000-0000-0000-000000000002';
SELECT lives_ok(
  $$ INSERT INTO conversation (cabinet_id, scope, patient_id)
     VALUES ('41690000-0000-0000-0000-000000000002', 'platform_support', NULL) $$,
  'CPSU3 conversation : conversation platform_support du cabinet B acceptée (pas de contrainte cross-tenant)');

SELECT * FROM finish();
ROLLBACK;
