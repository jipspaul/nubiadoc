-- 0093_quote_deposit_paid.sql
-- Ajoute quote.deposit_paid (bool, false par défaut) : marqué true par le
-- handler GoCardless webhook (payments.confirmed) quand le paiement d'acompte
-- lié au devis est confirmé.
-- Réf. : issue #1663, docs/12-api-reference.md §21.
ALTER TABLE quote
  ADD COLUMN IF NOT EXISTS deposit_paid boolean NOT NULL DEFAULT false;
