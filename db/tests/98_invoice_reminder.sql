-- 98_invoice_reminder.sql
-- pgTAP : invoice_reminder (#7206, migration 0275).
--   IR1. Cabinet A trace une relance sur sa propre facture (devis signé).
--   IR2. channel hors énum refusé (23514).
--   IR3. invoice_id d'un AUTRE cabinet refusé (23503, FK composite).
--   IR4. RLS : cabinet B ne voit PAS la relance de A.
--   IR5. Fail-closed : sans GUC → 0 ligne.
-- Exécuté par pg_prove sous nubia_app (NOSUPERUSER, NOBYPASSRLS).
-- Fixtures auto-contenues (BEGIN…ROLLBACK). Préfixe UUID 72060000.
-- Issue : #7206

BEGIN;
SELECT plan(5);

-- ===========================================================================
-- Fixtures : 2 cabinets, chacun avec un patient + un devis signé (facture).
-- ===========================================================================
INSERT INTO app_user (id, email, password_hash, kind) VALUES
  ('72060000-0000-0000-0000-0000000000a1', 'staff.7206@nubia.test', '$argon2id$fixture', 'pro');

SET LOCAL app.current_cabinet_id = '72060000-0000-0000-0000-000000000c01';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('72060000-0000-0000-0000-000000000c01', 'Cabinet Invoice-7206-A');
INSERT INTO patient (id, cabinet_id, first_name, last_name) VALUES
  ('72060000-0000-0000-0000-0000000000e1', '72060000-0000-0000-0000-000000000c01',
   'Patient', 'InvoiceA');
INSERT INTO quote (id, cabinet_id, patient_id, status, total_amount, currency, signed_at) VALUES
  ('72060000-0000-0000-0000-0000000000f1', '72060000-0000-0000-0000-000000000c01',
   '72060000-0000-0000-0000-0000000000e1', 'signed', 500.00, 'EUR', now());
RESET app.current_cabinet_id;

SET LOCAL app.current_cabinet_id = '72060000-0000-0000-0000-000000000c02';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('72060000-0000-0000-0000-000000000c02', 'Cabinet Invoice-7206-B');
INSERT INTO patient (id, cabinet_id, first_name, last_name) VALUES
  ('72060000-0000-0000-0000-0000000000e2', '72060000-0000-0000-0000-000000000c02',
   'Patient', 'InvoiceB');
INSERT INTO quote (id, cabinet_id, patient_id, status, total_amount, currency, signed_at) VALUES
  ('72060000-0000-0000-0000-0000000000f2', '72060000-0000-0000-0000-000000000c02',
   '72060000-0000-0000-0000-0000000000e2', 'signed', 300.00, 'EUR', now());
RESET app.current_cabinet_id;

-- ===========================================================================
-- IR1. Cabinet A trace une relance sur sa propre facture.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '72060000-0000-0000-0000-000000000c01';
INSERT INTO invoice_reminder (id, invoice_id, cabinet_id, channel, sent_by) VALUES
  ('72060000-0000-0000-0000-000000000d01', '72060000-0000-0000-0000-0000000000f1',
   '72060000-0000-0000-0000-000000000c01', 'push', '72060000-0000-0000-0000-0000000000a1');
SELECT is(
  (SELECT count(*)::int FROM invoice_reminder
   WHERE id = '72060000-0000-0000-0000-000000000d01'),
  1,
  'IR1 invoice_reminder : relance cabinet A sur sa propre facture OK');

-- ===========================================================================
-- IR2. channel hors énum refusé (23514).
-- ===========================================================================
SELECT throws_ok(
  $$ INSERT INTO invoice_reminder (invoice_id, cabinet_id, channel, sent_by)
     VALUES ('72060000-0000-0000-0000-0000000000f1',
             '72060000-0000-0000-0000-000000000c01', 'sms',
             '72060000-0000-0000-0000-0000000000a1') $$,
  '23514', NULL,
  'IR2 invoice_reminder_channel_check : channel hors énum refusé (23514)');

-- ===========================================================================
-- IR3. invoice_id d'un AUTRE cabinet refusé (23503, FK composite).
-- ===========================================================================
SELECT throws_ok(
  $$ INSERT INTO invoice_reminder (invoice_id, cabinet_id, channel, sent_by)
     VALUES ('72060000-0000-0000-0000-0000000000f2',
             '72060000-0000-0000-0000-000000000c01', 'push',
             '72060000-0000-0000-0000-0000000000a1') $$,
  '23503', NULL,
  '⭐ IR3 invoice_reminder : facture d''un autre cabinet refusée (23503, FK composite)');

-- ===========================================================================
-- IR4. RLS : cabinet B ne voit PAS la relance de A.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '72060000-0000-0000-0000-000000000c02';
SELECT is(
  (SELECT count(*)::int FROM invoice_reminder
   WHERE id = '72060000-0000-0000-0000-000000000d01'),
  0,
  '⭐ IR4 tenant_isolation : cabinet B ne voit PAS la relance du cabinet A');

-- ===========================================================================
-- IR5. Fail-closed : sans GUC → 0 ligne.
-- ===========================================================================
RESET app.current_cabinet_id;
SELECT is(
  (SELECT count(*)::int FROM invoice_reminder),
  0,
  '⭐ IR5 fail-closed : 0 ligne sans GUC positionné');

SELECT * FROM finish();
ROLLBACK;
