-- 0074_create_webhook_event_log.sql
-- Traçage des webhooks entrants (Yousign, Stripe, GoCardless).
-- Append-only : trigger bloque UPDATE/DELETE + révocation des privilèges correspondants.
-- Idempotence : UNIQUE (provider, event_id).
-- Pas de cabinet_id → pas de RLS cabinet (entité plateforme, cf. db/README §4).
-- Réf. : docs/12-api-reference.md §21 ; docs/07 §6.3 ; issue #698. Dépend de #697.

CREATE TABLE webhook_event_log (
    id           uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    provider     text        NOT NULL,
    event_id     text        NOT NULL,
    payload      jsonb       NOT NULL DEFAULT '{}',
    status       text        NOT NULL DEFAULT 'pending',
    processed_at timestamptz,
    error        text,
    created_at   timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT webhook_event_log_provider_event_id_key UNIQUE (provider, event_id)
);

COMMENT ON TABLE webhook_event_log IS
    'Traçage append-only des webhooks entrants (Yousign, Stripe, GoCardless). Idempotence via (provider, event_id). Issue #698.';
COMMENT ON COLUMN webhook_event_log.provider IS
    'Fournisseur émetteur du webhook : yousign, stripe, gocardless, ...';
COMMENT ON COLUMN webhook_event_log.event_id IS
    'Identifiant unique du webhook côté fournisseur (clé d''idempotence).';
COMMENT ON COLUMN webhook_event_log.status IS
    'État du traitement : pending, processed, failed.';

-- ---------------------------------------------------------------------------
-- Trigger append-only : toute tentative d'UPDATE ou DELETE lève une erreur.
-- Defense in depth : les privilèges UPDATE/DELETE sont aussi révoqués ci-dessous.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION webhook_event_log_append_only()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'UPDATE' THEN
        RAISE EXCEPTION 'webhook_event_log est append-only : UPDATE interdit (id=%)', OLD.id
            USING ERRCODE = 'P0001';
    ELSIF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION 'webhook_event_log est append-only : DELETE interdit (id=%)', OLD.id
            USING ERRCODE = 'P0001';
    END IF;
    RETURN NULL;
END;
$$;

CREATE TRIGGER webhook_event_log_no_update
    BEFORE UPDATE ON webhook_event_log
    FOR EACH ROW EXECUTE FUNCTION webhook_event_log_append_only();

CREATE TRIGGER webhook_event_log_no_delete
    BEFORE DELETE ON webhook_event_log
    FOR EACH ROW EXECUTE FUNCTION webhook_event_log_append_only();

-- ---------------------------------------------------------------------------
-- Grants : nubia_app peut SELECT (contrôle idempotence) + INSERT uniquement.
-- Les DEFAULT PRIVILEGES de 0001 ont accordé SELECT/INSERT/UPDATE/DELETE ;
-- on révoque UPDATE et DELETE (defense in depth, combiné au trigger ci-dessus).
-- nubia_seed : pas d'accès (données de plateforme, pas de seed démo).
-- ---------------------------------------------------------------------------
REVOKE UPDATE, DELETE ON webhook_event_log FROM nubia_app;
REVOKE ALL ON webhook_event_log FROM nubia_seed;
