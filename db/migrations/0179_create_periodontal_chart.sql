-- 0179_create_periodontal_chart.sql
-- Sondage/bilan parodontal (#4104) : aucune table ne stockait de sondage
-- parodontal ni d'indices (bilan remboursé ALD/diabétiques). Table
-- distincte de dental_chart : un schéma dentaire est un état courant unique
-- par patient (UNIQUE patient_id+cabinet_id, migration 0081), un bilan
-- parodontal est une série de mesures ponctuelles dans le temps
-- (measured_at) — plusieurs bilans par patient, aucune contrainte
-- d'unicité, pas de updated_at (chaque bilan est une capture immuable).
--
-- sites jsonb : profondeurs de poche par site/dent (schéma libre, comme
-- dental_chart.teeth_status).
-- indices jsonb : indices calculés (indice de plaque, indice de saignement,
-- etc. — schéma libre, aucun référentiel unique ne s'impose ici).

CREATE TABLE periodontal_chart (
    id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    cabinet_id  uuid        NOT NULL REFERENCES cabinet(id),
    patient_id  uuid        NOT NULL REFERENCES patient(id),
    measured_at timestamptz NOT NULL DEFAULT now(),
    sites       jsonb       NOT NULL DEFAULT '{}',
    indices     jsonb       NOT NULL DEFAULT '{}',
    created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_periodontal_chart_patient
    ON periodontal_chart (patient_id, measured_at DESC);

-- RLS tenant_isolation identique à dental_chart (fail-closed).
ALTER TABLE periodontal_chart ENABLE ROW LEVEL SECURITY;
ALTER TABLE periodontal_chart FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON periodontal_chart
    FOR ALL
    USING      (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid)
    WITH CHECK (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid);

GRANT SELECT, INSERT, UPDATE, DELETE ON periodontal_chart TO nubia_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON periodontal_chart TO nubia_seed;

COMMENT ON TABLE periodontal_chart IS 'Bilans parodontaux (sondage, indices) — série de mesures ponctuelles par patient, contrairement à dental_chart (état courant unique). RLS tenant_isolation fail-closed. Issue #4104.';
COMMENT ON COLUMN periodontal_chart.sites IS 'Profondeurs de poche par site/dent — schéma libre, comme dental_chart.teeth_status.';
COMMENT ON COLUMN periodontal_chart.indices IS 'Indices calculés (plaque, saignement, etc.) — schéma libre.';
