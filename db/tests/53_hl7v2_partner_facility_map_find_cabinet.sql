-- 53_hl7v2_partner_facility_map_find_cabinet.sql — Contrat de
-- hl7v2_partner_facility_map_find_cabinet (lot B6-fix, complète 0151).
-- SECURITY DEFINER : doit résoudre sans aucun GUC posé (c'est tout son
-- intérêt — appelée par le dispatch HL7v2 avant que le cabinet cible ne soit
-- connu). Vérifie : couple connu -> cabinet_id correct · couple inconnu ->
-- aucune ligne (jamais une erreur) · exécutable par nubia_app.
-- Exécuté par pg_prove sous nubia_app. Fixtures BEGIN…ROLLBACK.

BEGIN;
SELECT * FROM no_plan();

SET LOCAL app.current_cabinet_id = '05300000-0000-0000-0000-000000000001';
INSERT INTO cabinet (id, raison_sociale)
  VALUES ('05300000-0000-0000-0000-000000000001', 'Cabinet 53-fn')
  ON CONFLICT DO NOTHING;
RESET app.current_cabinet_id;

INSERT INTO hl7v2_partner (id, display_name, cert_fingerprint_sha256, status)
  VALUES ('05300000-0000-0000-0000-0000000000a1', 'EAI Labo 53-fn',
          'c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3', 'active')
  ON CONFLICT DO NOTHING;

SET LOCAL app.current_cabinet_id = '05300000-0000-0000-0000-000000000001';
INSERT INTO hl7v2_partner_facility_map (id, partner_id, sending_facility, receiving_facility, cabinet_id)
  VALUES ('05300000-0000-0000-0000-000000000051',
          '05300000-0000-0000-0000-0000000000a1', 'SIH53', 'NUBIA53',
          '05300000-0000-0000-0000-000000000001')
  ON CONFLICT DO NOTHING;
RESET app.current_cabinet_id;

-- Aucun GUC posé ici — exactement les conditions d'appel réelles du dispatch.
SELECT is(
  (SELECT cabinet_id FROM hl7v2_partner_facility_map_find_cabinet(
    '05300000-0000-0000-0000-0000000000a1', 'SIH53', 'NUBIA53')),
  '05300000-0000-0000-0000-000000000001'::uuid,
  'couple partenaire/facility connu -> cabinet_id correct, sans GUC');

SELECT is(
  (SELECT count(*)::int FROM hl7v2_partner_facility_map_find_cabinet(
    '05300000-0000-0000-0000-0000000000a1', 'INCONNU', 'NUBIA53')),
  0,
  '⭐ couple facility inconnu -> aucune ligne (jamais une erreur)');

SELECT is(
  (SELECT count(*)::int FROM hl7v2_partner_facility_map_find_cabinet(
    '00000000-0000-0000-0000-000000000000', 'SIH53', 'NUBIA53')),
  0,
  'partenaire inconnu -> aucune ligne');

SELECT * FROM finish();
ROLLBACK;
