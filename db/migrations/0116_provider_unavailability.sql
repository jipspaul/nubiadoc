-- 0116_provider_unavailability.sql
-- Table provider_unavailability : bloque des créneaux génériques (vacances, formation, congés).
-- RLS cabinet_isolation transitive via provider.cabinet_id (pas de colonne cabinet_id directe).
-- Issue : #2543

CREATE TABLE provider_unavailability (
  id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  provider_id uuid        NOT NULL REFERENCES provider(id) ON DELETE CASCADE,
  starts_at   timestamptz NOT NULL,
  ends_at     timestamptz NOT NULL,
  reason      text,
  CONSTRAINT provider_unavailability_check_range CHECK (starts_at < ends_at)
);

CREATE INDEX idx_provider_unavailability_provider_time
  ON provider_unavailability (provider_id, starts_at);

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
