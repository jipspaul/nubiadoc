-- 0096_waiting_list_entry_unique_active.sql
-- Contrainte d'unicité : un patient ne peut avoir qu'une entrée ACTIVE
-- pour un même provider (anti-doublon DB-level, appuie le 409 du handler
-- POST /v1/waiting-list — issue #1670).

CREATE UNIQUE INDEX IF NOT EXISTS waiting_list_entry_active_unique
  ON waiting_list_entry (patient_id, provider_id)
  WHERE status = 'active';
