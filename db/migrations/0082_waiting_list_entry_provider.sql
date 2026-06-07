-- 0082_waiting_list_entry_provider.sql
-- Ajoute `provider_id` à `waiting_list_entry` pour le handler POST /v1/waiting-list (US-P12).
-- Réf. : docs/12-api-reference.md §7.

ALTER TABLE waiting_list_entry
  ADD COLUMN IF NOT EXISTS provider_id uuid REFERENCES provider(id);
