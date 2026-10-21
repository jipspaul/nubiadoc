-- 0320_quote_item_patient_read_billed_to_account.sql
-- Reste à charge à 0 € en liste pour un devis de proche à charge (#8280) :
-- quote_patient_read (0029, étendue 0175) couvre déjà billed_to_account_id,
-- mais quote_item_patient_read (0315) ne filtre que sur
-- patient.patient_account_id — les quote_item d'un devis facturé au
-- responsable légal (patient_id = le proche à charge) restent invisibles au
-- tuteur, et patient_share_cents (calculé à partir des items visibles) tombe
-- à 0 en liste GET /v1/billing/quotes, alors que le détail GET
-- /v1/billing/quotes/:id (qui s'appuie sur quote_patient_read) reste juste.
-- Même pattern que 0175 et 0319 (#6797) : les items restent visibles au
-- bénéficiaire des soins (comportement inchangé) ET, si le devis associé a
-- billed_to_account_id renseigné, au compte facturé (le responsable légal).

DROP POLICY quote_item_patient_read ON quote_item;
CREATE POLICY quote_item_patient_read ON quote_item
  FOR SELECT
  TO nubia_app
  USING (
    quote_id IN (
      SELECT id FROM quote
      WHERE patient_id IN (
        SELECT id FROM patient
        WHERE patient_account_id = nullif(current_setting('app.patient_account_id', true), '')::uuid
      )
      OR billed_to_account_id = nullif(current_setting('app.patient_account_id', true), '')::uuid
    )
  );
