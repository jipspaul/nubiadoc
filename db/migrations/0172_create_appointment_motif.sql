-- 0172_create_appointment_motif.sql
-- Catalogue de motifs de RDV paramétrable par cabinet (#4084) :
-- `appointment.motif` (migration 0005) est du texte libre, et
-- `medical_act.motifs` (0009) est une taxonomie plateforme pour le
-- marketplace — ni l'un ni l'autre ne permet à un cabinet de définir ses
-- propres motifs récurrents (ex. "Détartrage", "Urgence douleur") avec une
-- durée par défaut pour préremplir l'agenda. Table tenant simple
-- (cabinet_id NOT NULL), même pattern RLS que letter_template
-- (migration 0167) / patient_tag (migration 0158).
--
-- default_duration_minutes : optionnel, préremplissage agenda uniquement —
-- ne contraint pas la durée réelle du RDV (appointment n'a pas de colonne
-- duration, cf. 0005).

CREATE TABLE appointment_motif (
    id                       UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    cabinet_id               UUID        NOT NULL REFERENCES cabinet(id),
    label                    TEXT        NOT NULL,
    default_duration_minutes INTEGER,
    created_at               TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT appointment_motif_label_not_blank CHECK (btrim(label) <> ''),
    CONSTRAINT appointment_motif_duration_positive
        CHECK (default_duration_minutes IS NULL OR default_duration_minutes > 0)
);

CREATE INDEX idx_appointment_motif_cabinet
    ON appointment_motif (cabinet_id);

GRANT SELECT, INSERT, UPDATE, DELETE ON appointment_motif TO nubia_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON appointment_motif TO nubia_seed;

ALTER TABLE appointment_motif ENABLE ROW LEVEL SECURITY;
ALTER TABLE appointment_motif FORCE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON appointment_motif
    USING      (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid)
    WITH CHECK (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid);

COMMENT ON TABLE appointment_motif IS 'Catalogue de motifs de RDV paramétrable par cabinet (préremplissage agenda). Table tenant (cabinet_id). RLS fail-closed. Issue #4084.';
COMMENT ON COLUMN appointment_motif.default_duration_minutes IS 'Durée par défaut suggérée pour préremplir l''agenda — n''oblige à rien, appointment n''a pas de colonne duration (cf. migration 0005).';
