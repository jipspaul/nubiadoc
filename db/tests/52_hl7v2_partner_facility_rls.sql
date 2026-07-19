-- 52_hl7v2_partner_facility_rls.sql — Contrat RLS hl7v2_partner_facility_map
-- (lot B6, interop HL7v2/MLLP). Vérifie : fail-closed · isolation cross-cabinet
-- en SELECT et INSERT (WITH CHECK) · les fonctions SECURITY DEFINER
-- hl7v2_partner_find_by_fingerprint / hl7v2_message_log_check_and_insert
-- fonctionnent sans aucun GUC posé (c'est tout leur intérêt : elles tournent
-- avant résolution du cabinet). hl7v2_partner et hl7v2_message_log sont des
-- tables plateforme (pas de cabinet_id) : rien à tester côté RLS pour elles.
-- Exécuté par pg_prove sous nubia_app. Fixtures BEGIN…ROLLBACK. Préfixe 01480000.

BEGIN;
SELECT * FROM no_plan();

-- Fixtures : cabinet A (propriétaire de l'association) + cabinet B (témoin).
SET LOCAL app.current_cabinet_id = '01480000-0000-0000-0000-000000000001';
INSERT INTO cabinet (id, raison_sociale)
  VALUES ('01480000-0000-0000-0000-000000000001', 'Cabinet B6-A')
  ON CONFLICT DO NOTHING;
RESET app.current_cabinet_id;
SET LOCAL app.current_cabinet_id = '01480000-0000-0000-0000-000000000002';
INSERT INTO cabinet (id, raison_sociale)
  VALUES ('01480000-0000-0000-0000-000000000002', 'Cabinet B6-B')
  ON CONFLICT DO NOTHING;
RESET app.current_cabinet_id;

-- Partenaire HL7v2 actif + un partenaire révoqué (table plateforme, pas de GUC).
INSERT INTO hl7v2_partner (id, display_name, cert_fingerprint_sha256, status)
  VALUES ('01480000-0000-0000-0000-0000000000a1', 'EAI Labo B6',
          'a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1', 'active')
  ON CONFLICT DO NOTHING;
INSERT INTO hl7v2_partner (id, display_name, cert_fingerprint_sha256, status)
  VALUES ('01480000-0000-0000-0000-0000000000a2', 'EAI Labo B6 révoqué',
          'b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2', 'revoked')
  ON CONFLICT DO NOTHING;

-- Association partenaire <-> cabinet A pour (MSH-4, MSH-6) = (LABX, NUBIA).
SET LOCAL app.current_cabinet_id = '01480000-0000-0000-0000-000000000001';
INSERT INTO hl7v2_partner_facility_map (id, partner_id, sending_facility, receiving_facility, cabinet_id)
  VALUES ('01480000-0000-0000-0000-000000000051',
          '01480000-0000-0000-0000-0000000000a1', 'LABX', 'NUBIA',
          '01480000-0000-0000-0000-000000000001')
  ON CONFLICT DO NOTHING;
RESET app.current_cabinet_id;

-- ===========================================================================
-- 1. Fail-closed sans GUC.
-- ===========================================================================
SELECT is(
  (SELECT count(*)::int FROM hl7v2_partner_facility_map
   WHERE id = '01480000-0000-0000-0000-000000000051'),
  0, '⭐ fail-closed : association invisible sans GUC');

-- ===========================================================================
-- 2. Isolation cross-cabinet en SELECT.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '01480000-0000-0000-0000-000000000001';
SELECT is(
  (SELECT count(*)::int FROM hl7v2_partner_facility_map
   WHERE id = '01480000-0000-0000-0000-000000000051'),
  1, 'cabinet A : voit son association');
RESET app.current_cabinet_id;

SET LOCAL app.current_cabinet_id = '01480000-0000-0000-0000-000000000002';
SELECT is(
  (SELECT count(*)::int FROM hl7v2_partner_facility_map
   WHERE id = '01480000-0000-0000-0000-000000000051'),
  0, '⭐ non-fuite : cabinet B ne voit pas l''association de A');
RESET app.current_cabinet_id;

-- ===========================================================================
-- 3. WITH CHECK : INSERT cross-cabinet refusé (cabinet B ne peut pas créer
-- une association pour cabinet A).
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '01480000-0000-0000-0000-000000000002';
SELECT throws_ok(
  $$ INSERT INTO hl7v2_partner_facility_map
       (id, partner_id, sending_facility, receiving_facility, cabinet_id)
     VALUES ('01480000-0000-0000-0000-000000000052',
             '01480000-0000-0000-0000-0000000000a1', 'LABY', 'NUBIA',
             '01480000-0000-0000-0000-000000000001') $$,
  '42501', NULL,
  '⭐ WITH CHECK : cabinet B ne peut pas créer une association pour cabinet A');
RESET app.current_cabinet_id;

-- ===========================================================================
-- 4. INSERT même-cabinet accepté.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '01480000-0000-0000-0000-000000000002';
INSERT INTO hl7v2_partner_facility_map
    (id, partner_id, sending_facility, receiving_facility, cabinet_id)
  VALUES ('01480000-0000-0000-0000-000000000053',
          '01480000-0000-0000-0000-0000000000a1', 'LABX', 'NUBIA',
          '01480000-0000-0000-0000-000000000002');
SELECT is(
  (SELECT count(*)::int FROM hl7v2_partner_facility_map
   WHERE id = '01480000-0000-0000-0000-000000000053'),
  1, 'cabinet B : peut créer sa propre association pour le même partenaire');
RESET app.current_cabinet_id;

-- ===========================================================================
-- 5. hl7v2_partner_find_by_fingerprint : SECURITY DEFINER, sans aucun GUC.
-- ===========================================================================
SELECT is(
  (SELECT id FROM hl7v2_partner_find_by_fingerprint(
    'a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1')),
  '01480000-0000-0000-0000-0000000000a1'::uuid,
  'hl7v2_partner_find_by_fingerprint : résout le partenaire actif sans GUC (SECURITY DEFINER)');

SELECT is(
  (SELECT id FROM hl7v2_partner_find_by_fingerprint(
    'b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2')),
  NULL::uuid,
  '⭐ hl7v2_partner_find_by_fingerprint : un partenaire révoqué n''est jamais résolu');

SELECT is(
  (SELECT id FROM hl7v2_partner_find_by_fingerprint(
    'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff')),
  NULL::uuid,
  'hl7v2_partner_find_by_fingerprint : empreinte inconnue -> aucun partenaire');

-- ===========================================================================
-- 6. hl7v2_message_log_check_and_insert : atomique, sans aucun GUC.
-- ===========================================================================
SELECT is(
  hl7v2_message_log_check_and_insert(
    '01480000-0000-0000-0000-0000000000a1', 'MSG-CTRL-0001'),
  true,
  'hl7v2_message_log_check_and_insert : premier passage -> message frais (true)');

SELECT is(
  hl7v2_message_log_check_and_insert(
    '01480000-0000-0000-0000-0000000000a1', 'MSG-CTRL-0001'),
  false,
  '⭐ hl7v2_message_log_check_and_insert : rejeu du même message -> doublon (false)');

SELECT is(
  hl7v2_message_log_check_and_insert(
    '01480000-0000-0000-0000-0000000000a1', 'MSG-CTRL-0002'),
  true,
  'hl7v2_message_log_check_and_insert : control_id différent -> message frais (true)');

-- Même control_id mais partenaire différent : pas un doublon (unique par partner_id).
SELECT is(
  hl7v2_message_log_check_and_insert(
    '01480000-0000-0000-0000-0000000000a2', 'MSG-CTRL-0001'),
  true,
  'hl7v2_message_log_check_and_insert : même control_id, partenaire différent -> pas un doublon');

SELECT * FROM finish();
ROLLBACK;
