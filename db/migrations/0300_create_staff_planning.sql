-- 0300_create_staff_planning.sql
-- Planning d'équipe, demandes de congés, pointage (périmètre RH, priorité basse).
-- `provider_unavailability` (0116) couvre déjà les absences praticien ; ces trois
-- tables couvrent le reste de l'équipe (secrétariat, assistantes, etc.) :
--   - staff_shift       : créneaux planifiés d'un membre de l'équipe.
--   - leave_request     : demandes de congés/absences, avec cycle de décision.
--   - time_clock_entry  : pointage (entrée/sortie), source de la saisie.
-- Toutes tenant (cabinet_id direct), même pattern RLS que `patient_tag` (0158).
-- Issue : #7145

CREATE TABLE staff_shift (
    id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    cabinet_id UUID        NOT NULL REFERENCES cabinet(id),
    user_id    UUID        NOT NULL REFERENCES app_user(id),
    starts_at  TIMESTAMPTZ NOT NULL,
    ends_at    TIMESTAMPTZ NOT NULL,
    room       TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT staff_shift_check_range CHECK (starts_at < ends_at)
);

CREATE INDEX idx_staff_shift_cabinet_user
    ON staff_shift (cabinet_id, user_id, starts_at);

GRANT SELECT, INSERT, UPDATE, DELETE ON staff_shift TO nubia_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON staff_shift TO nubia_seed;

ALTER TABLE staff_shift ENABLE ROW LEVEL SECURITY;
ALTER TABLE staff_shift FORCE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON staff_shift
    USING      (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid)
    WITH CHECK (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid);

COMMENT ON TABLE staff_shift IS
    'Créneaux planifiés d''un membre de l''équipe (planning d''équipe). Table tenant (cabinet_id). RLS fail-closed. Issue #7145.';

-- ---------------------------------------------------------------------------

CREATE TABLE leave_request (
    id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    cabinet_id UUID        NOT NULL REFERENCES cabinet(id),
    user_id    UUID        NOT NULL REFERENCES app_user(id),
    starts_at  TIMESTAMPTZ NOT NULL,
    ends_at    TIMESTAMPTZ NOT NULL,
    kind       TEXT        NOT NULL
        CHECK (kind IN ('paid_leave', 'unpaid_leave', 'sick_leave', 'other')),
    status     TEXT        NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'approved', 'rejected', 'cancelled')),
    decided_by UUID        REFERENCES app_user(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT leave_request_check_range CHECK (starts_at < ends_at)
);

CREATE INDEX idx_leave_request_cabinet_user
    ON leave_request (cabinet_id, user_id, starts_at);
CREATE INDEX idx_leave_request_cabinet_status
    ON leave_request (cabinet_id, status);

GRANT SELECT, INSERT, UPDATE, DELETE ON leave_request TO nubia_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON leave_request TO nubia_seed;

ALTER TABLE leave_request ENABLE ROW LEVEL SECURITY;
ALTER TABLE leave_request FORCE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON leave_request
    USING      (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid)
    WITH CHECK (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid);

COMMENT ON TABLE leave_request IS
    'Demande de congé/absence d''un membre de l''équipe, cycle pending → approved|rejected (+ cancelled). Table tenant (cabinet_id). RLS fail-closed. Issue #7145.';

-- ---------------------------------------------------------------------------

CREATE TABLE time_clock_entry (
    id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    cabinet_id UUID        NOT NULL REFERENCES cabinet(id),
    user_id    UUID        NOT NULL REFERENCES app_user(id),
    clock_in   TIMESTAMPTZ NOT NULL,
    clock_out  TIMESTAMPTZ,
    source     TEXT        NOT NULL DEFAULT 'manual'
        CHECK (source IN ('manual', 'mobile', 'badge')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT time_clock_entry_check_range CHECK (clock_out IS NULL OR clock_out > clock_in)
);

CREATE INDEX idx_time_clock_entry_cabinet_user
    ON time_clock_entry (cabinet_id, user_id, clock_in);

GRANT SELECT, INSERT, UPDATE, DELETE ON time_clock_entry TO nubia_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON time_clock_entry TO nubia_seed;

ALTER TABLE time_clock_entry ENABLE ROW LEVEL SECURITY;
ALTER TABLE time_clock_entry FORCE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON time_clock_entry
    USING      (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid)
    WITH CHECK (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid);

COMMENT ON TABLE time_clock_entry IS
    'Pointage (entrée/sortie) d''un membre de l''équipe, source de la saisie. Table tenant (cabinet_id). RLS fail-closed. Issue #7145.';
