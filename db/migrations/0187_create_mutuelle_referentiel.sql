-- 0187_create_mutuelle_referentiel.sql
-- Référentiel de mutuelles/organismes complémentaires (#4127) : aujourd'hui
-- patient_coverage.amc (migration 0023) est un simple champ texte libre,
-- resaisi manuellement par chaque cabinet.
--
-- Référentiel catalogue (comme ccam_act, migration 0119 / ccam_act_bundle,
-- migration 0182) : public en lecture, non tenant, aucune donnée patient —
-- même choix RLS (aucune).
--
-- Pas de données de seed dans cette migration : contrairement à CCAM/NGAP
-- (nomenclature nationale unique, officielle, vérifiable), la liste réelle
-- des organismes complémentaires + leurs coordonnées/conditions de tiers
-- payant n'est pas fournie par l'issue — l'inventer serait fabriquer une
-- information affichée comme un fait fiable au cabinet/patient (même
-- réserve déjà posée sur #4097 pour amc_convention). Cette migration pose
-- uniquement la structure ; le remplissage est laissé à une décision
-- humaine (script de seed dédié, à partir d'une source réelle).

CREATE TABLE mutuelle_referentiel (
    id                      uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    nom                     text        NOT NULL,
    contact                 text,
    conditions_tiers_payant text,
    created_at              timestamptz NOT NULL DEFAULT now(),
    updated_at              timestamptz NOT NULL DEFAULT now()
);

-- Recherche par nom (test d'intégration attendu par l'issue) + évite les
-- doublons d'un même organisme saisi deux fois lors du seed.
CREATE UNIQUE INDEX idx_mutuelle_referentiel_nom
    ON mutuelle_referentiel (lower(nom));

-- REVOKE ALL d'abord : migration 0001 pose un GRANT SELECT/INSERT/UPDATE/
-- DELETE par défaut sur TOUTE nouvelle table pour nubia_app (ALTER DEFAULT
-- PRIVILEGES) — un simple GRANT SELECT ne restreint donc rien tout seul,
-- il faut explicitement retirer les privilèges d'écriture par défaut
-- (même pattern que audit_log, migrations 0008/0011 ; bug identique déjà
-- corrigé sur dental_chart_history, #4121, où la suite pgTAP complète
-- avait détecté le même gap).
REVOKE ALL ON mutuelle_referentiel FROM nubia_app;
GRANT SELECT ON mutuelle_referentiel TO nubia_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON mutuelle_referentiel TO nubia_seed;

COMMENT ON TABLE mutuelle_referentiel IS
    'Référentiel plateforme des mutuelles/organismes complémentaires (nom, contact, conditions de tiers payant). Lecture publique, écriture réservée au seed. Pas de données préchargées (#4127). #4127.';
