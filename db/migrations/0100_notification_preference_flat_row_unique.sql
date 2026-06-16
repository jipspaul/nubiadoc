-- 0100_notification_preference_flat_row_unique.sql
-- Ajoute un index partiel UNIQUE sur notification_preference pour les lignes
-- "flat" (channel IS NULL AND type IS NULL), celles créées par le handler
-- PATCH /v1/account/notification-preferences avec le modèle booléen.
--
-- Contexte : la migration 0049 a supprimé UNIQUE(patient_account_id) et l'a
-- remplacé par UNIQUE(patient_account_id, channel, type) pour préparer le
-- modèle EAV. Or en SQL, les NULLs ne sont pas égaux entre eux → plusieurs
-- lignes avec channel=NULL et type=NULL pour le même patient_account_id
-- passaient sans conflit, cassant l'upsert du handler.
--
-- Ce partial unique index restaure l'unicité pour les lignes flat et permet
-- l'ON CONFLICT (patient_account_id) WHERE channel IS NULL AND type IS NULL
-- dans le handler.
--
-- Issue : #2035

CREATE UNIQUE INDEX notification_preference_flat_row_idx
  ON notification_preference (patient_account_id)
  WHERE channel IS NULL AND type IS NULL;
