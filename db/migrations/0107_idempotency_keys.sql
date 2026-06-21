-- 0107_idempotency_keys.sql
-- Table générique d'idempotence pour les mutations sensibles (POST /v1/payments/intent).
-- key TEXT PK    — clé fournie par le client (header Idempotency-Key).
-- response JSONB — réponse sérialisée, renvoyée à l'identique si replay < 24h.
-- created_at     — horodatage de la première exécution (TTL côté lecture).

CREATE TABLE idempotency_keys (
    key        TEXT        NOT NULL,
    response   JSONB       NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (key)
);

-- Index pour le cleanup périodique et le filtre TTL.
CREATE INDEX ON idempotency_keys (created_at);

-- RLS : pas de tenant_id (table cross-tenant), accès contrôlé par policy applicative.
ALTER TABLE idempotency_keys ENABLE ROW LEVEL SECURITY;
ALTER TABLE idempotency_keys FORCE ROW LEVEL SECURITY;

-- nubia_app : INSERT + SELECT (les handlers API stockent et relisent les réponses).
CREATE POLICY idempotency_keys_app ON idempotency_keys
    FOR ALL TO nubia_app
    USING (true) WITH CHECK (true);

-- nubia_seed : accès complet (données de démo fictives).
CREATE POLICY idempotency_keys_seed ON idempotency_keys
    FOR ALL TO nubia_seed
    USING (true) WITH CHECK (true);
