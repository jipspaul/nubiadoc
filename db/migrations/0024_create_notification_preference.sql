-- 0024_create_notification_preference.sql
-- Préférences de notification patient : opt-in par canal (email, SMS, push) et par type.
-- Entité plateforme liée à patient_account ; une ligne par compte (UNIQUE).
-- RLS patient-scoped (app.patient_account_id) : seul le titulaire peut lire/écrire sa ligne.
-- Issue : #238

CREATE TABLE notification_preference (
  id                 uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_account_id uuid        NOT NULL REFERENCES patient_account(id) UNIQUE,
  email_rdv          boolean     NOT NULL DEFAULT true,
  sms_rdv            boolean     NOT NULL DEFAULT true,
  push_rdv           boolean     NOT NULL DEFAULT true,
  email_messagerie   boolean     NOT NULL DEFAULT true,
  push_messagerie    boolean     NOT NULL DEFAULT true,
  email_rappels      boolean     NOT NULL DEFAULT true,
  push_rappels       boolean     NOT NULL DEFAULT true,
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now()
);

-- RLS patient-scoped : fail-closed (GUC absent → 0 ligne).
ALTER TABLE notification_preference ENABLE ROW LEVEL SECURITY;
ALTER TABLE notification_preference FORCE ROW LEVEL SECURITY;
CREATE POLICY notification_preference_owner
  ON notification_preference
  FOR ALL
  TO nubia_app
  USING      (patient_account_id = nullif(current_setting('app.patient_account_id', true), '')::uuid)
  WITH CHECK (patient_account_id = nullif(current_setting('app.patient_account_id', true), '')::uuid);

GRANT SELECT, INSERT, UPDATE, DELETE ON notification_preference TO nubia_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON notification_preference TO nubia_seed;
