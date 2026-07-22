-- 0189_create_orthodontic_treatment.sql
-- Traitement orthodontique (#4134) : aucune table ne le modélise
-- aujourd'hui, ni dans db/migrations ni dans docs/05-modele-de-donnees.md.
--
-- orthodontic_treatment / orthodontic_step, sur le modèle du couple
-- treatment_plan / treatment_phase (migration 0010) : treatment_plan_id
-- nullable — un traitement ortho peut exister sans plan de traitement
-- global rattaché (contrairement à treatment_phase.plan_id, NOT NULL, un
-- traitement ortho est souvent prescrit seul).
--
-- RLS posée ICI (pas dans le loop générique de la migration 0011, qui ne
-- couvre que les tables existant à l'époque de cette migration) — même
-- pattern que toutes les tables tenant ajoutées depuis (cr_template,
-- dental_chart_history...).

CREATE TABLE orthodontic_treatment (
    id                uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    cabinet_id        uuid        NOT NULL REFERENCES cabinet(id),
    patient_id        uuid        NOT NULL REFERENCES patient(id),
    treatment_plan_id uuid        REFERENCES treatment_plan(id),
    type              text        NOT NULL,
    semester_count    integer     NOT NULL CHECK (semester_count > 0),
    started_at        date,
    status            text        NOT NULL DEFAULT 'planned'
                        CHECK (status IN ('planned', 'in_progress', 'completed', 'discontinued')),
    created_at        timestamptz NOT NULL DEFAULT now(),
    updated_at        timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_orthodontic_treatment_patient
    ON orthodontic_treatment (patient_id);
CREATE INDEX idx_orthodontic_treatment_plan
    ON orthodontic_treatment (treatment_plan_id)
    WHERE treatment_plan_id IS NOT NULL;

CREATE TABLE orthodontic_step (
    id               uuid    PRIMARY KEY DEFAULT gen_random_uuid(),
    cabinet_id       uuid    NOT NULL REFERENCES cabinet(id),
    treatment_id     uuid    NOT NULL REFERENCES orthodontic_treatment(id),
    step_number      integer NOT NULL CHECK (step_number > 0),
    kind             text    NOT NULL CHECK (kind IN ('bague', 'contention', 'gouttiere')),
    delivered_at     date,
    conformity_notes text,
    UNIQUE (treatment_id, step_number)
);

CREATE INDEX idx_orthodontic_step_treatment
    ON orthodontic_step (treatment_id);

-- RLS tenant (fail-closed : GUC absent → 0 ligne) sur les deux tables.
ALTER TABLE orthodontic_treatment ENABLE ROW LEVEL SECURITY;
ALTER TABLE orthodontic_treatment FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON orthodontic_treatment
    FOR ALL
    TO nubia_app
    USING      (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid)
    WITH CHECK (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid);

ALTER TABLE orthodontic_step ENABLE ROW LEVEL SECURITY;
ALTER TABLE orthodontic_step FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON orthodontic_step
    FOR ALL
    TO nubia_app
    USING      (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid)
    WITH CHECK (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid);

GRANT SELECT, INSERT, UPDATE, DELETE ON orthodontic_treatment TO nubia_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON orthodontic_step TO nubia_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON orthodontic_treatment TO nubia_seed;
GRANT SELECT, INSERT, UPDATE, DELETE ON orthodontic_step TO nubia_seed;

COMMENT ON TABLE orthodontic_treatment IS
    'Traitement orthodontique d''un patient, optionnellement rattaché à un treatment_plan. #4134.';
COMMENT ON TABLE orthodontic_step IS
    'Étape d''un traitement orthodontique (pose bague/contention/gouttière). #4134.';
