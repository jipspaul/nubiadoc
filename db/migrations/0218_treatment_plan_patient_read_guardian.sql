-- 0218_treatment_plan_patient_read_guardian.sql
-- Étend treatment_plan_patient_read (migration 0038) à la branche tutelle
-- (#4596/QA-20260802-4), symétriquement à appointment_patient_read
-- (migration 0196, #4274) : un plan de traitement créé pour un dépendant
-- (patient_id rattaché au patient_account_id du DÉPENDANT, pas du tuteur)
-- était invisible côté tuteur : GET /treatment-plans l'omet, GET
-- /treatment-plans/:id → 404. Le plan existait bien côté cabinet, orphelin
-- côté patient — cul-de-sac clinique (le dépendant n'a aucun login).
--
-- La sous-requête `SELECT id FROM patient WHERE ...` reste soumise à la
-- policy RLS propre à `patient` (patient_account_read), déjà élargie à la
-- tutelle par la migration 0196 — pas besoin de la retoucher ici.
--
-- Les handlers list_treatment_plans/get_treatment_plan (api/src/treatment_plans.rs)
-- doivent aussi poser app.current_account_id, requis par la policy
-- guardianship_owner_select (migration 0025) sur account_guardianship.

DROP POLICY treatment_plan_patient_read ON treatment_plan;
CREATE POLICY treatment_plan_patient_read ON treatment_plan
  FOR SELECT
  TO nubia_app
  USING (
    patient_id IN (
      SELECT id FROM patient
      WHERE patient_account_id = nullif(current_setting('app.patient_account_id', true), '')::uuid
    )
    OR patient_id IN (
      SELECT id FROM patient
      WHERE patient_account_id IN (
        SELECT dependent_account_id FROM account_guardianship
        WHERE guardian_account_id = nullif(current_setting('app.patient_account_id', true), '')::uuid
          AND active = true
      )
    )
  );

COMMENT ON POLICY treatment_plan_patient_read ON treatment_plan IS
  'Lecture patient (compte propre) OU tuteur légal actif (account_guardianship) du dépendant rattaché au plan. #4596.';
