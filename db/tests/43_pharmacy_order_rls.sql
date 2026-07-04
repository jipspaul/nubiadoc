-- 43_pharmacy_order_rls.sql — Contrat RLS pharmacy_order + document_pharmacy_read (issue #3307, lot B2).
-- Vérifie : isolation des 3 ancres (pharmacie/patient/cabinet) · non-fuite cross-pharmacie ·
-- document visible uniquement par la pharmacie destinataire · WITH CHECK (pharmacie ne forge
-- pas d'annulation, patient ne forge pas picked_up/rejected, pas de changement de tenant) ·
-- index unique partiel (une commande active par ordonnance) · pas de DELETE pour l'app.
-- Exécuté par pg_prove sous nubia_app. Fixtures auto-containées (BEGIN…ROLLBACK). Préfixe 33070000.

BEGIN;
SELECT * FROM no_plan();

-- ===========================================================================
-- Fixtures : cabinet A + patient (compte lié) + ordonnance signée + document ;
-- pharmacies X (destinataire) et Y (témoin) ; une commande X.
-- ===========================================================================
INSERT INTO app_user (id, email, kind, status)
  VALUES ('33070000-0000-0000-0000-0000000000a1', 'patient-b2@demo-3307.test', 'patient', 'active')
  ON CONFLICT DO NOTHING;
INSERT INTO app_user (id, email, kind, status)
  VALUES ('33070000-0000-0000-0000-0000000000a2', 'praticien-b2@demo-3307.test', 'pro', 'active')
  ON CONFLICT DO NOTHING;
INSERT INTO patient_account (id, app_user_id, first_name, last_name)
  VALUES ('33070000-0000-0000-0000-0000000000b1', '33070000-0000-0000-0000-0000000000a1', 'Jean', 'Demo')
  ON CONFLICT DO NOTHING;

SET LOCAL app.current_cabinet_id = '33070000-0000-0000-0000-000000000001';
INSERT INTO cabinet (id, raison_sociale)
  VALUES ('33070000-0000-0000-0000-000000000001', 'Cabinet B2-A')
  ON CONFLICT DO NOTHING;
INSERT INTO patient (id, cabinet_id, first_name, last_name, patient_account_id)
  VALUES ('33070000-0000-0000-0000-000000000011', '33070000-0000-0000-0000-000000000001',
          'Jean', 'Demo', '33070000-0000-0000-0000-0000000000b1')
  ON CONFLICT DO NOTHING;
INSERT INTO practitioner (id, cabinet_id, user_id)
  VALUES ('33070000-0000-0000-0000-000000000021', '33070000-0000-0000-0000-000000000001',
          '33070000-0000-0000-0000-0000000000a2')
  ON CONFLICT DO NOTHING;
INSERT INTO document (id, cabinet_id, patient_id, category, storage_key, filename, mime_type, sha256, scan_status, uploaded_by, size_bytes)
  VALUES ('33070000-0000-0000-0000-000000000031', '33070000-0000-0000-0000-000000000001',
          '33070000-0000-0000-0000-000000000011', 'ordonnance', 'sk-3307', 'ordo.pdf',
          'application/pdf', repeat('0', 64), 'clean', '33070000-0000-0000-0000-0000000000a2', 0)
  ON CONFLICT DO NOTHING;
INSERT INTO prescription (id, cabinet_id, patient_id, practitioner_id, status, document_id, signed_at)
  VALUES ('33070000-0000-0000-0000-000000000041', '33070000-0000-0000-0000-000000000001',
          '33070000-0000-0000-0000-000000000011', '33070000-0000-0000-0000-000000000021',
          'signed', '33070000-0000-0000-0000-000000000031', now())
  ON CONFLICT DO NOTHING;

SET LOCAL app.current_pharmacy_id = '33070000-0000-0000-0000-0000000000f1';
INSERT INTO pharmacy (id, raison_sociale, is_listed)
  VALUES ('33070000-0000-0000-0000-0000000000f1', 'Pharmacie B2-X', true)
  ON CONFLICT DO NOTHING;
SET LOCAL app.current_pharmacy_id = '33070000-0000-0000-0000-0000000000f2';
INSERT INTO pharmacy (id, raison_sociale, is_listed)
  VALUES ('33070000-0000-0000-0000-0000000000f2', 'Pharmacie B2-Y', true)
  ON CONFLICT DO NOTHING;
RESET app.current_pharmacy_id;

-- La commande est créée par le cabinet A (policy cabinet_insert).
SET LOCAL app.current_cabinet_id = '33070000-0000-0000-0000-000000000001';
INSERT INTO pharmacy_order (id, pharmacy_id, cabinet_id, patient_account_id, prescription_id,
                            document_id, created_by_kind, pharmacy_name, patient_display_name)
  VALUES ('33070000-0000-0000-0000-000000000051', '33070000-0000-0000-0000-0000000000f1',
          '33070000-0000-0000-0000-000000000001', '33070000-0000-0000-0000-0000000000b1',
          '33070000-0000-0000-0000-000000000041', '33070000-0000-0000-0000-000000000031',
          'practitioner', 'Pharmacie B2-X', 'Jean D.')
  ON CONFLICT DO NOTHING;
RESET app.current_cabinet_id;

-- ===========================================================================
-- 1. FAIL-CLOSED : aucun GUC -> 0 ligne.
-- ===========================================================================
SELECT is(
  (SELECT count(*)::int FROM pharmacy_order WHERE id = '33070000-0000-0000-0000-000000000051'),
  0, '⭐ fail-closed : commande invisible sans GUC');

-- ===========================================================================
-- 2. Pharmacie destinataire voit ; pharmacie témoin ne voit pas.
-- ===========================================================================
SET LOCAL app.current_pharmacy_id = '33070000-0000-0000-0000-0000000000f1';
SELECT is(
  (SELECT count(*)::int FROM pharmacy_order WHERE id = '33070000-0000-0000-0000-000000000051'),
  1, 'pharmacie X : voit sa commande');
SET LOCAL app.current_pharmacy_id = '33070000-0000-0000-0000-0000000000f2';
SELECT is(
  (SELECT count(*)::int FROM pharmacy_order WHERE id = '33070000-0000-0000-0000-000000000051'),
  0, '⭐ non-fuite : pharmacie Y ne voit PAS la commande de X');
RESET app.current_pharmacy_id;

-- ===========================================================================
-- 3. Patient titulaire voit ; autre compte ne voit pas.
-- ===========================================================================
SET LOCAL app.patient_account_id = '33070000-0000-0000-0000-0000000000b1';
SELECT is(
  (SELECT count(*)::int FROM pharmacy_order WHERE id = '33070000-0000-0000-0000-000000000051'),
  1, 'patient titulaire : voit sa commande');
SET LOCAL app.patient_account_id = '33070000-0000-0000-0000-0000000000b9';
SELECT is(
  (SELECT count(*)::int FROM pharmacy_order WHERE id = '33070000-0000-0000-0000-000000000051'),
  0, '⭐ non-fuite : autre compte patient ne voit rien');
RESET app.patient_account_id;

-- ===========================================================================
-- 4. Cabinet d'origine voit ; autre cabinet ne voit pas.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '33070000-0000-0000-0000-000000000001';
SELECT is(
  (SELECT count(*)::int FROM pharmacy_order WHERE id = '33070000-0000-0000-0000-000000000051'),
  1, 'cabinet d''origine : voit la commande');
SET LOCAL app.current_cabinet_id = '33070000-0000-0000-0000-000000000002';
SELECT is(
  (SELECT count(*)::int FROM pharmacy_order WHERE id = '33070000-0000-0000-0000-000000000051'),
  0, '⭐ non-fuite : autre cabinet ne voit rien');
RESET app.current_cabinet_id;

-- ===========================================================================
-- 5. document_pharmacy_read : seule la pharmacie destinataire lit le PDF.
-- ===========================================================================
SET LOCAL app.current_pharmacy_id = '33070000-0000-0000-0000-0000000000f1';
SELECT is(
  (SELECT count(*)::int FROM document WHERE id = '33070000-0000-0000-0000-000000000031'),
  1, 'pharmacie X : lit le document de sa commande');
SET LOCAL app.current_pharmacy_id = '33070000-0000-0000-0000-0000000000f2';
SELECT is(
  (SELECT count(*)::int FROM document WHERE id = '33070000-0000-0000-0000-000000000031'),
  0, '⭐ cloisonnement : pharmacie Y ne lit PAS le document');
-- La pharmacie ne voit JAMAIS les tables cliniques (prescription).
SET LOCAL app.current_pharmacy_id = '33070000-0000-0000-0000-0000000000f1';
SELECT is(
  (SELECT count(*)::int FROM prescription WHERE id = '33070000-0000-0000-0000-000000000041'),
  0, '⭐ cloisonnement : la pharmacie ne lit pas la table prescription');
RESET app.current_pharmacy_id;

-- ===========================================================================
-- 6. WITH CHECK : transitions interdites par acteur.
-- ===========================================================================
SET LOCAL app.current_pharmacy_id = '33070000-0000-0000-0000-0000000000f1';
SELECT throws_ok(
  $$ UPDATE pharmacy_order SET status = 'cancelled'
     WHERE id = '33070000-0000-0000-0000-000000000051' $$,
  '42501', NULL,
  '⭐ WITH CHECK : la pharmacie ne peut pas forger une annulation');
SELECT throws_ok(
  $$ UPDATE pharmacy_order SET pharmacy_id = '33070000-0000-0000-0000-0000000000f2'
     WHERE id = '33070000-0000-0000-0000-000000000051' $$,
  '42501', NULL,
  '⭐ WITH CHECK : la pharmacie ne peut pas transférer la commande');
RESET app.current_pharmacy_id;

SET LOCAL app.patient_account_id = '33070000-0000-0000-0000-0000000000b1';
SELECT throws_ok(
  $$ UPDATE pharmacy_order SET status = 'picked_up'
     WHERE id = '33070000-0000-0000-0000-000000000051' $$,
  '42501', NULL,
  '⭐ WITH CHECK : le patient ne peut pas forger un retrait');
SELECT throws_ok(
  $$ UPDATE pharmacy_order SET status = 'rejected'
     WHERE id = '33070000-0000-0000-0000-000000000051' $$,
  '42501', NULL,
  '⭐ WITH CHECK : le patient ne peut pas forger un refus');
RESET app.patient_account_id;

-- ===========================================================================
-- 7. Une seule commande active par ordonnance (index unique partiel).
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '33070000-0000-0000-0000-000000000001';
SELECT throws_ok(
  $$ INSERT INTO pharmacy_order (pharmacy_id, cabinet_id, patient_account_id, prescription_id,
                                 document_id, created_by_kind, pharmacy_name, patient_display_name)
     VALUES ('33070000-0000-0000-0000-0000000000f1', '33070000-0000-0000-0000-000000000001',
             '33070000-0000-0000-0000-0000000000b1', '33070000-0000-0000-0000-000000000041',
             '33070000-0000-0000-0000-000000000031', 'practitioner', 'Pharmacie B2-X', 'Jean D.') $$,
  '23505', NULL,
  '⭐ unicité : pas de seconde commande active pour la même ordonnance');

-- ===========================================================================
-- 8. Append-only : pas de DELETE pour nubia_app.
-- ===========================================================================
SELECT throws_ok(
  $$ DELETE FROM pharmacy_order WHERE id = '33070000-0000-0000-0000-000000000051' $$,
  '42501', NULL,
  '⭐ pas de DELETE sur pharmacy_order pour nubia_app');
RESET app.current_cabinet_id;

SELECT * FROM finish();
ROLLBACK;
