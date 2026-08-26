-- 0237_cabinet_payout_action.sql
-- Trace persistante des actions humaines sur le rapprochement bancaire
-- (#5969) : `POST /v1/cabinet/payouts/:id/reconcile` et
-- `/v1/cabinet/payouts/:id/flag-accountant` mutaient uniquement l'état
-- Bloc Flutter en mémoire (marquer rapproché perdu au refresh) ou ne
-- faisaient strictement rien (signaler au comptable). Cette table donne à
-- ces deux actions un effet réel et durable côté back : `list_payouts`
-- relit `reconciled` pour ne plus jamais régresser au recalcul mock, et
-- `flagged_to_accountant` trace l'alerte comptable (aucun autre système de
-- notification/audit disponible pour ce mock, cf. `cabinet_payouts.rs`).
--
-- UNIQUE(cabinet_id, payout_id, action) + `ON CONFLICT DO NOTHING` côté
-- handler : cliquer deux fois la même action reste idempotent.

CREATE TABLE cabinet_payout_action (
    id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    cabinet_id  uuid        NOT NULL REFERENCES cabinet(id),
    payout_id   text        NOT NULL,
    action      text        NOT NULL CHECK (action IN ('reconciled', 'flagged_to_accountant')),
    created_by  uuid        NOT NULL,
    created_at  timestamptz NOT NULL DEFAULT now(),
    UNIQUE (cabinet_id, payout_id, action)
);

CREATE INDEX idx_cabinet_payout_action_payout ON cabinet_payout_action (cabinet_id, payout_id);

ALTER TABLE cabinet_payout_action ENABLE ROW LEVEL SECURITY;
ALTER TABLE cabinet_payout_action FORCE ROW LEVEL SECURITY;

CREATE POLICY cabinet_payout_action_tenant_isolation ON cabinet_payout_action
    FOR ALL
    USING  (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid)
    WITH CHECK (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid);

GRANT SELECT, INSERT, UPDATE, DELETE ON cabinet_payout_action TO nubia_app;

COMMENT ON TABLE cabinet_payout_action IS
    'Actions humaines persistées sur le rapprochement bancaire (#5969) : rapprochement manuel (survit au refresh) et signalement comptable (trace DB).';
