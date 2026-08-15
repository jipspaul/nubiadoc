-- 0229_pharmacy_quote_order_index.sql
-- Index sur pharmacy_quote.order_id (#5488) : GET /v1/pharmacy/orders[/{id}]
-- corrèle désormais chaque commande à son devis d'officine accepté (bloc
-- facturation billing_total_cents/…) via une sous-requête sur
-- pharmacy_quote.order_id — jusqu'ici sans index dédié (seuls
-- idx_pharmacy_quote_pharmacy_status et idx_pharmacy_quote_account
-- existaient, 0127), ce qui aurait forcé un scan complet par commande listée.

CREATE INDEX idx_pharmacy_quote_order
    ON pharmacy_quote (order_id)
    WHERE order_id IS NOT NULL;
