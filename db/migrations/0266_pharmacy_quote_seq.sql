-- 0266_pharmacy_quote_seq.sql
-- #7141 : la colonne « Devis » de la file d'officine (design-v2) affiche
-- l'UUID technique du devis pharmacie, faute de référence lisible —
-- `pharmacy_quote` est le seul des trois compteurs métier (avec
-- `pharmacy_order.order_seq`, migration 0245, #6253, et `quote.quote_seq`,
-- migration 0257, #6370) à ne pas avoir suivi.
-- quote_seq : compteur global (identity), formaté `DEV-P-0042` à la lecture
-- (api/src/pharmacy/quotes.rs, quote_ref) — même pattern que order_seq/
-- quote_seq, préfixe `-P-` pour le distinguer du devis dentaire (`DEV-0042`).

ALTER TABLE pharmacy_quote
    ADD COLUMN quote_seq bigint GENERATED ALWAYS AS IDENTITY;

COMMENT ON COLUMN pharmacy_quote.quote_seq IS
    'Compteur global, formaté "DEV-P-0042" à la lecture (quote_ref). Jamais exposé brut.';
