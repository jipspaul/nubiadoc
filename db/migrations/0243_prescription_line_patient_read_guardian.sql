-- 0243_prescription_line_patient_read_guardian.sql
-- Étend prescription_line_patient_read (migration 0108) à la branche tutelle,
-- symétrique à prescription_patient_read (0223), appointment_patient_read
-- (0196), document_patient_read (0218) et implant_passport_patient_read
-- (0219). Issue #6220 (QA-20260902-14).
--
-- Les lignes d'une ordonnance établie au nom d'un DÉPENDANT (patient_id
-- rattaché au patient_account_id du dépendant, jamais du tuteur) étaient
-- invisibles côté tuteur : GET /v1/account/orders/{id} renvoyait
-- toujours lines: [], alors que la commande elle-même (patient_display_name,
-- statut, timeline) traversait déjà la tutelle sans problème — la pharmacie
-- voyait bien la ligne via GET /v1/pharmacy/orders/{id}/items.
--
-- La sous-requête account_guardianship reste soumise à sa propre policy
-- guardianship_owner_select (migration 0025), qui exige app.current_account_id
-- — api/src/pharmacy/orders.rs::get_account_order doit donc poser AUSSI
-- app.current_account_id, en plus de app.patient_account_id, comme déjà fait
-- pour create_account_order.

DROP POLICY prescription_line_patient_read ON prescription_item;
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
    OR prescription_id IN (
      SELECT id FROM prescription
      WHERE patient_id IN (
        SELECT id FROM patient
        WHERE patient_account_id IN (
          SELECT dependent_account_id FROM account_guardianship
          WHERE guardian_account_id = nullif(current_setting('app.patient_account_id', true), '')::uuid
            AND active = true
        )
      )
    )
  );

COMMENT ON POLICY prescription_line_patient_read ON prescription_item IS
  'Lecture patient (compte propre) OU tuteur légal actif (account_guardianship) du dépendant rattaché à l''ordonnance. #6220.';
