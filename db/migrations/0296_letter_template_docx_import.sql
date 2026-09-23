-- 0296_letter_template_docx_import.sql
-- Import de modèles .docx pour le moteur de courriers (#7157, suite de
-- #7197) : jusqu'ici un courrier type n'était qu'un texte libre avec
-- placeholders (`body_template`, migration 0167). Le cabinet doit pouvoir
-- importer son propre modèle Word (mise en forme, logo...) —
-- `POST /v1/letter-templates/import` (api/src/letter_docx.rs) stocke le
-- fichier `.docx` original tel quel ; la substitution se fait dans
-- `word/document.xml` à la demande (`letters::generate_patient_letter`),
-- jamais à l'import.
--
-- source_format distingue les deux origines d'un courrier type :
--   'text' (défaut, comportement existant) : `body_template` porte le
--     texte avec placeholders, `docx_bytes`/`docx_placeholders` inutilisés.
--   'docx' : `body_template` vide (contrainte relâchée ci-dessous),
--     `docx_bytes` porte le fichier original, `docx_placeholders` la liste
--     extraite à l'import (mise en cache : évite de dézipper/scanner le
--     fichier à chaque `GET /v1/letter-templates`).

ALTER TABLE letter_template
    ADD COLUMN source_format TEXT NOT NULL DEFAULT 'text'
        CHECK (source_format IN ('text', 'docx')),
    ADD COLUMN docx_bytes BYTEA,
    ADD COLUMN docx_placeholders TEXT[] NOT NULL DEFAULT '{}';

ALTER TABLE letter_template DROP CONSTRAINT letter_template_body_not_blank;
ALTER TABLE letter_template ADD CONSTRAINT letter_template_body_not_blank
    CHECK (source_format = 'docx' OR btrim(body_template) <> '');

ALTER TABLE letter_template ADD CONSTRAINT letter_template_docx_bytes_present
    CHECK (source_format = 'text' OR docx_bytes IS NOT NULL);

COMMENT ON COLUMN letter_template.source_format IS 'Origine du courrier type : "text" (body_template, défaut) ou "docx" (fichier importé, docx_bytes). Issue #7157.';
COMMENT ON COLUMN letter_template.docx_bytes IS 'Fichier .docx original tel quel (source_format = ''docx''). Substitué à la demande dans word/document.xml (api/src/letter_docx.rs), jamais réécrit à l''import. Issue #7157.';
COMMENT ON COLUMN letter_template.docx_placeholders IS 'Placeholders extraits de docx_bytes à l''import (source_format = ''docx'') — mise en cache, évite de rescanner le fichier à chaque listing. Issue #7157.';
