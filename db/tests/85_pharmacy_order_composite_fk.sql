-- 85_pharmacy_order_composite_fk.sql
-- pgTAP : FK composite tenant-scopée pharmacy_order.document_id/prescription_id
-- -> document/prescription(id, cabinet_id) et pharmacy_order.consent_record_id
-- -> consent_record(id, patient_account_id) — migration 0210, audit #4291.
--   PO1. Cabinet A crée une commande référençant son propre document/
--        prescription/consent_record (cas légitime).
--   PO2. Rattacher un document d'un AUTRE cabinet refusé (23503).
--   PO3. Rattacher une prescription d'un AUTRE cabinet refusé (23503).
--   PO4. Rattacher le consent_record d'un AUTRE patient refusé (23503).
--   PO5. consent_record_id NULL : insertion toujours acceptée (FK optionnelle).
--   PO6. Fail-closed : sans GUC -> 0 ligne sur pharmacy_order.
-- Chaque cas d'échec (PO2-PO4) utilise une prescription cabinet dédiée et
-- jamais consommée par un ordre actif ailleurs dans ce fichier — sinon
-- l'index unique partiel pharmacy_order_active_prescription (une seule
-- commande active par ordonnance) masquerait la violation de FK testée
-- (23505 levée avant que Postgres n'évalue la FK).
-- Exécuté par pg_prove sous nubia_app (NOSUPERUSER, NOBYPASSRLS).
-- Fixtures auto-contenues (BEGIN…ROLLBACK). Préfixe UUID 42910000-...-f.
-- Issue : #4291

BEGIN;
SELECT plan(6);

-- ===========================================================================
-- Fixtures : 2 cabinets (A, B), une pharmacie, 2 patients (un par cabinet),
-- document/prescription de A (f11/f21, consommée par PO1) + une seconde
-- prescription A inutilisée (f23, cible de l'exploit PO3), document/
-- prescription de B (f12/f22), consent_record de A (f31).
-- ===========================================================================
INSERT INTO app_user (id, email, kind, status) VALUES
  ('42910000-0000-0000-0000-0000000000a1', 'patient-po-a@demo-4291.test', 'patient', 'active'),
  ('42910000-0000-0000-0000-0000000000a2', 'patient-po-b@demo-4291.test', 'patient', 'active'),
  ('42910000-0000-0000-0000-0000000000a3', 'praticien-po-a@demo-4291.test', 'pro', 'active'),
  ('42910000-0000-0000-0000-0000000000a4', 'praticien-po-b@demo-4291.test', 'pro', 'active');
INSERT INTO patient_account (id, app_user_id, first_name, last_name) VALUES
  ('42910000-0000-0000-0000-0000000000b1', '42910000-0000-0000-0000-0000000000a1', 'Jean', 'PoA'),
  ('42910000-0000-0000-0000-0000000000b2', '42910000-0000-0000-0000-0000000000a2', 'Marie', 'PoB');

SET LOCAL app.current_cabinet_id = '42910000-0000-0000-0000-000000000c11';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('42910000-0000-0000-0000-000000000c11', 'Cabinet PO-4291-A');
INSERT INTO patient (id, cabinet_id, first_name, last_name, patient_account_id) VALUES
  ('42910000-0000-0000-0000-000000000e11', '42910000-0000-0000-0000-000000000c11',
   'Jean', 'PoA', '42910000-0000-0000-0000-0000000000b1');
INSERT INTO practitioner (id, cabinet_id, user_id) VALUES
  ('42910000-0000-0000-0000-000000000d11', '42910000-0000-0000-0000-000000000c11',
   '42910000-0000-0000-0000-0000000000a3');
INSERT INTO document (id, cabinet_id, patient_id, category, storage_key, filename, mime_type, sha256, scan_status, uploaded_by, size_bytes) VALUES
  ('42910000-0000-0000-0000-000000000f11', '42910000-0000-0000-0000-000000000c11',
   '42910000-0000-0000-0000-000000000e11', 'ordonnance', 'sk-po-4291-a', 'ordo.pdf',
   'application/pdf', repeat('0', 64), 'clean', '42910000-0000-0000-0000-0000000000a3', 0);
INSERT INTO prescription (id, cabinet_id, patient_id, practitioner_id, status, document_id, signed_at) VALUES
  ('42910000-0000-0000-0000-000000000f21', '42910000-0000-0000-0000-000000000c11',
   '42910000-0000-0000-0000-000000000e11', '42910000-0000-0000-0000-000000000d11',
   'signed', '42910000-0000-0000-0000-000000000f11', now()),
  ('42910000-0000-0000-0000-000000000f23', '42910000-0000-0000-0000-000000000c11',
   '42910000-0000-0000-0000-000000000e11', '42910000-0000-0000-0000-000000000d11',
   'signed', NULL, now());
RESET app.current_cabinet_id;

SET LOCAL app.current_cabinet_id = '42910000-0000-0000-0000-000000000c12';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('42910000-0000-0000-0000-000000000c12', 'Cabinet PO-4291-B');
INSERT INTO patient (id, cabinet_id, first_name, last_name, patient_account_id) VALUES
  ('42910000-0000-0000-0000-000000000e12', '42910000-0000-0000-0000-000000000c12',
   'Marie', 'PoB', '42910000-0000-0000-0000-0000000000b2');
INSERT INTO practitioner (id, cabinet_id, user_id) VALUES
  ('42910000-0000-0000-0000-000000000d12', '42910000-0000-0000-0000-000000000c12',
   '42910000-0000-0000-0000-0000000000a4');
INSERT INTO document (id, cabinet_id, patient_id, category, storage_key, filename, mime_type, sha256, scan_status, uploaded_by, size_bytes) VALUES
  ('42910000-0000-0000-0000-000000000f12', '42910000-0000-0000-0000-000000000c12',
   '42910000-0000-0000-0000-000000000e12', 'ordonnance', 'sk-po-4291-b', 'ordo-b.pdf',
   'application/pdf', repeat('1', 64), 'clean', '42910000-0000-0000-0000-0000000000a4', 0);
INSERT INTO prescription (id, cabinet_id, patient_id, practitioner_id, status, document_id, signed_at) VALUES
  ('42910000-0000-0000-0000-000000000f22', '42910000-0000-0000-0000-000000000c12',
   '42910000-0000-0000-0000-000000000e12', '42910000-0000-0000-0000-000000000d12',
   'signed', '42910000-0000-0000-0000-000000000f12', now());
RESET app.current_cabinet_id;

SET LOCAL app.current_account_id = '42910000-0000-0000-0000-0000000000b1';
INSERT INTO consent_record (id, patient_account_id, purpose, granted, evidence) VALUES
  ('42910000-0000-0000-0000-000000000f31', '42910000-0000-0000-0000-0000000000b1',
   'partage_pharmacie', true, '{}');
RESET app.current_account_id;

SET LOCAL app.current_pharmacy_id = '42910000-0000-0000-0000-000000000f41';
INSERT INTO pharmacy (id, raison_sociale, is_listed) VALUES
  ('42910000-0000-0000-0000-000000000f41', 'Pharmacie PO-4291', true);
RESET app.current_pharmacy_id;

-- ===========================================================================
-- PO1. Cas légitime : cabinet A crée une commande référençant son propre
-- document/prescription/consent_record. Consomme le slot actif de f21.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '42910000-0000-0000-0000-000000000c11';
INSERT INTO pharmacy_order (id, pharmacy_id, cabinet_id, patient_account_id, prescription_id,
                            document_id, consent_record_id, created_by_kind, pharmacy_name, patient_display_name)
  VALUES ('42910000-0000-0000-0000-000000000f51', '42910000-0000-0000-0000-000000000f41',
          '42910000-0000-0000-0000-000000000c11', '42910000-0000-0000-0000-0000000000b1',
          '42910000-0000-0000-0000-000000000f21', '42910000-0000-0000-0000-000000000f11',
          '42910000-0000-0000-0000-000000000f31', 'practitioner', 'Pharmacie PO-4291', 'Jean P.');
SELECT is(
  (SELECT count(*)::int FROM pharmacy_order WHERE id = '42910000-0000-0000-0000-000000000f51'),
  1,
  'PO1 pharmacy_order : création cabinet A référençant ses propres document/prescription/consent OK');

-- ===========================================================================
-- PO2. Rattacher un document d'un AUTRE cabinet refusé (23503) — document a
-- RLS+FORCE RLS (0011) : la ligne du cabinet A est invisible sous le GUC B,
-- la FK échoue avant toute policy. Prescription B légitime (f22) pour
-- isoler la violation sur document_id uniquement.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '42910000-0000-0000-0000-000000000c12';
SELECT throws_ok(
  $$ INSERT INTO pharmacy_order (pharmacy_id, cabinet_id, patient_account_id, prescription_id,
                                 document_id, created_by_kind, pharmacy_name, patient_display_name)
     VALUES ('42910000-0000-0000-0000-000000000f41', '42910000-0000-0000-0000-000000000c12',
             '42910000-0000-0000-0000-0000000000b2', '42910000-0000-0000-0000-000000000f22',
             '42910000-0000-0000-0000-000000000f11', 'practitioner', 'Pharmacie PO-4291', 'Marie P.') $$,
  '23503', NULL,
  '⭐ PO2 pharmacy_order : rattacher un document d''un autre cabinet refusé (23503, RLS FK)');

-- ===========================================================================
-- PO3. Rattacher une prescription d'un AUTRE cabinet refusé (23503) —
-- document B légitime (f12), prescription A jamais consommée par un ordre
-- actif (f23) pour isoler la violation sur prescription_id uniquement.
-- ===========================================================================
SELECT throws_ok(
  $$ INSERT INTO pharmacy_order (pharmacy_id, cabinet_id, patient_account_id, prescription_id,
                                 document_id, created_by_kind, pharmacy_name, patient_display_name)
     VALUES ('42910000-0000-0000-0000-000000000f41', '42910000-0000-0000-0000-000000000c12',
             '42910000-0000-0000-0000-0000000000b2', '42910000-0000-0000-0000-000000000f23',
             '42910000-0000-0000-0000-000000000f12', 'practitioner', 'Pharmacie PO-4291', 'Marie P.') $$,
  '23503', NULL,
  '⭐ PO3 pharmacy_order : rattacher une prescription d''un autre cabinet refusé (23503, RLS FK)');

-- ===========================================================================
-- PO4. Rattacher le consent_record d'un AUTRE patient refusé (23503) —
-- consent_record n'a pas cabinet_id (plateforme, refactor 0017) : le risque
-- est cross-PATIENT, pas cross-cabinet. Document/prescription B légitimes
-- (f12/f22, ce dernier toujours libre : PO2 n'a jamais commité), seul le
-- consent_record_id référence le patient A.
-- ===========================================================================
SELECT throws_ok(
  $$ INSERT INTO pharmacy_order (pharmacy_id, cabinet_id, patient_account_id, prescription_id,
                                 document_id, consent_record_id, created_by_kind, pharmacy_name, patient_display_name)
     VALUES ('42910000-0000-0000-0000-000000000f41', '42910000-0000-0000-0000-000000000c12',
             '42910000-0000-0000-0000-0000000000b2', '42910000-0000-0000-0000-000000000f22',
             '42910000-0000-0000-0000-000000000f12', '42910000-0000-0000-0000-000000000f31',
             'practitioner', 'Pharmacie PO-4291', 'Marie P.') $$,
  '23503', NULL,
  '⭐ PO4 pharmacy_order : réutiliser le consent_record d''un autre patient refusé (23503, RLS FK)');

-- ===========================================================================
-- PO5. consent_record_id NULL : la commande reste créable (FK optionnelle,
-- MATCH SIMPLE — non vérifiée quand la colonne référençante est NULL).
-- f22 toujours libre : ni PO2 ni PO4 (tous deux en échec, rollback interne
-- de throws_ok) n'ont consommé son slot actif.
-- ===========================================================================
SELECT lives_ok(
  $$ INSERT INTO pharmacy_order (pharmacy_id, cabinet_id, patient_account_id, prescription_id,
                                 document_id, created_by_kind, pharmacy_name, patient_display_name)
     VALUES ('42910000-0000-0000-0000-000000000f41', '42910000-0000-0000-0000-000000000c12',
             '42910000-0000-0000-0000-0000000000b2', '42910000-0000-0000-0000-000000000f22',
             '42910000-0000-0000-0000-000000000f12', 'practitioner', 'Pharmacie PO-4291', 'Marie P.') $$,
  'PO5 pharmacy_order : consent_record_id NULL toujours accepté (FK optionnelle)');

-- ===========================================================================
-- PO6. Fail-closed : sans GUC -> 0 ligne sur pharmacy_order.
-- ===========================================================================
RESET app.current_cabinet_id;
SELECT is(
  (SELECT count(*)::int FROM pharmacy_order),
  0,
  '⭐ PO6 fail-closed : 0 ligne pharmacy_order sans GUC positionné');

SELECT * FROM finish();
ROLLBACK;
