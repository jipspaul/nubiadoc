-- 0085_create_reminder.sql
-- Rappels automatiques avant RDV (centre de notifications patient, W27).
-- Table tenant (cabinet_id) liée à appointment + patient.
-- Permet de planifier et suivre l'envoi de rappels multi-canaux (push, email, sms).
-- Issue : #1142

CREATE TABLE reminder (
    id             UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    cabinet_id     UUID        NOT NULL REFERENCES cabinet(id),
    appointment_id UUID        NOT NULL REFERENCES appointment(id),
    patient_id     UUID        NOT NULL REFERENCES patient(id),
    scheduled_at   TIMESTAMPTZ NOT NULL,
    kind           TEXT        NOT NULL DEFAULT 'rdv_rappel',
    channel        TEXT        NOT NULL DEFAULT 'push',
    status         TEXT        NOT NULL DEFAULT 'pending',
    sent_at        TIMESTAMPTZ,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT reminder_status_check  CHECK (status  IN ('pending', 'sent', 'failed', 'cancelled')),
    CONSTRAINT reminder_kind_check    CHECK (kind    IN ('rdv_rappel', 'rdv_confirmation', 'rdv_follow_up')),
    CONSTRAINT reminder_channel_check CHECK (channel IN ('push', 'email', 'sms'))
);

-- Index tenant-first pour récupération par cabinet + statut (worker de rappels).
CREATE INDEX idx_reminder_cabinet_status_scheduled
    ON reminder (cabinet_id, status, scheduled_at);

GRANT SELECT, INSERT, UPDATE ON reminder TO nubia_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON reminder TO nubia_seed;

-- RLS : isolation par cabinet (même pattern que les tables tenant standard).
ALTER TABLE reminder ENABLE ROW LEVEL SECURITY;
ALTER TABLE reminder FORCE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON reminder
    USING      (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid)
    WITH CHECK (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid);

COMMENT ON TABLE reminder IS 'Rappels automatiques pré-RDV (push/email/sms). Table tenant (cabinet_id). RLS fail-closed. Réf. W27 PLAN-ATOMIC.';
