-- 0058_appointment_idempotency_key.sql
-- Idempotency-Key pour POST /v1/appointments (issue #829).
-- Permet au client de rejouer la requête sans créer de doublon.
-- Contrainte UNIQUE partielle : une clé donnée ne peut exister qu'une fois
-- par cabinet (les clés sont générées côté client, pas globalement uniques).

ALTER TABLE appointment
  ADD COLUMN idempotency_key text;

CREATE UNIQUE INDEX idx_appointment_idempotency_key
  ON appointment (cabinet_id, idempotency_key)
  WHERE idempotency_key IS NOT NULL;
