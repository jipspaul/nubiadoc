-- 0041_rename_slot_provider_time_idx.sql
-- Renomme l'index pour correspondre au contrat pgTAP de l'issue #532.
ALTER INDEX availability_slot_provider_time_idx RENAME TO slot_provider_time_idx;
