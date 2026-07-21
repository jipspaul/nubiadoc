-- 0168_create_data_import_job.sql
-- Suivi des imports de reprise de données (#4167, "Migration White-Glove"
-- §4.2) : aucun outillage de reprise depuis un ancien logiciel n'existe.
-- Cette migration pose UNIQUEMENT la table de suivi (statut/comptage d'un
-- import) — le connecteur/parser par éditeur source (Logos, etc.) viendra
-- dans des issues ultérieures, hors scope ici.
--
-- Table tenant simple, même pattern RLS que patient_tag (migration 0158) /
-- letter_template (migration 0167).

CREATE TABLE data_import_job (
    id             UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    cabinet_id     UUID        NOT NULL REFERENCES cabinet(id),
    source_system  TEXT        NOT NULL,
    status         TEXT        NOT NULL DEFAULT 'pending'
                     CHECK (status IN ('pending', 'running', 'completed', 'failed')),
    imported_count INTEGER     NOT NULL DEFAULT 0 CHECK (imported_count >= 0),
    error_count    INTEGER     NOT NULL DEFAULT 0 CHECK (error_count >= 0),
    started_at     TIMESTAMPTZ,
    finished_at    TIMESTAMPTZ,
    CONSTRAINT data_import_job_source_system_not_blank CHECK (btrim(source_system) <> ''),
    CONSTRAINT data_import_job_finished_after_started
        CHECK (finished_at IS NULL OR started_at IS NULL OR finished_at >= started_at)
);

CREATE INDEX idx_data_import_job_cabinet
    ON data_import_job (cabinet_id);

GRANT SELECT, INSERT, UPDATE, DELETE ON data_import_job TO nubia_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON data_import_job TO nubia_seed;

ALTER TABLE data_import_job ENABLE ROW LEVEL SECURITY;
ALTER TABLE data_import_job FORCE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON data_import_job
    USING      (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid)
    WITH CHECK (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid);

COMMENT ON TABLE data_import_job IS 'Suivi d''un import de reprise de données depuis un ancien logiciel (Migration White-Glove). Table tenant (cabinet_id). RLS fail-closed. Connecteur/parser hors scope — issues ultérieures. Issue #4167.';
COMMENT ON COLUMN data_import_job.source_system IS 'Nom libre de l''éditeur/logiciel source (ex. Logos) — pas d''énum, catalogue de connecteurs à définir séparément.';
