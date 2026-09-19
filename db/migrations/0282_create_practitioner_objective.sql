-- 0282_create_practitioner_objective.sql
-- Objectif de chiffre d'affaires mensuel par praticien et par cabinet (#7190).
-- Un objectif par (cabinet, praticien, mois) — UNIQUE(cabinet_id, provider_id, month).
-- Table tenant (cabinet_id), même pattern RLS que `patient_tag` (migration 0158).

CREATE TABLE practitioner_objective (
    id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    cabinet_id    UUID        NOT NULL REFERENCES cabinet(id),
    provider_id   UUID        NOT NULL REFERENCES provider(id),
    month         DATE        NOT NULL,
    target_cents  BIGINT      NOT NULL CHECK (target_cents >= 0),
    created_by    UUID        NOT NULL REFERENCES app_user(id),
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT practitioner_objective_month_is_first_day CHECK (date_trunc('month', month)::date = month),
    CONSTRAINT practitioner_objective_unique_cabinet_provider_month UNIQUE (cabinet_id, provider_id, month)
);

-- Index tenant-first : liste des objectifs d'un cabinet (tableau de pilotage).
CREATE INDEX idx_practitioner_objective_cabinet_month
    ON practitioner_objective (cabinet_id, month);

GRANT SELECT, INSERT, UPDATE, DELETE ON practitioner_objective TO nubia_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON practitioner_objective TO nubia_seed;

-- RLS : isolation par cabinet (même pattern que patient_tag, migration 0158).
ALTER TABLE practitioner_objective ENABLE ROW LEVEL SECURITY;
ALTER TABLE practitioner_objective FORCE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON practitioner_objective
    USING      (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid)
    WITH CHECK (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid);

COMMENT ON TABLE practitioner_objective IS 'Objectif de CA mensuel par praticien et par cabinet. Table tenant (cabinet_id). RLS fail-closed. Issue #7190.';
