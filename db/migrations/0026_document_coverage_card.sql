-- 0026_document_coverage_card.sql
-- Prépare la table document pour les cartes mutuelles patient (issue #244).
-- 1. cabinet_id devient nullable : les documents plateforme (patient_account)
--    n'appartiennent pas à un cabinet.
-- 2. Nouvelles colonnes : patient_account_id, side (recto|verso), scan_status.
-- 3. Policy RLS patient-scoped (combinée par OR avec tenant_isolation cabinet).

ALTER TABLE document ALTER COLUMN cabinet_id DROP NOT NULL;

ALTER TABLE document
  ADD COLUMN patient_account_id uuid REFERENCES patient_account(id),
  ADD COLUMN side               text CHECK (side IN ('recto', 'verso')),
  ADD COLUMN scan_status        text NOT NULL DEFAULT 'pending';

-- Policy permissive patient : un patient accède à ses propres documents.
-- Se combine par OR avec la policy tenant_isolation existante (cabinet-scoped).
-- fail-closed : GUC absent ou vide → 0 ligne (nullif renvoie NULL → comparaison NULL ≠ uuid).
CREATE POLICY document_patient_owner ON document
  FOR ALL
  TO nubia_app
  USING (
    patient_account_id = nullif(current_setting('app.patient_account_id', true), '')::uuid
  )
  WITH CHECK (
    patient_account_id = nullif(current_setting('app.patient_account_id', true), '')::uuid
  );
