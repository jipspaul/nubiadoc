-- 0108_prescription_line_rls.sql
-- RLS explicite sur prescription_item (« ligne d'ordonnance ») :
--   - ENABLE + FORCE déjà posés par 0011 (idempotents — ALTER sans effet si déjà actifs).
--   - Remplace la policy générique `tenant_isolation` (0011, immuable) par deux policies
--     nommées conformément à DB-T026 :
--       1. prescription_line_cabinet_isolation FOR ALL  — isolation cabinet (même bornes)
--       2. prescription_line_patient_read     FOR SELECT — patient titulaire via
--          prescription_item → prescription → patient → patient_account_id (fail-closed)
-- Issue : #2448

-- Suppression de la policy générique créée par 0011 (immuable, correction = nouvelle migration).
DROP POLICY IF EXISTS tenant_isolation ON prescription_item;

-- Garde-fous idempotents (déjà actifs depuis 0011 ; inclus pour auto-documenter).
ALTER TABLE prescription_item ENABLE ROW LEVEL SECURITY;
ALTER TABLE prescription_item FORCE ROW LEVEL SECURITY;

-- ---------------------------------------------------------------------------
-- Policy 1 : isolation cabinet — couvre SELECT / INSERT / UPDATE / DELETE.
-- Fail-closed : nullif(...,'')::uuid → NULL si GUC absent → 0 ligne visible.
-- ---------------------------------------------------------------------------
CREATE POLICY prescription_line_cabinet_isolation ON prescription_item
  FOR ALL
  USING (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid)
  WITH CHECK (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid);

-- ---------------------------------------------------------------------------
-- Policy 2 : lecture patient titulaire — SELECT uniquement.
-- Chemin transitif : prescription_item.prescription_id
--                    → prescription.patient_id
--                    → patient.patient_account_id
-- Fail-closed : si app.patient_account_id absent/vide → NULL → 0 ligne.
-- ---------------------------------------------------------------------------
CREATE POLICY prescription_line_patient_read ON prescription_item
  FOR SELECT
  USING (
    prescription_id IN (
      SELECT id FROM prescription
      WHERE patient_id IN (
        SELECT id FROM patient
        WHERE patient_account_id = nullif(current_setting('app.patient_account_id', true), '')::uuid
      )
    )
  );
