-- 0035_conversation_list_policy.sql
-- Policy READ-ONLY patient sur cabinet via app.patient_account_id.
-- Permet à GET /v1/conversations de lire le raison_sociale du cabinet sans
-- positionner app.current_cabinet_id (liste multi-cabinets).
-- Permissive (OR avec tenant_isolation de 0011) : le cabinet conserve son accès.
-- Issue : #449

CREATE POLICY cabinet_patient_read ON cabinet
  FOR SELECT
  TO nubia_app
  USING (
    id IN (
      SELECT cabinet_id FROM patient
      WHERE patient_account_id = nullif(current_setting('app.patient_account_id', true), '')::uuid
    )
  );
