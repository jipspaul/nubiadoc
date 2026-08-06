-- 0219_implant_passport_patient_read_guardian.sql
-- Étend implant_passport_patient_read (migration 0077) à la branche tutelle
-- (#4641, QA-20260806-1), symétrique à appointment_patient_read (0196),
-- prescription_patient_read (#4597) et document_patient_read (0218).
--
-- Le passeport implantaire d'un dépendant (patient_id rattaché au
-- patient_account_id du DÉPENDANT, jamais du tuteur) était invisible côté
-- tuteur : GET /v1/implant-passport ne retournait que les implants du
-- compte propre — cul-de-sac de suivi médical pour le tuteur légal actif.
--
-- La sous-requête account_guardianship reste soumise à sa propre policy
-- guardianship_owner_select (migration 0025), qui exige
-- app.current_account_id — api/src/implant_passport.rs::list_implant_passport
-- doit donc poser AUSSI app.current_account_id, en plus de
-- app.patient_account_id, comme déjà fait pour les RDV (0196) et les
-- documents (0218).

DROP POLICY implant_passport_patient_read ON implant_passport;
CREATE POLICY implant_passport_patient_read ON implant_passport
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

COMMENT ON POLICY implant_passport_patient_read ON implant_passport IS
  'Lecture patient (compte propre) OU tuteur légal actif (account_guardianship) du dépendant rattaché à l''implant. #4641.';
