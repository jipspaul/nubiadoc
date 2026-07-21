-- 61_conversation_platform_support_scope.sql
-- pgTAP : CHECK conversation_platform_support_no_patient_chk (#4168).
-- Vérifie la contrainte ajoutée par la migration 0169 (sens unique — voir
-- son commentaire pour la justification de l'écart avec l'issue) :
--   CPS1. scope='platform_support', patient_id=NULL → INSERT réussit
--   CPS2. scope='platform_support', patient_id renseigné → INSERT échoue (23514)
--   CPS3. scope='patient_cabinet',  patient_id=NULL → INSERT réussit toujours
--         (non-régression : "liaison clinique différée" #450, migration 0036 —
--         cette issue ne doit PAS casser ce comportement déjà shippé)
--   CPS4. scope='patient_pharmacy', patient_id=NULL → INSERT réussit toujours
--         (non-régression : pattern légitime préexistant, migration 0126)
-- Exécuté par pg_prove sous nubia_app (NOSUPERUSER, NOBYPASSRLS).
-- Fixtures auto-contenues (BEGIN…ROLLBACK). Préfixe UUID 41680000.
-- Issue : #4168

BEGIN;
SELECT plan(4);

SET LOCAL app.current_cabinet_id = '41680000-0000-0000-0000-000000000001';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('41680000-0000-0000-0000-000000000001', 'Cabinet ConvPlatformSupport-4168');

INSERT INTO patient (id, cabinet_id, first_name, last_name) VALUES
  ('41680000-0000-0000-0000-000000000020',
   '41680000-0000-0000-0000-000000000001', 'Léa', 'Support4168');

-- ===========================================================================
-- CPS1. scope='platform_support', patient_id=NULL → OK.
-- ===========================================================================
SELECT lives_ok(
  $$ INSERT INTO conversation (cabinet_id, scope, patient_id)
     VALUES ('41680000-0000-0000-0000-000000000001', 'platform_support', NULL) $$,
  'CPS1 conversation : scope=platform_support + patient_id=NULL accepté');

-- ===========================================================================
-- CPS2. scope='platform_support', patient_id renseigné → rejeté (23514).
-- ===========================================================================
SELECT throws_ok(
  $$ INSERT INTO conversation (cabinet_id, scope, patient_id)
     VALUES ('41680000-0000-0000-0000-000000000001', 'platform_support',
             '41680000-0000-0000-0000-000000000020') $$,
  '23514', NULL,
  'CPS2 conversation_platform_support_no_patient_chk : platform_support + patient_id renseigné rejeté (23514)');

-- ===========================================================================
-- CPS3. Non-régression : scope='patient_cabinet', patient_id=NULL → OK
-- (liaison clinique différée, #450 / migration 0036 — ne doit pas être cassé).
-- ===========================================================================
SELECT lives_ok(
  $$ INSERT INTO conversation (cabinet_id, scope, patient_id)
     VALUES ('41680000-0000-0000-0000-000000000001', 'patient_cabinet', NULL) $$,
  'CPS3 conversation : scope=patient_cabinet + patient_id=NULL toujours accepté (non-régression #450)');

-- ===========================================================================
-- CPS4. Non-régression : scope='patient_pharmacy', patient_id=NULL → OK.
-- ===========================================================================
SET LOCAL app.current_pharmacy_id = '41680000-0000-0000-0000-000000000040';
INSERT INTO pharmacy (id, raison_sociale, is_listed) VALUES
  ('41680000-0000-0000-0000-000000000040', 'Pharmacie ConvPlatformSupport-4168', true);

SELECT lives_ok(
  $$ INSERT INTO conversation (pharmacy_id, scope, patient_id)
     VALUES ('41680000-0000-0000-0000-000000000040', 'patient_pharmacy', NULL) $$,
  'CPS4 conversation : scope=patient_pharmacy + patient_id=NULL toujours accepté (non-régression migration 0126)');

SELECT * FROM finish();
ROLLBACK;
