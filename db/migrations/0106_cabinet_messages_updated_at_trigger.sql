-- 0106_cabinet_messages_updated_at_trigger.sql
-- Fonction partagée set_updated_at() + table cabinet_messages +
-- trigger BEFORE UPDATE maintenant updated_at = now(). Issue : #2237

CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION set_updated_at() IS
    'Trigger partagé : positionne NEW.updated_at = now() avant chaque UPDATE.';

-- Messages internes au cabinet (staff ↔ staff), hors messagerie patient.
CREATE TABLE cabinet_messages (
    id         uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    cabinet_id uuid        NOT NULL REFERENCES cabinet(id),
    sender_id  uuid        NOT NULL REFERENCES app_user(id),
    body       text        NOT NULL,
    read_at    timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz
);

ALTER TABLE cabinet_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE cabinet_messages FORCE ROW LEVEL SECURITY;

CREATE POLICY cabinet_messages_tenant_isolation ON cabinet_messages
    USING (cabinet_id = current_setting('app.current_cabinet_id', true)::uuid)
    WITH CHECK (cabinet_id = current_setting('app.current_cabinet_id', true)::uuid);

GRANT SELECT, INSERT, UPDATE, DELETE ON cabinet_messages TO nubia_app;
GRANT SELECT, INSERT ON cabinet_messages TO nubia_seed;

CREATE TRIGGER cabinet_messages_set_updated_at
    BEFORE UPDATE ON cabinet_messages
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

COMMENT ON TRIGGER cabinet_messages_set_updated_at ON cabinet_messages IS
    'Maintient updated_at = now() avant chaque UPDATE (DB-T023, issue #2237).';
