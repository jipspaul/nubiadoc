-- 67_quote_billed_to_account.sql
-- pgTAP : quote.billed_to_account_id + policy quote_patient_read étendue
-- (#4098, migration 0175).
--   QB1. Bénéficiaire des soins (patient_id → patient_account_id) voit
--        toujours son devis — comportement inchangé.
--   QB2. Responsable légal (billed_to_account_id) voit aussi le devis.
--   QB3. Compte tiers (ni bénéficiaire ni responsable) ne voit rien.
--   QB4. Devis sans billed_to_account_id (NULL) : comportement identique à
--        avant la migration (visible seulement au bénéficiaire).
-- Exécuté par pg_prove sous nubia_app (NOSUPERUSER, NOBYPASSRLS).
-- Fixtures auto-contenues (BEGIN…ROLLBACK). Préfixe UUID 40980000.
-- Issue : #4098

BEGIN;
SELECT plan(4);

-- ===========================================================================
-- Fixtures : cabinet, 2 comptes plateforme (bénéficiaire, responsable) +
-- 1 tiers, patient cabinet rattaché au bénéficiaire, 2 devis (avec/sans
-- billed_to_account_id).
-- ===========================================================================
INSERT INTO app_user (id, email, password_hash, kind) VALUES
  ('40980000-0000-0000-0000-0000000000a1', 'quote.billed.beneficiary@nubia.test', '$argon2id$fixture', 'patient');
INSERT INTO app_user (id, email, password_hash, kind) VALUES
  ('40980000-0000-0000-0000-0000000000a2', 'quote.billed.guardian@nubia.test', '$argon2id$fixture', 'patient');
INSERT INTO app_user (id, email, password_hash, kind) VALUES
  ('40980000-0000-0000-0000-0000000000a3', 'quote.billed.thirdparty@nubia.test', '$argon2id$fixture', 'patient');

INSERT INTO patient_account (id, app_user_id, first_name, last_name) VALUES
  ('40980000-0000-0000-0000-0000000000e1', '40980000-0000-0000-0000-0000000000a1', 'Léa', 'Beneficiaire');
INSERT INTO patient_account (id, app_user_id, first_name, last_name) VALUES
  ('40980000-0000-0000-0000-0000000000e2', '40980000-0000-0000-0000-0000000000a2', 'Paul', 'Guardian');
INSERT INTO patient_account (id, app_user_id, first_name, last_name) VALUES
  ('40980000-0000-0000-0000-0000000000e3', '40980000-0000-0000-0000-0000000000a3', 'Marc', 'Tiers');

SET LOCAL app.current_cabinet_id = '40980000-0000-0000-0000-000000000001';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('40980000-0000-0000-0000-000000000001', 'Cabinet QuoteBilledTo-4098');

INSERT INTO patient (id, cabinet_id, first_name, last_name, patient_account_id) VALUES
  ('40980000-0000-0000-0000-000000000030', '40980000-0000-0000-0000-000000000001',
   'Léa', 'Beneficiaire', '40980000-0000-0000-0000-0000000000e1');

-- Devis avec billed_to_account_id (responsable = e2).
INSERT INTO quote (id, cabinet_id, patient_id, status, total_amount, billed_to_account_id) VALUES
  ('40980000-0000-0000-0000-000000000040', '40980000-0000-0000-0000-000000000001',
   '40980000-0000-0000-0000-000000000030', 'sent', 200.00, '40980000-0000-0000-0000-0000000000e2');

-- Devis sans billed_to_account_id (NULL) — comportement pré-migration.
INSERT INTO quote (id, cabinet_id, patient_id, status, total_amount) VALUES
  ('40980000-0000-0000-0000-000000000041', '40980000-0000-0000-0000-000000000001',
   '40980000-0000-0000-0000-000000000030', 'sent', 100.00);

RESET app.current_cabinet_id;

-- ===========================================================================
-- QB1. Bénéficiaire des soins voit les 2 devis (comportement inchangé).
-- ===========================================================================
SET LOCAL app.patient_account_id = '40980000-0000-0000-0000-0000000000e1';
SELECT is(
  (SELECT count(*)::int FROM quote
   WHERE id IN ('40980000-0000-0000-0000-000000000040',
                '40980000-0000-0000-0000-000000000041')),
  2,
  'QB1 quote_patient_read : bénéficiaire voit ses 2 devis (inchangé)');

-- ===========================================================================
-- QB2. Responsable légal voit le devis qui lui est facturé.
-- ===========================================================================
SET LOCAL app.patient_account_id = '40980000-0000-0000-0000-0000000000e2';
SELECT is(
  (SELECT count(*)::int FROM quote
   WHERE id = '40980000-0000-0000-0000-000000000040'),
  1,
  '⭐ QB2 quote_patient_read : responsable légal voit le devis billed_to_account_id');

-- ===========================================================================
-- QB3. Compte tiers ne voit aucun des 2 devis.
-- ===========================================================================
SET LOCAL app.patient_account_id = '40980000-0000-0000-0000-0000000000e3';
SELECT is(
  (SELECT count(*)::int FROM quote
   WHERE id IN ('40980000-0000-0000-0000-000000000040',
                '40980000-0000-0000-0000-000000000041')),
  0,
  '⭐ QB3 quote_patient_read : compte tiers ne voit aucun devis');

-- ===========================================================================
-- QB4. Responsable légal ne voit PAS le devis sans billed_to_account_id.
-- ===========================================================================
SET LOCAL app.patient_account_id = '40980000-0000-0000-0000-0000000000e2';
SELECT is(
  (SELECT count(*)::int FROM quote
   WHERE id = '40980000-0000-0000-0000-000000000041'),
  0,
  'QB4 quote_patient_read : devis sans billed_to_account_id invisible au non-bénéficiaire');

SELECT * FROM finish();
ROLLBACK;
