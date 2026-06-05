-- 0041_marketplace_slots_reviews.sql
-- Renomme l'index availability_slot_provider_time_idx (créé en 0012) en
-- slot_provider_time_idx, conformément à l'interface publique définie dans
-- docs/05 §9.2 et la spec issue #532.
-- Issue : #532

ALTER INDEX availability_slot_provider_time_idx RENAME TO slot_provider_time_idx;
