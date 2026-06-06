-- 0057_conversation_soft_delete.sql
-- Ajoute soft-delete sur conversation (deleted_at) et updated_at.
-- Réf. : db/README §2 ("soft-delete obligatoire"), issue #823.
-- message est append-only : pas de deleted_at ni updated_at.

ALTER TABLE conversation
    ADD COLUMN IF NOT EXISTS updated_at  timestamptz NOT NULL DEFAULT now();

ALTER TABLE conversation
    ADD COLUMN IF NOT EXISTS deleted_at  timestamptz;
