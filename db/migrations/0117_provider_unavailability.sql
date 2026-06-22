-- 0117_provider_unavailability.sql
-- Table provider_unavailability : blocage générique de créneaux praticien
-- (vacances, congés, formation). FK ON DELETE CASCADE : la suppression du
-- provider supprime ses indisponibilités. RLS cabinet-scoped via
-- provider.cabinet_id (transitif — la table n'a pas de cabinet_id direct).
-- GUC absent → nullif(...)::uuid = NULL → EXISTS = false → fail-closed.
-- Issue : #2514

CREATE TABLE provider_unavailability (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    provider_id UUID        NOT NULL REFERENCES provider(id) ON DELETE CASCADE,
    starts_at   TIMESTAMPTZ NOT NULL,
    ends_at     TIMESTAMPTZ NOT NULL,
    reason      TEXT,
    CONSTRAINT provider_unavailability_dates_check CHECK (starts_at < ends_at)
);

GRANT SELECT, INSERT, UPDATE, DELETE ON provider_unavailability TO nubia_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON provider_unavailability TO nubia_seed;

ALTER TABLE provider_unavailability ENABLE ROW LEVEL SECURITY;
ALTER TABLE provider_unavailability FORCE ROW LEVEL SECURITY;

CREATE POLICY provider_unavailability_cabinet_isolation ON provider_unavailability
    FOR ALL TO nubia_app
    USING (
        EXISTS (
            SELECT 1 FROM provider p
            WHERE p.id         = provider_unavailability.provider_id
              AND p.cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM provider p
            WHERE p.id         = provider_unavailability.provider_id
              AND p.cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid
        )
    );

CREATE POLICY provider_unavailability_seed ON provider_unavailability
    FOR ALL TO nubia_seed
    USING (true)
    WITH CHECK (true);

COMMENT ON TABLE provider_unavailability IS 'Blocage générique de créneaux praticien (vacances, congés, formation). RLS cabinet-scoped via provider.cabinet_id (transitif). Réf. DB-T032 #2514.';
