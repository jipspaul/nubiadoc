-- 0246_create_user_notification_preference.sql
-- Préférences de notification réglables pour TOUT app_user (pro, pharma, nurse,
-- patient inclus) : GET/PATCH /v1/me/notification-preferences.
-- Distinct de `notification_preference` (0024, patient_account_id NOT NULL,
-- clés RDV/messagerie/rappels/documents/paiement) : ce nouveau tableau est
-- keyed par app_user_id, catégories pro (rdv/messagerie/devis/stock/labo/
-- visites), défaut ON pour in-app et OFF pour email.
-- RLS user-scoped (app.current_user_id), même convention que `notification` (0053).
-- Issue : #6257

CREATE TABLE user_notification_preference (
  id                uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  app_user_id       uuid        NOT NULL REFERENCES app_user(id) ON DELETE CASCADE UNIQUE,
  inapp_rdv         boolean     NOT NULL DEFAULT true,
  inapp_messagerie  boolean     NOT NULL DEFAULT true,
  inapp_devis       boolean     NOT NULL DEFAULT true,
  inapp_stock       boolean     NOT NULL DEFAULT true,
  inapp_labo        boolean     NOT NULL DEFAULT true,
  inapp_visites     boolean     NOT NULL DEFAULT true,
  email_rdv         boolean     NOT NULL DEFAULT false,
  email_messagerie  boolean     NOT NULL DEFAULT false,
  email_devis       boolean     NOT NULL DEFAULT false,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now()
);

GRANT SELECT, INSERT, UPDATE ON user_notification_preference TO nubia_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON user_notification_preference TO nubia_seed;

ALTER TABLE user_notification_preference ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_notification_preference FORCE ROW LEVEL SECURITY;

CREATE POLICY user_notification_preference_owner_select ON user_notification_preference
  FOR SELECT TO nubia_app
  USING (app_user_id = nullif(current_setting('app.current_user_id', true), '')::uuid);

CREATE POLICY user_notification_preference_owner_insert ON user_notification_preference
  FOR INSERT TO nubia_app
  WITH CHECK (app_user_id = nullif(current_setting('app.current_user_id', true), '')::uuid);

CREATE POLICY user_notification_preference_owner_update ON user_notification_preference
  FOR UPDATE TO nubia_app
  USING  (app_user_id = nullif(current_setting('app.current_user_id', true), '')::uuid)
  WITH CHECK (app_user_id = nullif(current_setting('app.current_user_id', true), '')::uuid);

-- nubia_seed : accès complet (données de démo fictives, pas de GUC en seed).
CREATE POLICY user_notification_preference_seed ON user_notification_preference
  FOR ALL TO nubia_seed
  USING (true) WITH CHECK (true);

COMMENT ON TABLE user_notification_preference IS 'Préférences de notification réglables par app_user (pro/pharma/nurse/patient), catégorie x canal. RLS user-scoped (app.current_user_id). Réf. #6256.';
