-- 88_quote_signature_composite_fk.sql
-- pgTAP : FK composite tenant-scopée groupes "quote" et "signature" —
-- migration 0213, audit #4291.
--   QI1/QI2. quote_item.quote_id -> quote(id, cabinet_id) : légitime OK,
--            exploit cross-cabinet refusé (23503).
--   QS1/QS2. quote.signature_id -> signature(id, cabinet_id) : légitime OK,
--            exploit cross-cabinet refusé (23503).
--   PS1/PS2. prescription.signature_id -> signature(id, cabinet_id) :
--            légitime OK, exploit cross-cabinet refusé (23503).
--   FC. Fail-closed : sans GUC -> 0 ligne visible.
-- Échantillon représentatif (pattern déjà mécanique et identique 6 fois —
-- payment_schedule.quote_id/payment.quote_id/treatment_plan.quote_id
-- couverts structurellement par fk_ok() dans 00_schema.sql/15_billing.sql).
-- Exécuté par pg_prove sous nubia_app (NOSUPERUSER, NOBYPASSRLS).
-- Fixtures auto-contenues (BEGIN…ROLLBACK). Préfixe UUID 42910003-...
-- Issue : #4291

BEGIN;
SELECT plan(7);

-- ===========================================================================
-- Fixtures : 2 cabinets, chacun avec un patient/practitioner ; cabinet A a
-- en plus un quote et une signature.
-- ===========================================================================
INSERT INTO app_user (id, email, kind, status) VALUES
  ('42910003-0000-0000-0000-0000000000a1', 'praticien-qs-a@demo-42913.test', 'pro', 'active');

SET LOCAL app.current_cabinet_id = '42910003-0000-0000-0000-000000000c11';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('42910003-0000-0000-0000-000000000c11', 'Cabinet QS-4291-A');
INSERT INTO patient (id, cabinet_id, first_name, last_name) VALUES
  ('42910003-0000-0000-0000-000000000e11', '42910003-0000-0000-0000-000000000c11',
   'Patient', 'A');
INSERT INTO practitioner (id, cabinet_id, user_id) VALUES
  ('42910003-0000-0000-0000-000000000d11', '42910003-0000-0000-0000-000000000c11',
   '42910003-0000-0000-0000-0000000000a1');
INSERT INTO quote (id, cabinet_id, patient_id) VALUES
  ('42910003-0000-0000-0000-000000000f11', '42910003-0000-0000-0000-000000000c11',
   '42910003-0000-0000-0000-000000000e11');
INSERT INTO signature (id, cabinet_id, provider_ref) VALUES
  ('42910003-0000-0000-0000-000000000f21', '42910003-0000-0000-0000-000000000c11',
   'yousign-ref-a');
RESET app.current_cabinet_id;

SET LOCAL app.current_cabinet_id = '42910003-0000-0000-0000-000000000c12';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('42910003-0000-0000-0000-000000000c12', 'Cabinet QS-4291-B');
INSERT INTO patient (id, cabinet_id, first_name, last_name) VALUES
  ('42910003-0000-0000-0000-000000000e12', '42910003-0000-0000-0000-000000000c12',
   'Patient', 'B');
INSERT INTO practitioner (id, cabinet_id, user_id) VALUES
  ('42910003-0000-0000-0000-000000000d12', '42910003-0000-0000-0000-000000000c12',
   '42910003-0000-0000-0000-0000000000a1');
INSERT INTO quote (id, cabinet_id, patient_id) VALUES
  ('42910003-0000-0000-0000-000000000f12', '42910003-0000-0000-0000-000000000c12',
   '42910003-0000-0000-0000-000000000e12');
RESET app.current_cabinet_id;

-- ===========================================================================
-- QI1/QI2. quote_item.quote_id
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '42910003-0000-0000-0000-000000000c11';
INSERT INTO quote_item (cabinet_id, quote_id, label, unit_amount) VALUES
  ('42910003-0000-0000-0000-000000000c11', '42910003-0000-0000-0000-000000000f11',
   'Acte A', 5000);
SELECT lives_ok(
  $$ SELECT 1 $$,
  'QI1 quote_item : fixture légitime cabinet A / quote A insérée sans erreur');
RESET app.current_cabinet_id;
SET LOCAL app.current_cabinet_id = '42910003-0000-0000-0000-000000000c12';
SELECT throws_ok(
  $$ INSERT INTO quote_item (cabinet_id, quote_id, label, unit_amount)
     VALUES ('42910003-0000-0000-0000-000000000c12',
             '42910003-0000-0000-0000-000000000f11', 'Acte cross-tenant', 5000) $$,
  '23503', NULL,
  '⭐ QI2 quote_item : rattacher un quote d''un autre cabinet refusé (23503, RLS FK)');
RESET app.current_cabinet_id;

-- ===========================================================================
-- QS1/QS2. quote.signature_id
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '42910003-0000-0000-0000-000000000c11';
UPDATE quote SET signature_id = '42910003-0000-0000-0000-000000000f21'
  WHERE id = '42910003-0000-0000-0000-000000000f11';
SELECT lives_ok(
  $$ SELECT 1 $$,
  'QS1 quote : rattacher sa propre signature (cabinet A) OK');
RESET app.current_cabinet_id;
SET LOCAL app.current_cabinet_id = '42910003-0000-0000-0000-000000000c12';
SELECT throws_ok(
  $$ UPDATE quote SET signature_id = '42910003-0000-0000-0000-000000000f21'
     WHERE id = '42910003-0000-0000-0000-000000000f12' $$,
  '23503', NULL,
  '⭐ QS2 quote : rattacher la signature d''un autre cabinet refusé (23503, RLS FK)');
RESET app.current_cabinet_id;

-- ===========================================================================
-- PS1/PS2. prescription.signature_id
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '42910003-0000-0000-0000-000000000c11';
INSERT INTO prescription (id, cabinet_id, patient_id, practitioner_id, status, signature_id) VALUES
  ('42910003-0000-0000-0000-000000000f31', '42910003-0000-0000-0000-000000000c11',
   '42910003-0000-0000-0000-000000000e11', '42910003-0000-0000-0000-000000000d11',
   'signed', '42910003-0000-0000-0000-000000000f21');
SELECT lives_ok(
  $$ SELECT 1 $$,
  'PS1 prescription : rattacher sa propre signature (cabinet A) OK');
RESET app.current_cabinet_id;
SET LOCAL app.current_cabinet_id = '42910003-0000-0000-0000-000000000c12';
INSERT INTO practitioner (id, cabinet_id, user_id) VALUES
  ('42910003-0000-0000-0000-000000000d13', '42910003-0000-0000-0000-000000000c12',
   '42910003-0000-0000-0000-0000000000a1');
SELECT throws_ok(
  $$ INSERT INTO prescription (cabinet_id, patient_id, practitioner_id, status, signature_id)
     VALUES ('42910003-0000-0000-0000-000000000c12',
             '42910003-0000-0000-0000-000000000e12', '42910003-0000-0000-0000-000000000d13',
             'signed', '42910003-0000-0000-0000-000000000f21') $$,
  '23503', NULL,
  '⭐ PS2 prescription : rattacher la signature d''un autre cabinet refusé (23503, RLS FK)');
RESET app.current_cabinet_id;

-- ===========================================================================
-- FC. Fail-closed : sans GUC -> 0 ligne visible.
-- ===========================================================================
SELECT is(
  (SELECT count(*)::int FROM quote_item) + (SELECT count(*)::int FROM signature)
    + (SELECT count(*)::int FROM prescription WHERE signature_id IS NOT NULL),
  0,
  '⭐ FC fail-closed : 0 ligne visible (quote_item/signature/prescription) sans GUC positionné');

SELECT * FROM finish();
ROLLBACK;
