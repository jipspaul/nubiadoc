-- 0043_payment_method_client_secret.sql
-- Ajoute method et client_secret à payment pour POST /v1/payments/intent.
-- method  : canal de paiement (card, apple_pay, google_pay, sepa).
-- client_secret : secret Stripe retourné au client pour confirmer le PaymentIntent côté front.
--                 Stocké pour idempotence : une clé Idempotency-Key retourne toujours le même secret.
ALTER TABLE payment
  ADD COLUMN IF NOT EXISTS method        text CHECK (method IN ('card','apple_pay','google_pay','sepa')),
  ADD COLUMN IF NOT EXISTS client_secret text;
