-- 0048_consent_record_patient_rls.sql
-- Ajoute patient_account_id FK + evidence à consent_record (consentements RGPD patient portal).
-- Active RLS account-scoped (app.current_account_id) fail-closed.
-- La table existait en cabinet-scoped (0008), a été refactorisée en plateforme app_user (0017) ;
-- cette migration ajoute le lien patient_account côte-à-côte pour le portail RGPD.
-- Contrainte UNIQUE (patient_account_id, purpose) pour l'upsert PUT /v1/account/consents/{purpose}.
-- Issue : #720

ALTER TABLE consent_record
  ADD COLUMN IF NOT EXISTS patient_account_id UUID REFERENCES patient_account(id),
  ADD COLUMN IF NOT EXISTS evidence            JSONB NOT NULL DEFAULT '{}';

-- RLS account-scoped : fail-closed (GUC absent → 0 ligne visible/modifiable pour nubia_app).
ALTER TABLE consent_record ENABLE ROW LEVEL SECURITY;
ALTER TABLE consent_record FORCE ROW LEVEL SECURITY;

-- SELECT : borné au compte courant
CREATE POLICY consent_account_select ON consent_record
  FOR SELECT TO nubia_app
  USING (patient_account_id = nullif(current_setting('app.current_account_id', true), '')::uuid);

-- INSERT : ouvert (contrôle applicatif ; append-only par convention RGPD)
CREATE POLICY consent_account_insert ON consent_record
  FOR INSERT TO nubia_app
  WITH CHECK (true);

-- UPDATE : borné au compte courant (révocation, correction)
CREATE POLICY consent_account_update ON consent_record
  FOR UPDATE TO nubia_app
  USING  (patient_account_id = nullif(current_setting('app.current_account_id', true), '')::uuid)
  WITH CHECK (patient_account_id = nullif(current_setting('app.current_account_id', true), '')::uuid);

-- DELETE : borné au compte courant
CREATE POLICY consent_account_delete ON consent_record
  FOR DELETE TO nubia_app
  USING (patient_account_id = nullif(current_setting('app.current_account_id', true), '')::uuid);

-- nubia_seed : accès complet (données de démo fictives, pas de GUC en seed)
CREATE POLICY consent_seed ON consent_record
  FOR ALL TO nubia_seed
  USING (true) WITH CHECK (true);

-- Contrainte unicité (patient_account_id, purpose) — NULLs exclus (comportement SQL standard)
ALTER TABLE consent_record
  ADD CONSTRAINT consent_record_account_purpose_unique
  UNIQUE (patient_account_id, purpose);

COMMENT ON TABLE consent_record IS 'Consentements RGPD/CGU : app_user_id (CGU plateforme 0017) + patient_account_id (consentements patient RGPD 0048). RLS account-scoped. Réf. docs/12 §1.8, §3.';
