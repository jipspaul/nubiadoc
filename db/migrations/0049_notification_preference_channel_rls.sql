-- 0049_notification_preference_channel_rls.sql
-- Ajoute colonnes EAV (channel / enabled / type) à notification_preference.
-- Migre la RLS : ancien GUC app.patient_account_id → app.current_account_id (convention 0045+).
-- Remplace la contrainte UNIQUE(patient_account_id) mono-ligne par
-- UNIQUE(patient_account_id, channel, type) compatible avec le modèle EAV.
-- Ajoute une policy nubia_seed (manquante en 0024) pour cohérence avec 0045+.
-- Issue : #720

-- 1. Supprimer l'ancienne policy (GUC app.patient_account_id → remplacée ci-dessous)
DROP POLICY IF EXISTS notification_preference_owner ON notification_preference;

-- 2. Supprimer la contrainte UNIQUE mono-ligne incompatible avec le modèle EAV
ALTER TABLE notification_preference
  DROP CONSTRAINT IF EXISTS notification_preference_patient_account_id_key;

-- 3. Colonnes EAV : channel, enabled, type
ALTER TABLE notification_preference
  ADD COLUMN IF NOT EXISTS channel TEXT  CHECK (channel IN ('push', 'email', 'sms')),
  ADD COLUMN IF NOT EXISTS enabled BOOLEAN NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS type    TEXT;

-- 4. Unicité par (patient_account_id, channel, type) pour l'upsert EAV
--    NULLs dans channel/type : comportement SQL standard (NULLs non-égaux → pas de conflit)
ALTER TABLE notification_preference
  ADD CONSTRAINT notification_preference_account_channel_type_unique
  UNIQUE (patient_account_id, channel, type);

-- 5. Nouvelles policies RLS (app.current_account_id = convention plateforme depuis 0045)
CREATE POLICY notif_pref_account_select ON notification_preference
  FOR SELECT TO nubia_app
  USING (patient_account_id = nullif(current_setting('app.current_account_id', true), '')::uuid);

CREATE POLICY notif_pref_account_insert ON notification_preference
  FOR INSERT TO nubia_app
  WITH CHECK (patient_account_id = nullif(current_setting('app.current_account_id', true), '')::uuid);

CREATE POLICY notif_pref_account_update ON notification_preference
  FOR UPDATE TO nubia_app
  USING  (patient_account_id = nullif(current_setting('app.current_account_id', true), '')::uuid)
  WITH CHECK (patient_account_id = nullif(current_setting('app.current_account_id', true), '')::uuid);

CREATE POLICY notif_pref_account_delete ON notification_preference
  FOR DELETE TO nubia_app
  USING (patient_account_id = nullif(current_setting('app.current_account_id', true), '')::uuid);

-- nubia_seed : accès complet (données de démo fictives, absent en 0024)
CREATE POLICY notif_pref_seed ON notification_preference
  FOR ALL TO nubia_seed
  USING (true) WITH CHECK (true);

COMMENT ON TABLE notification_preference IS 'Préférences de notification patient par canal (push/email/sms) et type (EAV). RLS account-scoped (app.current_account_id). Réf. docs/12 §6.';
