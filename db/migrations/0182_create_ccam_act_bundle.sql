-- 0182_create_ccam_act_bundle.sql
-- Groupes d'actes CCAM composés (#4114) : aucun mécanisme de groupe
-- n'existe — un acte composé (ex. "couronne céramique" = plusieurs codes
-- CCAM) doit être ajouté code par code à chaque consultation.
--
-- Référentiel catalogue (comme ccam_act, migration 0119) : public en
-- lecture, non tenant, aucune donnée patient — même choix RLS (aucune).
--
-- Pas de données de seed dans cette migration : la composition réelle d'un
-- acte composé (quels codes CCAM, en quelle quantité, pour "couronne
-- céramique" ou tout autre groupe) est une donnée métier/clinique précise
-- qui n'est pas fournie par l'issue — l'inventer serait fabriquer une
-- information facturable. Cette migration pose uniquement la structure ;
-- le remplissage du catalogue est laissé à une décision humaine (praticien/
-- expert métier), dans une issue ou un script de seed dédié.

CREATE TABLE ccam_act_bundle (
    code  text PRIMARY KEY,
    label text NOT NULL
);

CREATE TABLE ccam_act_bundle_item (
    id          uuid    PRIMARY KEY DEFAULT gen_random_uuid(),
    bundle_code text    NOT NULL REFERENCES ccam_act_bundle(code),
    ccam_code   text    NOT NULL REFERENCES ccam_act(code),
    qty         integer NOT NULL DEFAULT 1 CHECK (qty > 0),
    UNIQUE (bundle_code, ccam_code)
);

CREATE INDEX idx_ccam_act_bundle_item_bundle
    ON ccam_act_bundle_item (bundle_code);

GRANT SELECT ON ccam_act_bundle TO nubia_app;
GRANT SELECT ON ccam_act_bundle_item TO nubia_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON ccam_act_bundle TO nubia_seed;
GRANT SELECT, INSERT, UPDATE, DELETE ON ccam_act_bundle_item TO nubia_seed;

COMMENT ON TABLE ccam_act_bundle IS
    'Groupes d''actes CCAM composés (ex. "couronne céramique" = plusieurs codes). Référentiel public en lecture, non tenant. #4114.';
COMMENT ON TABLE ccam_act_bundle_item IS
    'Composition d''un groupe d''actes : code CCAM + quantité. #4114.';
