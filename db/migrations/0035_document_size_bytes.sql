-- 0035_document_size_bytes.sql
-- Ajoute size_bytes à la table document pour retourner la taille au client
-- (GET /v1/documents/{id} — issue #446).
-- DEFAULT 0 assure la compatibilité avec les documents existants.

ALTER TABLE document
  ADD COLUMN IF NOT EXISTS size_bytes bigint NOT NULL DEFAULT 0;
