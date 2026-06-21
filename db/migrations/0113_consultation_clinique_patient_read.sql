-- 0113_consultation_clinique_patient_read.sql
-- Table consultation_clinique (compte rendu patient post-RDV) + RLS :
--   - cabinet_isolation : praticien/secrétariat du cabinet (ALL).
--   - consultation_clinique_patient_read : patient titulaire du RDV (SELECT).
-- Le patient est identifié via appointment → patient → patient_account_id ;
-- appointment n'a pas de colonne patient_account_id directe.
-- Issue : #2472 (DB-T028)

CREATE TABLE consultation_clinique (
    id                 uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    cabinet_id         uuid        NOT NULL REFERENCES cabinet(id),
    appointment_id     uuid        NOT NULL UNIQUE REFERENCES appointment(id),
    practitioner_id    uuid        NOT NULL REFERENCES practitioner(id),
    content_ciphertext bytea,
    content_key_ref    text,
    status             text        NOT NULL DEFAULT 'draft'
                                   CHECK (status IN ('draft', 'finalized')),
    created_at         timestamptz NOT NULL DEFAULT now(),
    updated_at         timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_consultation_clinique_cabinet_appointment
    ON consultation_clinique (cabinet_id, appointment_id);

ALTER TABLE consultation_clinique ENABLE ROW LEVEL SECURITY;
ALTER TABLE consultation_clinique FORCE ROW LEVEL SECURITY;

-- Policy cabinet (pro) : isolation tenant standard.
CREATE POLICY consultation_clinique_cabinet_isolation ON consultation_clinique
    FOR ALL
    TO nubia_app
    USING  (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid)
    WITH CHECK (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid);

-- Policy patient-read : patient titulaire du RDV (via appointment → patient).
CREATE POLICY consultation_clinique_patient_read ON consultation_clinique
    FOR SELECT
    TO nubia_app
    USING (
        EXISTS (
            SELECT 1 FROM appointment a
            JOIN patient p ON p.id = a.patient_id
            WHERE a.id = consultation_clinique.appointment_id
              AND p.patient_account_id = nullif(current_setting('app.patient_account_id', true), '')::uuid
        )
    );

GRANT SELECT, INSERT, UPDATE, DELETE ON consultation_clinique TO nubia_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON consultation_clinique TO nubia_seed;
