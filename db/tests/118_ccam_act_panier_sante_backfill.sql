-- 118_ccam_act_panier_sante_backfill.sql
-- pgTAP : ccam_act.panier_sante — garde-fou anti-régression (#6767).
-- #6767 : les 62 lignes du catalogue CCAM avaient `panier_sante` NULL
-- depuis la création de la colonne (0161), empêchant tout affichage du
-- bandeau réglementaire « alternative reste à charge zéro » (#4061). La
-- migration 0324 classe les actes prothétiques et endodontiques ; ce test
-- vérifie que ce trou de données ne se recreuse pas silencieusement.
--   AC1. Aucun acte `prothese` sans panier_sante.
--   AC2. Aucun acte `endo` sans panier_sante.
--   AC3. panier_sante, quand renseigné, respecte la liste autorisée (CHECK).
-- Exécuté par pg_prove sous nubia_app (NOSUPERUSER, NOBYPASSRLS).
-- Issue : #6767

BEGIN;
SELECT plan(3);

SELECT is(
  (SELECT count(*)::int FROM ccam_act WHERE category = 'prothese' AND panier_sante IS NULL),
  0,
  'AC1 ccam_act : aucun acte prothetique sans classification panier_sante (#6767)');

SELECT is(
  (SELECT count(*)::int FROM ccam_act WHERE category = 'endo' AND panier_sante IS NULL),
  0,
  'AC2 ccam_act : aucun acte d''endodontie sans classification panier_sante (#6767)');

SELECT is(
  (SELECT count(*)::int FROM ccam_act
     WHERE panier_sante IS NOT NULL
       AND panier_sante NOT IN ('rac0', 'modere', 'libre', 'hors_nomenclature')),
  0,
  'AC3 ccam_act : panier_sante renseigne appartient a la liste autorisee');

SELECT * FROM finish();
ROLLBACK;
