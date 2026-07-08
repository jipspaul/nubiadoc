-- 0136_payment_pharmacy_quote.sql
-- Ouvre un chemin de paiement pour un devis d'officine accepté (#3505) :
-- jusqu'ici `payment.quote_id` ne référence que le devis dentaire cabinet-scopé
-- (`quote`), aucune colonne ne permettait de lier un paiement à un
-- `pharmacy_quote` (lot B7, épic #3323). `cabinet_id`/`patient_id` restent
-- résolus via `pharmacy_order.cabinet_id` + `patient.patient_account_id`
-- (même patient, cabinet d'origine de l'ordonnance) : pas de relaxation de
-- contrainte nécessaire, seule la colonne de référence manque.
ALTER TABLE payment
  ADD COLUMN IF NOT EXISTS pharmacy_quote_id uuid REFERENCES pharmacy_quote(id);

CREATE INDEX IF NOT EXISTS idx_payment_pharmacy_quote
    ON payment (pharmacy_quote_id) WHERE pharmacy_quote_id IS NOT NULL;
