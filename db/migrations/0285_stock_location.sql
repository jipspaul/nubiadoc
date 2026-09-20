-- 0285_stock_location.sql
-- #7184 (DP-F12.a) : `stock_item` (migration 0192) ne porte qu'une seule
-- quantité (`quantity_on_hand`) par article, sans notion de localisation
-- (stock principal, salle 1, salle 2…). On ajoute :
--   stock_location      : les localisations de stock d'un cabinet, avec
--                         un flag `is_main` (au plus une localisation
--                         principale par cabinet).
--   stock_item_location : la quantité (et le seuil d'alerte) d'un article
--                         par localisation.
-- `stock_item.quantity_on_hand`/`alert_threshold` sont conservés tels quels
-- (l'API/le front qui les lisent ne sont pas modifiés par cette migration —
-- fondation DB uniquement) ; le backfill crée, pour chaque cabinet ayant au
-- moins un stock_item, une localisation "Stock principal" et y bascule
-- l'intégralité des quantités existantes.
--
-- FK COMPOSITES (item_id, cabinet_id) / (location_id, cabinet_id) plutôt que
-- des FK simples sur l'id seul : PostgreSQL fait bypasser la RLS aux
-- vérifications d'intégrité référentielle (FK/UNIQUE/PK) même sous FORCE ROW
-- LEVEL SECURITY — cf. #4137/migration 0190. Fix standard : UNIQUE (id,
-- cabinet_id) côté table référencée + FK composite côté table référençante.

CREATE TABLE stock_location (
    id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    cabinet_id  uuid        NOT NULL REFERENCES cabinet(id),
    name        text        NOT NULL,
    is_main     boolean     NOT NULL DEFAULT false,
    created_at  timestamptz NOT NULL DEFAULT now(),
    UNIQUE (cabinet_id, name),
    UNIQUE (id, cabinet_id)
);

CREATE INDEX idx_stock_location_cabinet
    ON stock_location (cabinet_id);

-- Au plus une localisation principale par cabinet.
CREATE UNIQUE INDEX idx_stock_location_one_main
    ON stock_location (cabinet_id)
    WHERE is_main;

CREATE TABLE stock_item_location (
    id           uuid    PRIMARY KEY DEFAULT gen_random_uuid(),
    cabinet_id   uuid    NOT NULL REFERENCES cabinet(id),
    item_id      uuid    NOT NULL,
    location_id  uuid    NOT NULL,
    quantity     integer NOT NULL DEFAULT 0,
    threshold    integer,
    UNIQUE (item_id, location_id),
    FOREIGN KEY (item_id, cabinet_id)
        REFERENCES stock_item (id, cabinet_id),
    FOREIGN KEY (location_id, cabinet_id)
        REFERENCES stock_location (id, cabinet_id)
);

CREATE INDEX idx_stock_item_location_item
    ON stock_item_location (item_id);
CREATE INDEX idx_stock_item_location_location
    ON stock_item_location (location_id);

-- RLS tenant (fail-closed : GUC absent → 0 ligne) sur les deux tables.
ALTER TABLE stock_location ENABLE ROW LEVEL SECURITY;
ALTER TABLE stock_location FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON stock_location
    FOR ALL
    TO nubia_app
    USING      (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid)
    WITH CHECK (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid);

ALTER TABLE stock_item_location ENABLE ROW LEVEL SECURITY;
ALTER TABLE stock_item_location FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON stock_item_location
    FOR ALL
    TO nubia_app
    USING      (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid)
    WITH CHECK (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid);

GRANT SELECT, INSERT, UPDATE, DELETE ON stock_location TO nubia_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON stock_item_location TO nubia_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON stock_location TO nubia_seed;
GRANT SELECT, INSERT, UPDATE, DELETE ON stock_item_location TO nubia_seed;

COMMENT ON TABLE stock_location IS
    'Localisation de stock d''un cabinet (principal, salle…). Au plus une localisation is_main par cabinet. #7184.';
COMMENT ON TABLE stock_item_location IS
    'Quantité (et seuil d''alerte) d''un stock_item par stock_location. #7184.';

-- ===========================================================================
-- Backfill : pour chaque cabinet ayant au moins un stock_item, crée une
-- localisation "Stock principal" (is_main = true) et y bascule
-- l'intégralité des quantités/seuils existants de stock_item.
-- ===========================================================================
INSERT INTO stock_location (cabinet_id, name, is_main)
SELECT DISTINCT cabinet_id, 'Stock principal', true
FROM stock_item;

INSERT INTO stock_item_location (cabinet_id, item_id, location_id, quantity, threshold)
SELECT si.cabinet_id, si.id, sl.id, si.quantity_on_hand, si.alert_threshold
FROM stock_item si
JOIN stock_location sl
    ON sl.cabinet_id = si.cabinet_id
    AND sl.is_main;
