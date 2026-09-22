-- 0292_create_lab_price_list.sql
-- [DP-F19.a] Grille tarifaire par laboratoire (#7165).
--
-- lab_price_list : catalogue des prix pratiqués par chaque laboratoire
-- prothétique (lab_name/item_label/item_code/price_cents), avec valid_from
-- pour tracer l'historique des tarifs sans réécrire les lignes existantes
-- (migrations forward-only, mêmes contraintes sur les données applicatives).
-- Jusqu'ici lab_work_order.purchase_price_cents (migration 0193) est saisi
-- à la main à chaque bon de travail — cette grille permet de le valoriser
-- automatiquement et de calculer la marge (prix labo vs prix facturé
-- patient).
--
-- lab_work_order.price_list_item_id (nullable, ajouté ici) relie
-- optionnellement un bon de travail à la ligne de grille tarifaire utilisée
-- pour le valoriser ; nullable car purchase_price_cents reste saisissable à
-- la main (labo hors grille, tarif négocié ponctuel).
--
-- FK COMPOSITE (price_list_item_id, cabinet_id) plutôt qu'une FK simple sur
-- l'id seul : PostgreSQL fait bypasser la RLS aux vérifications d'intégrité
-- référentielle (FK) même sous FORCE ROW LEVEL SECURITY (#4137/migration
-- 0190) — même pattern que lab_work_order (0193) / cabinet_equipment (0291).
-- lab_price_list_id_cabinet_uniq est créée ci-dessous pour ce besoin.

CREATE TABLE lab_price_list (
    id           uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    cabinet_id   uuid        NOT NULL REFERENCES cabinet(id),
    lab_name     text        NOT NULL,
    item_label   text        NOT NULL,
    item_code    text        NOT NULL,
    price_cents  integer     NOT NULL CHECK (price_cents >= 0),
    valid_from   date        NOT NULL DEFAULT CURRENT_DATE,
    created_at   timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT lab_price_list_lab_name_not_blank CHECK (btrim(lab_name) <> ''),
    CONSTRAINT lab_price_list_item_label_not_blank CHECK (btrim(item_label) <> ''),
    CONSTRAINT lab_price_list_item_code_not_blank CHECK (btrim(item_code) <> ''),
    CONSTRAINT lab_price_list_lab_item_valid_from_uniq
        UNIQUE (cabinet_id, lab_name, item_code, valid_from),
    CONSTRAINT lab_price_list_id_cabinet_uniq UNIQUE (id, cabinet_id)
);

CREATE INDEX idx_lab_price_list_cabinet
    ON lab_price_list (cabinet_id);
CREATE INDEX idx_lab_price_list_cabinet_lab_item
    ON lab_price_list (cabinet_id, lab_name, item_code, valid_from DESC);

ALTER TABLE lab_work_order
    ADD COLUMN price_list_item_id uuid;
ALTER TABLE lab_work_order
    ADD CONSTRAINT lab_work_order_price_list_item_id_fkey
    FOREIGN KEY (price_list_item_id, cabinet_id)
    REFERENCES lab_price_list (id, cabinet_id);

CREATE INDEX idx_lab_work_order_price_list_item
    ON lab_work_order (price_list_item_id)
    WHERE price_list_item_id IS NOT NULL;

-- RLS tenant (fail-closed : GUC absent → 0 ligne).
ALTER TABLE lab_price_list ENABLE ROW LEVEL SECURITY;
ALTER TABLE lab_price_list FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON lab_price_list
    FOR ALL
    TO nubia_app
    USING      (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid)
    WITH CHECK (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid);

GRANT SELECT, INSERT, UPDATE, DELETE ON lab_price_list TO nubia_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON lab_price_list TO nubia_seed;

COMMENT ON TABLE lab_price_list IS
    'Grille tarifaire par laboratoire (libellé, code interne, prix, date de validité) pour valoriser automatiquement le coût d''un bon de travail et calculer la marge. Table tenant (cabinet_id). RLS fail-closed. #7165.';
COMMENT ON COLUMN lab_price_list.valid_from IS
    'Date de début de validité du tarif : permet de tracer l''historique sans réécrire les lignes existantes (#7165).';
COMMENT ON COLUMN lab_work_order.price_list_item_id IS
    'Ligne de grille tarifaire (lab_price_list) utilisée pour valoriser ce bon de travail, optionnelle (#7165).';
