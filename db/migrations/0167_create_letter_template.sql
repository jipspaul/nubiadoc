-- 0167_create_letter_template.sql
-- Modèles de courriers types / publipostage (#4166) : aucune trace de
-- courriers types (convocations, relances, courriers confrères) alors que
-- c'est un standard marché. Table tenant simple (cabinet_id NOT NULL),
-- même pattern RLS que patient_tag (migration 0158) — pas de variante
-- globale/seedée demandée par l'issue, contrairement à prescription_template
-- (migration 0166) qui a un catalogue standard partagé.
--
-- body_template : texte libre avec placeholders `{{patient.prenom}}` etc.
-- (le moteur de substitution n'est pas dans le scope de cette migration —
-- schéma seul, cf. issue).
-- kind : catégorie du courrier, restreinte aux valeurs citées par l'issue
-- + une valeur générique ("autre") pour ne pas bloquer un usage non prévu.

CREATE TABLE letter_template (
    id             UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    cabinet_id     UUID        NOT NULL REFERENCES cabinet(id),
    name           TEXT        NOT NULL,
    kind           TEXT        NOT NULL
                     CHECK (kind IN ('convocation', 'relance', 'courrier_confrere', 'autre')),
    body_template  TEXT        NOT NULL,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT letter_template_name_not_blank CHECK (btrim(name) <> ''),
    CONSTRAINT letter_template_body_not_blank CHECK (btrim(body_template) <> '')
);

CREATE INDEX idx_letter_template_cabinet
    ON letter_template (cabinet_id);

GRANT SELECT, INSERT, UPDATE, DELETE ON letter_template TO nubia_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON letter_template TO nubia_seed;

ALTER TABLE letter_template ENABLE ROW LEVEL SECURITY;
ALTER TABLE letter_template FORCE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON letter_template
    USING      (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid)
    WITH CHECK (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid);

COMMENT ON TABLE letter_template IS 'Modèles de courriers types (publipostage) — convocations, relances, courriers confrères. Table tenant (cabinet_id). RLS fail-closed. Issue #4166.';
COMMENT ON COLUMN letter_template.body_template IS 'Corps du courrier avec placeholders libres (ex. {{patient.prenom}}) — moteur de substitution hors scope de cette migration.';
