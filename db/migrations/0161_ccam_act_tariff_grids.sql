-- 0161_ccam_act_tariff_grids.sql
-- ccam_act n'avait qu'un tarif_cents unique — aucune variante secteur 1/2,
-- OPTAM, ni classification panier 100% Santé (RAC 0/modéré/libre), pourtant
-- requise par l'obligation conventionnelle de présenter l'alternative
-- RAC 0 dans le devis (#4055).
--
-- `tarif_cents` (déjà exploité par consultations.rs/ngap_acts.rs et le
-- front, ccam_picker.dart) reste inchangé — c'est le tarif de référence
-- utilisé pour préremplir la saisie d'un acte, pas touché ici pour éviter
-- une migration à large rayon d'impact. Cette migration AJOUTE les colonnes
-- de grille tarifaire à côté.
--
-- `secteur1_cents` est rétro-rempli depuis `tarif_cents` pour les lignes
-- existantes : la base conventionnelle secteur 1 EST la donnée déjà stockée
-- dans `tarif_cents` (cf. commentaire 0119, "base de remboursement
-- indicative"), ce n'est pas une nouvelle donnée inventée. `optam_cents` et
-- `panier_sante` restent NULL : leur valeur par code nécessite la
-- classification officielle CNAM (grille conventionnelle 100% Santé), que
-- ccam_act (~31 actes, #4054) ne référence pas encore de façon fiable —
-- deviner ces valeurs risquerait précisément l'erreur que cette colonne
-- doit prévenir (omettre l'alternative RAC 0 obligatoire).

ALTER TABLE ccam_act
    ADD COLUMN IF NOT EXISTS secteur1_cents integer,
    ADD COLUMN IF NOT EXISTS optam_cents integer,
    ADD COLUMN IF NOT EXISTS panier_sante text
        CHECK (panier_sante IN ('rac0', 'modere', 'libre', 'hors_nomenclature'));

COMMENT ON COLUMN ccam_act.secteur1_cents IS
    'Base de remboursement conventionnelle secteur 1, en centimes.';
COMMENT ON COLUMN ccam_act.optam_cents IS
    'Tarif plafond applicable si le praticien a adhéré à l''OPTAM, en '
    'centimes. NULL si non classifié (cf. commentaire de migration).';
COMMENT ON COLUMN ccam_act.panier_sante IS
    'Classification 100% Santé (rac0 = reste à charge nul, modere, libre, '
    'ou hors_nomenclature). NULL si non classifié — un devis ne doit PAS '
    'déduire rac0 par défaut d''une valeur NULL (cf. commentaire de '
    'migration : nécessite la grille officielle CNAM par code).';

UPDATE ccam_act SET secteur1_cents = tarif_cents WHERE secteur1_cents IS NULL;
