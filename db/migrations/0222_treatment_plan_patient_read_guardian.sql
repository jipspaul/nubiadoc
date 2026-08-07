-- 0222_treatment_plan_patient_read_guardian.sql
-- Étend treatment_plan_patient_read (migration 0038) à la branche tutelle
-- (#4596, QA-20260802-4), symétrique à appointment_patient_read (0196),
-- document_patient_read (0218) et implant_passport_patient_read (0219).
--
-- Le plan de traitement d'un dépendant (patient_id rattaché au
-- patient_account_id du DÉPENDANT, jamais du tuteur) était invisible côté
-- tuteur : GET /v1/treatment-plans l'omettait et GET /v1/treatment-plans/:id
-- renvoyait 404, alors que le cabinet le voit — cul-de-sac clinique, le
-- dépendant (enfant) n'ayant aucun login.
--
-- La sous-requête account_guardianship reste soumise à sa propre policy
-- guardianship_owner_select (migration 0025), qui exige
-- app.current_account_id — api/src/treatment_plans.rs::list_treatment_plans
-- et ::get_treatment_plan doivent donc poser AUSSI app.current_account_id,
-- en plus de app.patient_account_id, comme déjà fait pour les RDV (0196).

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
