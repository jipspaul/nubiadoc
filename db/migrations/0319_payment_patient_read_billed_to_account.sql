-- 0319_payment_patient_read_billed_to_account.sql
-- Paiement pour un dépendant invisible chez le titulaire (#6797) :
-- quote_patient_read (0029, étendue 0175) couvre déjà billed_to_account_id,
-- mais payment_patient_read (0029) ne filtre que sur patient.patient_account_id
-- — un paiement fait par le titulaire pour le devis d'un dépendant (patient_id
-- = l'enfant) reste invisible dans GET /v1/payments malgré le 201 à la
-- création. Même pattern que 0175 : le paiement reste visible au bénéficiaire
-- des soins (comportement inchangé) ET, si le devis associé a
-- billed_to_account_id renseigné, au compte facturé (le responsable légal).

DROP POLICY payment_patient_read ON payment;
CREATE POLICY payment_patient_read ON payment
  FOR SELECT
  TO nubia_app
  USING (
    patient_id IN (
      SELECT id FROM patient
      WHERE patient_account_id = nullif(current_setting('app.patient_account_id', true), '')::uuid
    )
    OR quote_id IN (
      SELECT id FROM quote
      WHERE billed_to_account_id = nullif(current_setting('app.patient_account_id', true), '')::uuid
    )
  );
