-- 0249_pharmacy_order_pickup_short_code.sql
-- #6419 : la maquette design-v2 prescrit un code court dictable au comptoir
-- (« Ou dictez ce code au pharmacien ») — le token du QR (64 hex, lot B3)
-- n'est pas dictable. Colonne séparée pour ne pas affaiblir l'entropie du
-- QR : le token long reste l'unique contenu scanné, le code court est un
-- second chemin de résolution, dérivé du même HMAC (cf. get_pickup_token).

ALTER TABLE pharmacy_order
    ADD COLUMN pickup_short_code VARCHAR(8);

CREATE INDEX idx_pharmacy_order_pickup_short_code
    ON pharmacy_order (pickup_short_code)
    WHERE pickup_short_code IS NOT NULL;
