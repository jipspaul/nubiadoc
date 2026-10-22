-- 117_pharmacy_order_item_prepared_rls.sql — Contrat RLS pharmacy_order_item_prepared (#8340).
-- Vérifie : la case « sortie des rayons » est bornée À LA COMMANDE (pas à
-- l'ordonnance) · la pharmacie destinataire lit/coche/décoche ses lignes ·
-- une pharmacie témoin (autre officine) n'en voit rien · WITH CHECK interdit
-- de forger une case sur la commande d'une autre officine · le patient lit
-- en lecture seule ses propres commandes, jamais en écriture · fail-closed
-- sans GUC · une commande neuve sur LA MÊME ordonnance ne porte aucune case
-- héritée (cœur du bug #8340 : avant ce fix, la case était stockée sur
-- prescription_item et survivait au cycle de vie de la commande).
-- Exécuté par pg_prove sous nubia_app. Fixtures auto-containées (BEGIN…ROLLBACK).
-- Préfixe 83400000.

BEGIN;
SELECT * FROM no_plan();

-- ===========================================================================
-- Fixtures : cabinet + patient (compte lié) + ordonnance signée + document +
-- 2 lignes ; pharmacies X (destinataire) et Y (témoin) ; une commande X.
-- ===========================================================================
INSERT INTO app_user (id, email, kind, status)
  VALUES ('83400000-0000-0000-0000-0000000000a1', 'patient-8340@demo.test', 'patient', 'active')
  ON CONFLICT DO NOTHING;
INSERT INTO app_user (id, email, kind, status)
  VALUES ('83400000-0000-0000-0000-0000000000a2', 'praticien-8340@demo.test', 'pro', 'active')
  ON CONFLICT DO NOTHING;
INSERT INTO patient_account (id, app_user_id, first_name, last_name)
  VALUES ('83400000-0000-0000-0000-0000000000b1', '83400000-0000-0000-0000-0000000000a1', 'Marc', 'Demo')
  ON CONFLICT DO NOTHING;

SET LOCAL app.current_cabinet_id = '83400000-0000-0000-0000-000000000001';
INSERT INTO cabinet (id, raison_sociale)
  VALUES ('83400000-0000-0000-0000-000000000001', 'Cabinet 8340')
  ON CONFLICT DO NOTHING;
INSERT INTO patient (id, cabinet_id, first_name, last_name, patient_account_id)
  VALUES ('83400000-0000-0000-0000-000000000011', '83400000-0000-0000-0000-000000000001',
          'Marc', 'Demo', '83400000-0000-0000-0000-0000000000b1')
  ON CONFLICT DO NOTHING;
INSERT INTO practitioner (id, cabinet_id, user_id)
  VALUES ('83400000-0000-0000-0000-000000000021', '83400000-0000-0000-0000-000000000001',
          '83400000-0000-0000-0000-0000000000a2')
  ON CONFLICT DO NOTHING;
INSERT INTO document (id, cabinet_id, patient_id, category, storage_key, filename, mime_type, sha256, scan_status, uploaded_by, size_bytes)
  VALUES ('83400000-0000-0000-0000-000000000031', '83400000-0000-0000-0000-000000000001',
          '83400000-0000-0000-0000-000000000011', 'ordonnance', 'sk-8340', 'ordo.pdf',
          'application/pdf', repeat('0', 64), 'clean', '83400000-0000-0000-0000-0000000000a2', 0)
  ON CONFLICT DO NOTHING;
INSERT INTO prescription (id, cabinet_id, patient_id, practitioner_id, status, document_id, signed_at)
  VALUES ('83400000-0000-0000-0000-000000000041', '83400000-0000-0000-0000-000000000001',
          '83400000-0000-0000-0000-000000000011', '83400000-0000-0000-0000-000000000021',
          'signed', '83400000-0000-0000-0000-000000000031', now())
  ON CONFLICT DO NOTHING;
INSERT INTO prescription_item (id, cabinet_id, prescription_id, label, posology, duration, quantity)
  VALUES ('83400000-0000-0000-0000-000000000061', '83400000-0000-0000-0000-000000000001',
          '83400000-0000-0000-0000-000000000041', 'Ibuprofene 400mg', '1 cp x3/j', '5 jours', '15 cp')
  ON CONFLICT DO NOTHING;
INSERT INTO prescription_item (id, cabinet_id, prescription_id, label, posology, duration, quantity)
  VALUES ('83400000-0000-0000-0000-000000000062', '83400000-0000-0000-0000-000000000001',
          '83400000-0000-0000-0000-000000000041', 'Spasfon', '1 cp x3/j', '5 jours', '15 cp')
  ON CONFLICT DO NOTHING;
RESET app.current_cabinet_id;

SET LOCAL app.current_pharmacy_id = '83400000-0000-0000-0000-0000000000f1';
INSERT INTO pharmacy (id, raison_sociale, is_listed)
  VALUES ('83400000-0000-0000-0000-0000000000f1', 'Pharmacie 8340-X', true)
  ON CONFLICT DO NOTHING;
SET LOCAL app.current_pharmacy_id = '83400000-0000-0000-0000-0000000000f2';
INSERT INTO pharmacy (id, raison_sociale, is_listed)
  VALUES ('83400000-0000-0000-0000-0000000000f2', 'Pharmacie 8340-Y', true)
  ON CONFLICT DO NOTHING;
RESET app.current_pharmacy_id;

SET LOCAL app.current_cabinet_id = '83400000-0000-0000-0000-000000000001';
INSERT INTO pharmacy_order (id, pharmacy_id, cabinet_id, patient_account_id, prescription_id,
                            document_id, created_by_kind, pharmacy_name, patient_display_name)
  VALUES ('83400000-0000-0000-0000-000000000051', '83400000-0000-0000-0000-0000000000f1',
          '83400000-0000-0000-0000-000000000001', '83400000-0000-0000-0000-0000000000b1',
          '83400000-0000-0000-0000-000000000041', '83400000-0000-0000-0000-000000000031',
          'practitioner', 'Pharmacie 8340-X', 'Marc D.')
  ON CONFLICT DO NOTHING;
RESET app.current_cabinet_id;

-- ===========================================================================
-- 1. Fail-closed : aucun GUC -> 0 ligne, même après que X a coché.
-- ===========================================================================
SET LOCAL app.current_pharmacy_id = '83400000-0000-0000-0000-0000000000f1';
SELECT lives_ok(
  $$ INSERT INTO pharmacy_order_item_prepared (order_id, prescription_item_id)
     VALUES ('83400000-0000-0000-0000-000000000051', '83400000-0000-0000-0000-000000000061') $$,
  '⭐ la pharmacie destinataire coche la ligne de SA commande');
RESET app.current_pharmacy_id;

SELECT is(
  (SELECT count(*)::int FROM pharmacy_order_item_prepared
   WHERE order_id = '83400000-0000-0000-0000-000000000051'),
  0, '⭐ fail-closed : case invisible sans GUC');

-- ===========================================================================
-- 2. Pharmacie témoin (autre officine) ne voit pas la case cochée par X.
-- ===========================================================================
SET LOCAL app.current_pharmacy_id = '83400000-0000-0000-0000-0000000000f2';
SELECT is(
  (SELECT count(*)::int FROM pharmacy_order_item_prepared
   WHERE order_id = '83400000-0000-0000-0000-000000000051'),
  0, '⭐ pharmacie témoin ne voit pas la case cochée par X');

-- WITH CHECK : Y ne peut pas forger une case sur la commande de X.
SELECT throws_ok(
  $$ INSERT INTO pharmacy_order_item_prepared (order_id, prescription_item_id)
     VALUES ('83400000-0000-0000-0000-000000000051', '83400000-0000-0000-0000-000000000062') $$,
  '42501', NULL,
  '⭐ WITH CHECK : une pharmacie témoin ne peut pas cocher la commande d''une autre officine');
RESET app.current_pharmacy_id;

-- ===========================================================================
-- 3. Pharmacie destinataire voit sa propre case ; patient la lit, en lecture
--    seule (ne peut pas la décocher).
-- ===========================================================================
SET LOCAL app.current_pharmacy_id = '83400000-0000-0000-0000-0000000000f1';
SELECT is(
  (SELECT count(*)::int FROM pharmacy_order_item_prepared
   WHERE order_id = '83400000-0000-0000-0000-000000000051'),
  1, '⭐ pharmacie destinataire voit sa propre case cochée');
RESET app.current_pharmacy_id;

SET LOCAL app.patient_account_id = '83400000-0000-0000-0000-0000000000b1';
SELECT is(
  (SELECT count(*)::int FROM pharmacy_order_item_prepared
   WHERE order_id = '83400000-0000-0000-0000-000000000051'),
  1, '⭐ le patient lit la case de sa propre commande');
SELECT throws_ok(
  $$ DELETE FROM pharmacy_order_item_prepared
     WHERE order_id = '83400000-0000-0000-0000-000000000051' $$,
  '42501', NULL,
  '⭐ le patient ne peut pas décocher (lecture seule)');
RESET app.patient_account_id;

-- ===========================================================================
-- 4. Décocher : la pharmacie destinataire supprime sa propre case.
-- ===========================================================================
SET LOCAL app.current_pharmacy_id = '83400000-0000-0000-0000-0000000000f1';
SELECT lives_ok(
  $$ DELETE FROM pharmacy_order_item_prepared
     WHERE order_id = '83400000-0000-0000-0000-000000000051'
       AND prescription_item_id = '83400000-0000-0000-0000-000000000061' $$,
  '⭐ la pharmacie décoche sa propre ligne');
SELECT is(
  (SELECT count(*)::int FROM pharmacy_order_item_prepared
   WHERE order_id = '83400000-0000-0000-0000-000000000051'),
  0, '⭐ la ligne décochée disparaît');

-- ===========================================================================
-- 5. #8340 (cœur du bug) : une commande NEUVE sur LA MÊME ordonnance (même
--    pharmacie X) ne porte aucune case héritée. Avant ce fix, la case
--    (stockée sur prescription_item) survivait au cycle de vie de la
--    commande et une commande neuve naissait déjà « préparée ».
-- ===========================================================================
SELECT lives_ok(
  $$ INSERT INTO pharmacy_order_item_prepared (order_id, prescription_item_id)
     VALUES ('83400000-0000-0000-0000-000000000051', '83400000-0000-0000-0000-000000000061') $$,
  '⭐ (re)coche la ligne sur la commande d''origine (état avant refus)');
SELECT lives_ok(
  $$ UPDATE pharmacy_order SET status = 'rejected' WHERE id = '83400000-0000-0000-0000-000000000051' $$,
  '⭐ la pharmacie refuse la commande (libère l''ordonnance côté patient)');
RESET app.current_pharmacy_id;

SET LOCAL app.current_cabinet_id = '83400000-0000-0000-0000-000000000001';
INSERT INTO pharmacy_order (id, pharmacy_id, cabinet_id, patient_account_id, prescription_id,
                            document_id, created_by_kind, pharmacy_name, patient_display_name)
  VALUES ('83400000-0000-0000-0000-000000000052', '83400000-0000-0000-0000-0000000000f1',
          '83400000-0000-0000-0000-000000000001', '83400000-0000-0000-0000-0000000000b1',
          '83400000-0000-0000-0000-000000000041', '83400000-0000-0000-0000-000000000031',
          'practitioner', 'Pharmacie 8340-X', 'Marc D.')
  ON CONFLICT DO NOTHING;
RESET app.current_cabinet_id;

SET LOCAL app.current_pharmacy_id = '83400000-0000-0000-0000-0000000000f1';
SELECT is(
  (SELECT count(*)::int FROM pharmacy_order_item_prepared
   WHERE order_id = '83400000-0000-0000-0000-000000000052'),
  0, '⭐ #8340 : une commande neuve sur la même ordonnance ne porte aucune case héritée');
-- La commande rejetée garde sa trace comptoir (pas de régression sur #7013).
SELECT is(
  (SELECT count(*)::int FROM pharmacy_order_item_prepared
   WHERE order_id = '83400000-0000-0000-0000-000000000051'),
  1, '⭐ la commande rejetée garde sa trace comptoir (#7013)');
RESET app.current_pharmacy_id;

SELECT * FROM finish();
ROLLBACK;
