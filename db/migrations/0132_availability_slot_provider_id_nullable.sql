-- 0132_availability_slot_provider_id_nullable.sql
-- Rend availability_slot.provider_id nullable : depuis 0075 (cabinet_slots_bo),
-- un créneau BO peut être créé pour un praticien sans provider marketplace associé
-- (POST /v1/cabinet/slots). provider_id NOT NULL (hérité de 0009, marketplace-only)
-- faisait échouer ces créations avec une violation NOT NULL.
-- Les requêtes marketplace (JOIN provider) excluent naturellement les slots sans
-- provider_id.

ALTER TABLE availability_slot
  ALTER COLUMN provider_id DROP NOT NULL;
