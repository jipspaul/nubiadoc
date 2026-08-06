-- 0221_prescription_patient_read_guardian.sql
-- Étend prescription_patient_read (migration 0109) à la branche tutelle
-- (#4597, QA-20260802-5), symétrique à appointment_patient_read (0196),
-- document_patient_read (0218) et implant_passport_patient_read (0219).
--
-- L'ordonnance d'un dépendant (patient_id rattaché au patient_account_id du
-- DÉPENDANT, jamais du tuteur) était invisible côté tuteur : absente de
-- GET /v1/account/prescriptions et POST /v1/account/prescriptions/{id}/order
-- (envoi pharmacie) renvoyait 404 — cul-de-sac clinique et légal, le mineur
-- n'ayant aucun login pour retirer lui-même son traitement.
--
-- La sous-requête account_guardianship reste soumise à sa propre policy
-- guardianship_owner_select (migration 0025), qui exige app.current_account_id
-- — api/src/prescriptions.rs::list_account_prescriptions doit donc poser
-- AUSSI app.current_account_id, en plus de app.patient_account_id, comme
-- déjà fait pour les RDV (0196), documents (0218) et passeports implantaires
-- (0219). api/src/pharmacy/orders.rs::create_account_order pose déjà les
-- deux GUC.

DROP POLICY prescription_patient_read ON prescription;
CREATE POLICY prescription_patient_read ON prescription
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

COMMENT ON POLICY prescription_patient_read ON prescription IS
  'Lecture patient (compte propre) OU tuteur légal actif (account_guardianship) du dépendant rattaché à l''ordonnance. #4597.';
