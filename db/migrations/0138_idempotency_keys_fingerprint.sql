-- 0138_idempotency_keys_fingerprint.sql
-- #3547 : une Idempotency-Key n'était scopée que par `key`, sans empreinte de
-- requête ni de compte -> rejouée avec un autre quote_id/amount_cents, elle
-- renvoyait silencieusement le paiement de la première requête.
-- fingerprint TEXT — empreinte (account_id + paramètres métier) de la requête
-- d'origine ; une clé rejouée avec une empreinte différente est rejetée en 409.
-- Issue : #3547

ALTER TABLE idempotency_keys ADD COLUMN fingerprint TEXT NOT NULL DEFAULT '';
