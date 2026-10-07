-- 0315_quote_item_patient_read_policy.sql
-- Policy RLS READ-ONLY permissive (OR avec tenant_isolation cabinet) pour
-- GET /v1/billing/quotes (liste patient) : symétrique à quote_patient_read
-- (migration 0029), mais sur quote_item — nécessaire pour calculer
-- patient_share_cents (total - AMO - AMC) en liste, sans quoi la seule
-- policy existante (tenant_isolation, app.current_cabinet_id) bloque la
-- lecture quand le patient consulte des devis de plusieurs cabinets.
-- Issue : #8085

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
    )
  );
