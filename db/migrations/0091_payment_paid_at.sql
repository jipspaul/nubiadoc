-- 0091_payment_paid_at.sql
-- Ajoute la colonne paid_at à payment pour enregistrer l'horodatage de confirmation
-- GoCardless (payments.confirmed) et Stripe (payment_intent.succeeded).
-- Réf. : issue #1455 (T1437.b), handler gocardless_webhook.
ALTER TABLE payment
  ADD COLUMN IF NOT EXISTS paid_at timestamptz;
