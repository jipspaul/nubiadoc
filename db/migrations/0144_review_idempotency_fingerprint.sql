-- 0144_review_idempotency_fingerprint.sql
-- #3671 : POST /v1/reviews ne scope l'idempotence que par (patient_account_id,
-- idempotency_key), sans empreinte de requête -> une clé rejouée avec un
-- appointment_id différent renvoie silencieusement l'avis de la première
-- requête (le 2e avis n'est jamais créé). Jumeau de #3632 (bookings) et
-- #3620 (pharmacy-quote-intent).
-- fingerprint TEXT — empreinte (appointment_id + rating + comment) de la
-- requête d'origine ; une clé rejouée avec une empreinte différente est
-- rejetée en 409.
-- Issue : #3671

ALTER TABLE review ADD COLUMN idempotency_fingerprint TEXT;
