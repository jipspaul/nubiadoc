-- 0086_add_secretariat.sql
-- Table secretariat : sous-unité d'un cabinet (feature multi-établissement §H).
-- Socle de P11 (membres), P12 (assignation docteurs), P13 (RLS contexte).
-- RLS cabinet-scoped, fail-closed (pattern standard tenant_isolation).
-- Issue : #1187

CREATE TABLE secretariat (
    id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    cabinet_id UUID        NOT NULL REFERENCES cabinet(id) ON DELETE CASCADE,
    name       TEXT        NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Index tenant-first (liste des secrétariats par cabinet).
CREATE INDEX idx_secretariat_cabinet
    ON secretariat (cabinet_id);

GRANT SELECT, INSERT, UPDATE ON secretariat TO nubia_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON secretariat TO nubia_seed;

-- RLS : isolation par cabinet (même pattern que les tables tenant standard).
ALTER TABLE secretariat ENABLE ROW LEVEL SECURITY;
ALTER TABLE secretariat FORCE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON secretariat
    USING      (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid)
    WITH CHECK (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid);

-- Backfill : tout cabinet existant reçoit un secrétariat 'Principal' s'il n'en a pas encore.
-- Idempotent (WHERE NOT EXISTS) : safe à rejouer.
INSERT INTO secretariat (cabinet_id, name)
SELECT id, 'Principal'
FROM cabinet
WHERE NOT EXISTS (
    SELECT 1 FROM secretariat WHERE secretariat.cabinet_id = cabinet.id
);

COMMENT ON TABLE secretariat IS 'Secrétariat : sous-unité d''un cabinet (multi-établissement §H). Table tenant (cabinet_id). RLS fail-closed. Réf. P10 PLAN-ATOMIC.';
