-- 0192_create_stock_inventory.sql
-- Inventaire cabinet (#4143) : le seul objet stock existant (stock_request,
-- migration 0125) est une demande de réappro cabinet→pharmacie sans
-- quantités ni inventaire réel côté cabinet.
--
-- stock_item : un article d'inventaire cabinet (consommable), avec la
-- quantité en stock et un seuil d'alerte.
-- stock_movement : un mouvement affectant un stock_item (réception,
-- consommation, ajustement, péremption), optionnellement rattaché à l'acte
-- qui a consommé le stock (traçabilité acte ↔ consommation).
-- ccam_act_stock_consumption : mapping catalogue — quelle quantité d'un
-- stock_item est consommée par défaut pour un acte CCAM donné, par cabinet
-- (le catalogue ccam_act est public/non tenant-scopé, mais le stock_item
-- référencé est propre à un cabinet — cette table doit donc, elle aussi,
-- être cabinet-scopée).
--
-- FK COMPOSITES (stock_item_id, cabinet_id) / (consultation_act_id,
-- cabinet_id) plutôt que des FK simples sur l'id seul : PostgreSQL fait
-- bypasser la RLS aux vérifications d'intégrité référentielle (FK/UNIQUE/PK)
-- même sous FORCE ROW LEVEL SECURITY — cf. #4137/migration 0190. Fix
-- standard : UNIQUE (id, cabinet_id) côté table référencée + FK composite
-- côté table référençante, un mismatch de cabinet_id ne correspond à aucune
-- ligne de l'index unique, la FK échoue en 23503 indépendamment de la RLS.

CREATE TABLE stock_item (
    id                uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    cabinet_id        uuid        NOT NULL REFERENCES cabinet(id),
    reference         text        NOT NULL,
    label             text        NOT NULL,
    unit              text        NOT NULL,
    quantity_on_hand  integer     NOT NULL DEFAULT 0,
    alert_threshold   integer,
    created_at        timestamptz NOT NULL DEFAULT now(),
    UNIQUE (cabinet_id, reference),
    UNIQUE (id, cabinet_id)
);

CREATE INDEX idx_stock_item_cabinet
    ON stock_item (cabinet_id);

CREATE TABLE stock_movement (
    id                   uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    cabinet_id           uuid        NOT NULL REFERENCES cabinet(id),
    stock_item_id        uuid        NOT NULL,
    delta                integer     NOT NULL CHECK (delta <> 0),
    reason               text        NOT NULL CHECK (reason IN ('reception', 'consumption', 'adjustment', 'peremption')),
    expiry_date          date,
    consultation_act_id  uuid,
    created_at           timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (stock_item_id, cabinet_id)
        REFERENCES stock_item (id, cabinet_id),
    FOREIGN KEY (consultation_act_id, cabinet_id)
        REFERENCES consultation_act (id, cabinet_id)
);

CREATE INDEX idx_stock_movement_stock_item
    ON stock_movement (stock_item_id);
CREATE INDEX idx_stock_movement_consultation_act
    ON stock_movement (consultation_act_id)
    WHERE consultation_act_id IS NOT NULL;

CREATE TABLE ccam_act_stock_consumption (
    id             uuid    PRIMARY KEY DEFAULT gen_random_uuid(),
    cabinet_id     uuid    NOT NULL REFERENCES cabinet(id),
    ccam_code      text    NOT NULL REFERENCES ccam_act(code),
    stock_item_id  uuid    NOT NULL,
    quantity       integer NOT NULL CHECK (quantity > 0),
    UNIQUE (cabinet_id, ccam_code, stock_item_id),
    FOREIGN KEY (stock_item_id, cabinet_id)
        REFERENCES stock_item (id, cabinet_id)
);

CREATE INDEX idx_ccam_act_stock_consumption_ccam_code
    ON ccam_act_stock_consumption (ccam_code);

-- RLS tenant (fail-closed : GUC absent → 0 ligne) sur les trois tables.
ALTER TABLE stock_item ENABLE ROW LEVEL SECURITY;
ALTER TABLE stock_item FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON stock_item
    FOR ALL
    TO nubia_app
    USING      (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid)
    WITH CHECK (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid);

ALTER TABLE stock_movement ENABLE ROW LEVEL SECURITY;
ALTER TABLE stock_movement FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON stock_movement
    FOR ALL
    TO nubia_app
    USING      (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid)
    WITH CHECK (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid);

ALTER TABLE ccam_act_stock_consumption ENABLE ROW LEVEL SECURITY;
ALTER TABLE ccam_act_stock_consumption FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON ccam_act_stock_consumption
    FOR ALL
    TO nubia_app
    USING      (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid)
    WITH CHECK (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid);

GRANT SELECT, INSERT, UPDATE, DELETE ON stock_item TO nubia_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON stock_movement TO nubia_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON ccam_act_stock_consumption TO nubia_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON stock_item TO nubia_seed;
GRANT SELECT, INSERT, UPDATE, DELETE ON stock_movement TO nubia_seed;
GRANT SELECT, INSERT, UPDATE, DELETE ON ccam_act_stock_consumption TO nubia_seed;

COMMENT ON TABLE stock_item IS
    'Article d''inventaire cabinet (consommable) : quantité en stock + seuil d''alerte. #4143.';
COMMENT ON TABLE stock_movement IS
    'Mouvement de stock (reception/consumption/adjustment/peremption), optionnellement rattaché à l''acte consommateur. #4143.';
COMMENT ON TABLE ccam_act_stock_consumption IS
    'Mapping catalogue : quantité d''un stock_item consommée par défaut pour un acte CCAM donné, par cabinet. #4143.';
