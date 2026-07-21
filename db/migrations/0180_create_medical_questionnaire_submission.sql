-- 0180_create_medical_questionnaire_submission.sql
-- Questionnaire médical patient pré-consultation (#4107) : docs/02-decoupe-projet.md
-- classe cette fonctionnalité 🟧 mais aucun écran/route ni table n'existait
-- côté app_patient — la doc était obsolète (constaté par grep, aucun fichier
-- lié dans front/apps/app_patient).
--
-- cabinet_id : le questionnaire est rempli en vue d'une consultation dans un
-- cabinet précis (un patient peut avoir un compte lié à plusieurs cabinets,
-- cf. patient_correspondent/patient_coverage — entités "plateforme" par
-- patient_account_id, mais celle-ci est explicitement par cabinet d'après
-- l'issue).
--
-- Deux policies RLS, même pattern à deux volets que consultation_clinique
-- (migration 0113) :
--   - medical_questionnaire_submission_patient_owner : le patient gère son
--     propre brouillon/soumission (ALL, scoped app.patient_account_id).
--   - medical_questionnaire_submission_cabinet_read : le praticien/secrétariat
--     du cabinet lit UNIQUEMENT après soumission (SELECT, status <> 'draft'),
--     même garde-fou que quote_patient_read pour les brouillons (#4098/#3487) —
--     appliqué ici à l'envers (le cabinet ne doit pas voir un brouillon en
--     cours de saisie côté patient).

CREATE TABLE medical_questionnaire_submission (
    id                 uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    cabinet_id         uuid        NOT NULL REFERENCES cabinet(id),
    patient_account_id uuid        NOT NULL REFERENCES patient_account(id),
    payload            jsonb       NOT NULL DEFAULT '{}'::jsonb,
    status             text        NOT NULL DEFAULT 'draft'
                         CHECK (status IN ('draft', 'submitted', 'reviewed')),
    submitted_at       timestamptz,
    created_at         timestamptz NOT NULL DEFAULT now(),
    updated_at         timestamptz NOT NULL DEFAULT now(),
    -- submitted_at cohérent avec le statut : renseigné à partir de 'submitted', jamais avant.
    CONSTRAINT medical_questionnaire_submission_submitted_at_check CHECK (
        (status = 'draft' AND submitted_at IS NULL) OR
        (status IN ('submitted', 'reviewed') AND submitted_at IS NOT NULL)
    )
);

CREATE INDEX idx_medical_questionnaire_submission_cabinet
    ON medical_questionnaire_submission (cabinet_id);
CREATE INDEX idx_medical_questionnaire_submission_account
    ON medical_questionnaire_submission (patient_account_id);

ALTER TABLE medical_questionnaire_submission ENABLE ROW LEVEL SECURITY;
ALTER TABLE medical_questionnaire_submission FORCE ROW LEVEL SECURITY;

CREATE POLICY medical_questionnaire_submission_patient_owner
    ON medical_questionnaire_submission
    FOR ALL
    TO nubia_app
    USING (
        patient_account_id = nullif(current_setting('app.patient_account_id', true), '')::uuid
    )
    WITH CHECK (
        patient_account_id = nullif(current_setting('app.patient_account_id', true), '')::uuid
    );

CREATE POLICY medical_questionnaire_submission_cabinet_read
    ON medical_questionnaire_submission
    FOR SELECT
    TO nubia_app
    USING (
        cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid
        AND status <> 'draft'
    );

GRANT SELECT, INSERT, UPDATE, DELETE ON medical_questionnaire_submission TO nubia_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON medical_questionnaire_submission TO nubia_seed;

COMMENT ON TABLE medical_questionnaire_submission IS 'Questionnaire médical rempli par le patient avant consultation. Le patient gère son brouillon (RLS ALL par patient_account_id) ; le cabinet ne le voit qu''une fois soumis (RLS SELECT par cabinet_id, status <> draft). Issue #4107.';
