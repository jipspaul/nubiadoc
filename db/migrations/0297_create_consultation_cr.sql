-- 0297_create_consultation_cr.sql
-- Table consultation_cr (CR structuré, DP-F23.b #7154) : sections rédigées
-- pour une séance (`consultation_session`), à partir d'un modèle optionnel
-- (`cr_template`, migration 0186, #4123). Sauvegardée en brouillon à chaque
-- frappe (`status = 'draft'`), puis finalisée (rendu texte/PDF côté API,
-- alimentation du passeport implantaire si une section implant est
-- renseignée — `implant_passport_id`, upsert idempotent au fil des
-- autosaves plutôt qu'une création d'implant par frappe).
-- Contenu chiffré (colonne PII, même stub que consultation_session
-- .note_ciphertext) : sections_ciphertext/sections_key_ref.
-- Issue : #7154 (DP-F23.b)

CREATE TABLE consultation_cr (
    id                   uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    cabinet_id           uuid        NOT NULL REFERENCES cabinet(id),
    appointment_id       uuid        NOT NULL UNIQUE REFERENCES appointment(id),
    practitioner_id      uuid        NOT NULL REFERENCES practitioner(id),
    template_id          uuid        REFERENCES cr_template(id),
    sections_ciphertext  bytea,
    sections_key_ref     text,
    implant_passport_id  uuid        REFERENCES implant_passport(id),
    status               text        NOT NULL DEFAULT 'draft'
                                     CHECK (status IN ('draft', 'finalized')),
    created_at           timestamptz NOT NULL DEFAULT now(),
    updated_at           timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_consultation_cr_cabinet_appointment
    ON consultation_cr (cabinet_id, appointment_id);

ALTER TABLE consultation_cr ENABLE ROW LEVEL SECURITY;
ALTER TABLE consultation_cr FORCE ROW LEVEL SECURITY;

-- Policy cabinet (pro) : isolation tenant standard, même pattern que
-- consultation_clinique_cabinet_isolation (migration 0113).
CREATE POLICY consultation_cr_cabinet_isolation ON consultation_cr
    FOR ALL
    TO nubia_app
    USING  (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid)
    WITH CHECK (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid);

GRANT SELECT, INSERT, UPDATE, DELETE ON consultation_cr TO nubia_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON consultation_cr TO nubia_seed;
