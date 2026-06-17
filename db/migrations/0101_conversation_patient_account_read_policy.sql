-- 0101_conversation_patient_account_read_policy.sql
-- Corrige les policies patient READ sur conversation et message.
-- Contexte : migration 0036 a rendu patient_id nullable dans conversation et
-- a ajouté patient_account_id. POST /v1/conversations insère uniquement
-- patient_account_id (sans patient_id) → les policies de 0029 filtraient
-- uniquement via patient_id IN (...), rendant ces conversations invisibles
-- au patient connecté.
-- Fix : étendre le USING avec un OR sur patient_account_id direct.
-- Issue : #2033

DROP POLICY conversation_patient_read ON conversation;
CREATE POLICY conversation_patient_read ON conversation
  FOR SELECT
  TO nubia_app
  USING (
    patient_id IN (
      SELECT id FROM patient
      WHERE patient_account_id = nullif(current_setting('app.patient_account_id', true), '')::uuid
    )
    OR patient_account_id = nullif(current_setting('app.patient_account_id', true), '')::uuid
  );

DROP POLICY message_patient_read ON message;
CREATE POLICY message_patient_read ON message
  FOR SELECT
  TO nubia_app
  USING (
    conversation_id IN (
      SELECT id FROM conversation
      WHERE patient_id IN (
        SELECT id FROM patient
        WHERE patient_account_id = nullif(current_setting('app.patient_account_id', true), '')::uuid
      )
      OR patient_account_id = nullif(current_setting('app.patient_account_id', true), '')::uuid
    )
  );
