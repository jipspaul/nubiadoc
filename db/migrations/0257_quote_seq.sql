-- 0257_quote_seq.sql
-- #6370 : la colonne « Devis » du suivi secrétariat (design-v2) affiche
-- l'UUID technique du devis, faute de référence lisible — `quote` n'a jamais
-- porté de numéro (contrairement à `pharmacy_order.order_seq`/`order_ref`,
-- migration 0245, #6253, exposée en `CMD-0042`). Même logique ici :
-- quote_seq : compteur global (identity), formaté `DEV-0042` à la lecture
-- (api/src/cabinet_quotes.rs, quote_ref) — même pattern que order_seq (0245)
-- et audit_log.id (0008).

ALTER TABLE quote
    ADD COLUMN quote_seq bigint GENERATED ALWAYS AS IDENTITY;

COMMENT ON COLUMN quote.quote_seq IS
    'Compteur global, formaté "DEV-0042" à la lecture (quote_ref). Jamais exposé brut.';
