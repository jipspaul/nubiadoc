-- 0158_create_patient_tag.sql
-- Étiquettes administratives sur la fiche patient (#4039).
-- Distinct du journal clinique praticien-only (clinical_note) : ZÉRO donnée
-- de santé ici, uniquement des repères administratifs libres pour le
-- secrétariat/accueil (ex. "paie en retard", "préfère le matin", "allergique
-- au parfum d'ambiance") — le référentiel cite ce type de fonctionnalité
-- comme un tueur de démo silencieux face à une assistante expérimentée.
-- Table tenant (cabinet_id), même pattern RLS que `reminder` (migration 0085).

CREATE TABLE patient_tag (
    id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    cabinet_id UUID        NOT NULL REFERENCES cabinet(id),
    patient_id UUID        NOT NULL REFERENCES patient(id),
    label      TEXT        NOT NULL,
    color      TEXT        NOT NULL DEFAULT '#94A3B8',
    created_by UUID        NOT NULL REFERENCES app_user(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT patient_tag_label_not_blank CHECK (btrim(label) <> '')
);

-- Index tenant-first : liste des étiquettes d'un patient (fiche admin).
CREATE INDEX idx_patient_tag_cabinet_patient
    ON patient_tag (cabinet_id, patient_id);

GRANT SELECT, INSERT, UPDATE, DELETE ON patient_tag TO nubia_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON patient_tag TO nubia_seed;

-- RLS : isolation par cabinet (même pattern que reminder, migration 0085).
ALTER TABLE patient_tag ENABLE ROW LEVEL SECURITY;
ALTER TABLE patient_tag FORCE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON patient_tag
    USING      (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid)
    WITH CHECK (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid);

COMMENT ON TABLE patient_tag IS 'Étiquettes administratives libres sur la fiche patient (zéro donnée clinique). Table tenant (cabinet_id). RLS fail-closed. Issue #4039.';
