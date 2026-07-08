-- 0134_quote_patient_read_exclude_draft.sql
-- Corrige quote_patient_read (migration 0029) : un devis 'draft' est un
-- brouillon interne cabinet, jamais envoyé au patient (send_cabinet_quote,
-- api/src/billing.rs, exige status = 'draft' avant transition vers 'sent').
-- La policy autorisait le SELECT sans filtre de statut, exposant le
-- brouillon dans GET /v1/quotes et GET /v1/quotes/:id avant tout envoi.
-- Issue : #3487

DROP POLICY IF EXISTS quote_patient_read ON quote;

CREATE POLICY quote_patient_read ON quote
  FOR SELECT
  TO nubia_app
  USING (
    status <> 'draft'
    AND patient_id IN (
      SELECT id FROM patient
      WHERE patient_account_id = nullif(current_setting('app.patient_account_id', true), '')::uuid
    )
  );
