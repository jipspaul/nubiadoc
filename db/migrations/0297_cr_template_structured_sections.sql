-- 0297_cr_template_structured_sections.sql
-- #7155 (DP-F23.a) : schéma de sections structurées (jsonb) pour les modèles
-- de CR (cr_template, 0186) — chirurgie implantaire, endo, paro. Chaque
-- section est un objet {key, label, fields[]} et l'ordre du tableau jsonb
-- fixe l'ordre d'affichage du CR. Sections couvertes par l'issue : patient
-- & intervention, anesthésie, guide chirurgical, lambeau, implants
-- (référence, lot), greffes, matériaux, post-opératoire, documents — un
-- modèle donné n'active que le sous-ensemble pertinent à son acte (ex. un
-- CR d'endodontie n'a ni section implants ni lambeau).
--
-- Ce schéma ne remplace pas body_template (texte libre) : un modèle peut
-- rester purement texte (sections = '[]', comportement inchangé) ou
-- combiner les deux.
--
-- Pas de table `consultation_report` dans ce schéma : son équivalent est
-- `consultation_clinique` (0113, compte rendu patient post-RDV), qui gagne
-- la colonne `structured jsonb` portant les valeurs saisies par section,
-- keyées par `cr_template.sections[].key`.

ALTER TABLE cr_template
    ADD COLUMN sections jsonb NOT NULL DEFAULT '[]'::jsonb
        CHECK (jsonb_typeof(sections) = 'array');

COMMENT ON COLUMN cr_template.sections IS
    'Schéma de sections structurées, ordonné : [{key,label,fields[]}, ...]. Vide = modèle en texte libre uniquement (body_template). #7155.';

ALTER TABLE consultation_clinique
    ADD COLUMN structured jsonb NOT NULL DEFAULT '{}'::jsonb
        CHECK (jsonb_typeof(structured) = 'object');

COMMENT ON COLUMN consultation_clinique.structured IS
    'Valeurs saisies par section structurée (clé = cr_template.sections[].key). Vide pour un CR en texte libre. #7155.';
