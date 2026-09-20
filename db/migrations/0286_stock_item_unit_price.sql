-- 0286_stock_item_unit_price.sql
-- #7183 (DP-F12.b) : `POST /v1/stock/import` saisit une facture fournisseur
-- ligne à ligne (`ref;libellé;quantité;prix`) sans OCR — `stock_item` n'a
-- aucune colonne pour conserver le prix unitaire de la ligne importée.
-- `unit_price_cents` (comme les autres montants du repo, cf. `amount_cents`
-- sur `quote_item`) est nullable : un article créé hors import (formulaire
-- manuel, `stock_items.rs::create_stock_item`) n'a pas de prix connu.

ALTER TABLE stock_item ADD COLUMN unit_price_cents integer CHECK (unit_price_cents IS NULL OR unit_price_cents >= 0);

COMMENT ON COLUMN stock_item.unit_price_cents IS
    'Prix unitaire (centimes) de la dernière ligne de facture importée pour cet article. #7183.';
