-- 105_quote_event.sql
-- pgTAP : quote_event (#7177, migration 0287) — journal d'un devis.
--   QE1.  Cabinet A trace un événement 'created' sur son propre devis.
--   QE2.  kind hors énum refusé (23514).
--   QE3.  actor_kind hors énum refusé (23514).
--   QE4.  quote_id d'un AUTRE cabinet refusé (23503, FK composite).
--   QE5.  RLS : cabinet B ne voit PAS l'événement du cabinet A.
--   QE6.  Fail-closed : sans GUC → 0 ligne.
--   QE7.  Append-only : UPDATE interdit sous nubia_app (42501).
--   QE8.  Append-only : DELETE interdit sous nubia_app (42501).
--   QE9.  Patient lié au devis 'sent' (non-draft) voit l'événement via
--         app.patient_account_id.
--   QE10. Patient ne voit PAS les événements de son PROPRE devis 'draft'
--         (exclusion cohérente avec quote_patient_read, migration 0134).
--   QE11. Patient A ne voit PAS les événements du devis 'sent' du patient B
--         (isolation cross-patient, indépendante du statut).
-- Exécuté par pg_prove sous nubia_app (NOSUPERUSER, NOBYPASSRLS).
-- Fixtures auto-contenues (BEGIN…ROLLBACK). Préfixe UUID 71770000.
-- Issue : #7177

BEGIN;
SELECT plan(11);

-- ===========================================================================
-- Fixtures : 2 cabinets, chacun avec un patient + un devis (A : 'sent',
-- B : 'draft').
-- ===========================================================================
INSERT INTO app_user (id, email, password_hash, kind) VALUES
  ('71770000-0000-0000-0000-0000000000a1', 'staff.7177@nubia.test', '$argon2id$fixture', 'pro');

SET LOCAL app.current_cabinet_id = '71770000-0000-0000-0000-000000000c01';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('71770000-0000-0000-0000-000000000c01', 'Cabinet QuoteEvent-7177-A');
INSERT INTO patient (id, cabinet_id, first_name, last_name) VALUES
  ('71770000-0000-0000-0000-0000000000e1', '71770000-0000-0000-0000-000000000c01',
   'Patient', 'EventA');
INSERT INTO quote (id, cabinet_id, patient_id, status, total_amount, currency) VALUES
  ('71770000-0000-0000-0000-0000000000f1', '71770000-0000-0000-0000-000000000c01',
   '71770000-0000-0000-0000-0000000000e1', 'sent', 500.00, 'EUR');
RESET app.current_cabinet_id;

SET LOCAL app.current_cabinet_id = '71770000-0000-0000-0000-000000000c02';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('71770000-0000-0000-0000-000000000c02', 'Cabinet QuoteEvent-7177-B');
INSERT INTO patient (id, cabinet_id, first_name, last_name) VALUES
  ('71770000-0000-0000-0000-0000000000e2', '71770000-0000-0000-0000-000000000c02',
   'Patient', 'EventB');
INSERT INTO quote (id, cabinet_id, patient_id, status, total_amount, currency) VALUES
  ('71770000-0000-0000-0000-0000000000f2', '71770000-0000-0000-0000-000000000c02',
   '71770000-0000-0000-0000-0000000000e2', 'draft', 300.00, 'EUR');
INSERT INTO quote (id, cabinet_id, patient_id, status, total_amount, currency) VALUES
  ('71770000-0000-0000-0000-0000000000f3', '71770000-0000-0000-0000-000000000c02',
   '71770000-0000-0000-0000-0000000000e2', 'sent', 300.00, 'EUR');
RESET app.current_cabinet_id;

-- ===========================================================================
-- QE1. Cabinet A trace un événement 'created' sur son propre devis.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '71770000-0000-0000-0000-000000000c01';
INSERT INTO quote_event (id, quote_id, cabinet_id, kind, actor_kind, actor_id) VALUES
  ('71770000-0000-0000-0000-000000000d01', '71770000-0000-0000-0000-0000000000f1',
   '71770000-0000-0000-0000-000000000c01', 'created', 'cabinet',
   '71770000-0000-0000-0000-0000000000a1');
SELECT is(
  (SELECT count(*)::int FROM quote_event
   WHERE id = '71770000-0000-0000-0000-000000000d01'),
  1,
  'QE1 quote_event : cabinet A trace un événement sur son propre devis');

-- ===========================================================================
-- QE2. kind hors énum refusé (23514).
-- ===========================================================================
SELECT throws_ok(
  $$ INSERT INTO quote_event (quote_id, cabinet_id, kind, actor_kind, actor_id)
     VALUES ('71770000-0000-0000-0000-0000000000f1',
             '71770000-0000-0000-0000-000000000c01', 'expired', 'cabinet',
             '71770000-0000-0000-0000-0000000000a1') $$,
  '23514', NULL,
  'QE2 quote_event : kind hors énum refusé (23514)');

-- ===========================================================================
-- QE3. actor_kind hors énum refusé (23514).
-- ===========================================================================
SELECT throws_ok(
  $$ INSERT INTO quote_event (quote_id, cabinet_id, kind, actor_kind, actor_id)
     VALUES ('71770000-0000-0000-0000-0000000000f1',
             '71770000-0000-0000-0000-000000000c01', 'created', 'admin',
             '71770000-0000-0000-0000-0000000000a1') $$,
  '23514', NULL,
  'QE3 quote_event : actor_kind hors énum refusé (23514)');

-- ===========================================================================
-- QE4. quote_id d'un AUTRE cabinet refusé (23503, FK composite).
-- ===========================================================================
SELECT throws_ok(
  $$ INSERT INTO quote_event (quote_id, cabinet_id, kind, actor_kind)
     VALUES ('71770000-0000-0000-0000-0000000000f2',
             '71770000-0000-0000-0000-000000000c01', 'created', 'system') $$,
  '23503', NULL,
  '⭐ QE4 quote_event : devis d''un autre cabinet refusé (23503, FK composite)');

-- ===========================================================================
-- QE5. RLS : cabinet B ne voit PAS l'événement du cabinet A.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '71770000-0000-0000-0000-000000000c02';
SELECT is(
  (SELECT count(*)::int FROM quote_event
   WHERE id = '71770000-0000-0000-0000-000000000d01'),
  0,
  '⭐ QE5 tenant_isolation : cabinet B ne voit PAS l''événement du cabinet A');

-- ===========================================================================
-- QE6. Fail-closed : sans GUC → 0 ligne.
-- ===========================================================================
RESET app.current_cabinet_id;
SELECT is(
  (SELECT count(*)::int FROM quote_event),
  0,
  '⭐ QE6 fail-closed : 0 ligne sans GUC positionné');

-- ===========================================================================
-- QE7. Append-only : UPDATE interdit sous nubia_app (42501).
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '71770000-0000-0000-0000-000000000c01';
SELECT throws_ok(
  $$ UPDATE quote_event SET kind = 'signed'
     WHERE id = '71770000-0000-0000-0000-000000000d01' $$,
  '42501', NULL,
  '⭐ QE7 append-only : UPDATE interdit (permission denied sous nubia_app)');

-- ===========================================================================
-- QE8. Append-only : DELETE interdit sous nubia_app (42501).
-- ===========================================================================
SELECT throws_ok(
  $$ DELETE FROM quote_event
     WHERE id = '71770000-0000-0000-0000-000000000d01' $$,
  '42501', NULL,
  '⭐ QE8 append-only : DELETE interdit (permission denied sous nubia_app)');

-- ===========================================================================
-- QE9. Patient lié au devis 'sent' (non-draft) voit l'événement via
--      app.patient_account_id.
-- ===========================================================================
INSERT INTO app_user (id, email, password_hash, kind) VALUES
  ('71770000-0000-0000-0000-0000000000a2', 'patient.a.7177@nubia.test', '$argon2id$fixture', 'patient');
INSERT INTO patient_account (id, app_user_id, first_name, last_name) VALUES
  ('71770000-0000-0000-0000-0000000000b1', '71770000-0000-0000-0000-0000000000a2',
   'Patient', 'EventA');
UPDATE patient SET patient_account_id = '71770000-0000-0000-0000-0000000000b1'
  WHERE id = '71770000-0000-0000-0000-0000000000e1';

RESET app.current_cabinet_id;
SET LOCAL app.patient_account_id = '71770000-0000-0000-0000-0000000000b1';
SELECT is(
  (SELECT count(*)::int FROM quote_event
   WHERE id = '71770000-0000-0000-0000-000000000d01'),
  1,
  'QE9 quote_event_patient_read : patient voit l''événement de son devis ''sent''');

-- ===========================================================================
-- Fixtures : compte patient B, lié au patient du cabinet B, événements sur
-- son devis 'draft' (f2) et son devis 'sent' (f3).
-- ===========================================================================
RESET app.patient_account_id;
SET LOCAL app.current_cabinet_id = '71770000-0000-0000-0000-000000000c02';
INSERT INTO quote_event (id, quote_id, cabinet_id, kind, actor_kind) VALUES
  ('71770000-0000-0000-0000-000000000d02', '71770000-0000-0000-0000-0000000000f2',
   '71770000-0000-0000-0000-000000000c02', 'created', 'system');
INSERT INTO quote_event (id, quote_id, cabinet_id, kind, actor_kind) VALUES
  ('71770000-0000-0000-0000-000000000d03', '71770000-0000-0000-0000-0000000000f3',
   '71770000-0000-0000-0000-000000000c02', 'sent', 'cabinet');
INSERT INTO app_user (id, email, password_hash, kind) VALUES
  ('71770000-0000-0000-0000-0000000000a3', 'patient.b.7177@nubia.test', '$argon2id$fixture', 'patient');
INSERT INTO patient_account (id, app_user_id, first_name, last_name) VALUES
  ('71770000-0000-0000-0000-0000000000b2', '71770000-0000-0000-0000-0000000000a3',
   'Patient', 'EventB');
UPDATE patient SET patient_account_id = '71770000-0000-0000-0000-0000000000b2'
  WHERE id = '71770000-0000-0000-0000-0000000000e2';

-- ===========================================================================
-- QE10. Patient B ne voit PAS les événements de son PROPRE devis 'draft'.
-- ===========================================================================
RESET app.current_cabinet_id;
SET LOCAL app.patient_account_id = '71770000-0000-0000-0000-000000000b2';
SELECT is(
  (SELECT count(*)::int FROM quote_event
   WHERE id = '71770000-0000-0000-0000-000000000d02'),
  0,
  '⭐ QE10 quote_event_patient_read : patient ne voit PAS les événements de son propre devis draft');

-- ===========================================================================
-- QE11. Patient A ne voit PAS les événements du devis 'sent' du patient B.
-- ===========================================================================
SET LOCAL app.patient_account_id = '71770000-0000-0000-0000-000000000b1';
SELECT is(
  (SELECT count(*)::int FROM quote_event
   WHERE id = '71770000-0000-0000-0000-000000000d03'),
  0,
  '⭐ QE11 quote_event_patient_read : patient A ne voit PAS les événements du devis du patient B');

SELECT * FROM finish();
ROLLBACK;
