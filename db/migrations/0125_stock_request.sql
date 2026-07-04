-- 0125_stock_request.sql
-- Demandes de stock cabinet → pharmacie (lot B5, épic #3323).
-- Deux ancres RLS : le cabinet émetteur (GUC app.current_cabinet_id) et la
-- pharmacie destinataire (GUC app.current_pharmacy_id). Fail-closed.
-- items jsonb [{label, qty, note?}] — JAMAIS de donnée patient (docs/07 §2.7).
-- Cycle : sent → accepted|rejected → fulfilled, + cancelled (cabinet, tant
-- que sent). Pas de DELETE pour l'app.
-- Issue : #3310

CREATE TABLE stock_request (
    id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    cabinet_id    UUID        NOT NULL REFERENCES cabinet(id),
    pharmacy_id   UUID        NOT NULL REFERENCES pharmacy(id),
    created_by    UUID        NOT NULL,
    cabinet_name  TEXT        NOT NULL,
    items         JSONB       NOT NULL DEFAULT '[]',
    status        TEXT        NOT NULL DEFAULT 'sent'
        CHECK (status IN ('sent', 'accepted', 'rejected', 'fulfilled', 'cancelled')),
    response_note TEXT,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_stock_request_pharmacy_status ON stock_request (pharmacy_id, status);
CREATE INDEX idx_stock_request_cabinet ON stock_request (cabinet_id);

REVOKE ALL ON stock_request FROM nubia_app;
GRANT SELECT, INSERT, UPDATE ON stock_request TO nubia_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON stock_request TO nubia_seed;

ALTER TABLE stock_request ENABLE ROW LEVEL SECURITY;
ALTER TABLE stock_request FORCE ROW LEVEL SECURITY;

-- Cabinet émetteur : lecture + création + annulation (WITH CHECK interdit de
-- forger une réponse pharmacie).
CREATE POLICY stock_request_cabinet_select ON stock_request
    FOR SELECT TO nubia_app
    USING (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid);
CREATE POLICY stock_request_cabinet_insert ON stock_request
    FOR INSERT TO nubia_app
    WITH CHECK (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid);
CREATE POLICY stock_request_cabinet_update ON stock_request
    FOR UPDATE TO nubia_app
    USING (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid)
    WITH CHECK (
        cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid
        AND status IN ('sent', 'cancelled')
    );

-- Pharmacie destinataire : lecture + réponse (jamais d'annulation).
CREATE POLICY stock_request_pharmacy_select ON stock_request
    FOR SELECT TO nubia_app
    USING (pharmacy_id = nullif(current_setting('app.current_pharmacy_id', true), '')::uuid);
CREATE POLICY stock_request_pharmacy_update ON stock_request
    FOR UPDATE TO nubia_app
    USING (pharmacy_id = nullif(current_setting('app.current_pharmacy_id', true), '')::uuid)
    WITH CHECK (
        pharmacy_id = nullif(current_setting('app.current_pharmacy_id', true), '')::uuid
        AND status <> 'cancelled'
    );

CREATE POLICY stock_request_seed_all ON stock_request
    TO nubia_seed USING (true) WITH CHECK (true);

COMMENT ON TABLE stock_request IS
    'Demande de stock cabinet → pharmacie (items jsonb sans donnée patient). Deux ancres RLS. Cycle sent → accepted|rejected → fulfilled (+ cancelled cabinet). Réf. épic #3323.';
