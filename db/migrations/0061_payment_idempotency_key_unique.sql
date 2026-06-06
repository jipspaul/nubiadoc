-- 0061_payment_idempotency_key_unique.sql
-- Ajoute la contrainte UNIQUE sur payment.idempotency_key.
-- Réf. : docs/07 §6.3, issue #778.
-- Sans cette contrainte, un webhook Stripe/GoCardless rejoué insérerait un
-- doublon de paiement ; la contrainte UNIQUE garantit l'idempotence côté DB.
-- NULL est autorisé (paiements sans idempotency_key ne se conflictent pas entre eux).

ALTER TABLE payment
  ADD CONSTRAINT payment_idempotency_key_unique UNIQUE (idempotency_key);
