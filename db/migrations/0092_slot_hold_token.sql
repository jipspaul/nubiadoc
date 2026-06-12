-- 0092_slot_hold_token.sql
-- Ajoute hold_token TEXT NULL sur availability_slot pour le mécanisme de hold éphémère.
-- Réf. : docs/12-api-reference.md §12.3, issue #1584.

ALTER TABLE availability_slot
  ADD COLUMN IF NOT EXISTS hold_token TEXT NULL;
