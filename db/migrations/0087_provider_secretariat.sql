-- 0087_provider_secretariat.sql
-- Table de jonction provider ↔ secretariat : pivot du cloisonnement intra-établissement.
-- Un docteur peut être assigné à un ou plusieurs secrétariat(s) ; le flag `active`
-- permet la désassignation sans DELETE (audit trail, PLAN-ATOMIC §H.1 P12).
-- RLS cabinet-scoped via secretariat.cabinet_id (EXISTS subquery).
-- Issue : #1195

CREATE TABLE provider_secretariat (
    id             UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    provider_id    UUID        NOT NULL REFERENCES provider(id),
    secretariat_id UUID        NOT NULL REFERENCES secretariat(id),
    active         BOOLEAN     NOT NULL DEFAULT true,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Un seul lien actif par couple (provider, secretariat).
-- Les entrées inactives (désassignations) ne sont pas contraintes → audit trail.
CREATE UNIQUE INDEX idx_provider_secretariat_unique_active
    ON provider_secretariat (provider_id, secretariat_id)
    WHERE active;

GRANT SELECT, INSERT, UPDATE ON provider_secretariat TO nubia_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON provider_secretariat TO nubia_seed;

-- RLS : isolation cabinet via secretariat.cabinet_id.
-- La RLS sur secretariat s'applique au subquery → cohérence garantie sans cabinet_id direct.
ALTER TABLE provider_secretariat ENABLE ROW LEVEL SECURITY;
ALTER TABLE provider_secretariat FORCE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON provider_secretariat
    USING (
        EXISTS (
            SELECT 1 FROM secretariat s
            WHERE s.id = provider_secretariat.secretariat_id
              AND s.cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM secretariat s
            WHERE s.id = provider_secretariat.secretariat_id
              AND s.cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid
        )
    );

COMMENT ON TABLE provider_secretariat IS 'Assignation docteur ↔ secrétariat (multi-établissement §H). RLS cabinet-scoped via secretariat.cabinet_id. active=false = désassignation sans DELETE. Réf. P12 PLAN-ATOMIC.';
