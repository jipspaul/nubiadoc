-- 0143_appointment_idempotency_fingerprint.sql
-- #3632 : POST /v1/bookings ne scope l'idempotence que par (cabinet_id,
-- idempotency_key), sans empreinte de requête -> une clé rejouée avec un
-- slot_id différent renvoie silencieusement le RDV de la première requête
-- (la 2e réservation n'est jamais créée). Jumeau de #3547 (payment).
-- fingerprint TEXT — empreinte (slot_id + motif) de la requête d'origine ;
-- une clé rejouée avec une empreinte différente est rejetée en 409.
-- Issue : #3632

ALTER TABLE appointment ADD COLUMN idempotency_fingerprint TEXT;
