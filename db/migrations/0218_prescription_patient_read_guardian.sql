-- 0218_prescription_patient_read_guardian.sql
-- Étend prescription_patient_read (0109) à la branche tutelle
-- (#4597/QA-20260802-5), symétrique à appointment_patient_read (0196,
-- #4274) et treatment_plan_patient_read (#4596) : l'ordonnance SIGNÉE d'un
-- dépendant (patient_id rattaché au patient_account_id du DÉPENDANT) était
-- invisible au tuteur légal actif — GET /account/prescriptions l'omettait,
-- POST /account/prescriptions/:id/order → 404. Cul-de-sac clinique ET légal :
-- le mineur n'a aucun login, sans le tuteur l'ordonnance est inaccessible à
-- quiconque côté patient.
--
-- La policy ne scope aujourd'hui que app.patient_account_id = compte de
-- session courant, sans branche guardianship — la sous-requête
-- account_guardianship est elle-même soumise à sa policy
-- guardianship_owner_select (0025), qui exige app.current_account_id (GUC
-- différent de app.patient_account_id) : les handlers concernés
-- (list_account_prescriptions, create_account_order) doivent donc poser
-- AUSSI app.current_account_id = claims.account_id.

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
  'Lecture prescription (compte propre) OU tuteur légal actif (account_guardianship) du dépendant. #4597.';
