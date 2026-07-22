-- 0186_create_cr_template.sql
-- Modèles de comptes rendus opératoires (#4123) : aucun mécanisme de modèle
-- par type d'acte n'existe alors que la note de séance
-- (consultation_session.note_ciphertext) est toujours saisie de zéro.
--
-- cr_template(cabinet_id, ccam_code nullable, title, body_template) :
-- entité tenant (RLS cabinet_id), contrairement à ccam_act/ccam_act_bundle/
-- ccam_act_incompatibility (catalogue public) — un modèle de CR appartient
-- à UN cabinet (formulation propre à sa pratique), pas un référentiel
-- national partagé.
--
-- ccam_code nullable : un modèle peut être générique (applicable à tout
-- type d'acte, ex. "CR standard") ou spécifique à un acte du catalogue
-- (ex. modèle pré-rempli pour HBLD001 "pose d'implant"). Plusieurs modèles
-- peuvent viser le même ccam_code (pas de contrainte d'unicité — non
-- demandée par l'issue, un cabinet peut vouloir plusieurs variantes de CR
-- pour un même acte).

CREATE TABLE cr_template (
    id            uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    cabinet_id    uuid        NOT NULL REFERENCES cabinet(id),
    ccam_code     text        REFERENCES ccam_act(code),
    title         text        NOT NULL,
    body_template text        NOT NULL,
    created_at    timestamptz NOT NULL DEFAULT now(),
    updated_at    timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_cr_template_cabinet
    ON cr_template (cabinet_id);
CREATE INDEX idx_cr_template_ccam_code
    ON cr_template (ccam_code) WHERE ccam_code IS NOT NULL;

ALTER TABLE cr_template ENABLE ROW LEVEL SECURITY;
ALTER TABLE cr_template FORCE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON cr_template
    FOR ALL
    TO nubia_app
    USING      (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid)
    WITH CHECK (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid);

GRANT SELECT, INSERT, UPDATE, DELETE ON cr_template TO nubia_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON cr_template TO nubia_seed;

COMMENT ON TABLE cr_template IS
    'Modèles de comptes rendus opératoires par cabinet, optionnellement rattachés à un acte CCAM. #4123.';
