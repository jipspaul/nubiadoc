-- 0032_appointment_documents_hint.sql
-- Colonne hint documents pour la préparation RDV (GET /v1/appointments/:id/preparation).
-- documents_hint : texte libre (null = aucun document spécifique demandé).

ALTER TABLE appointment
  ADD COLUMN documents_hint text;
