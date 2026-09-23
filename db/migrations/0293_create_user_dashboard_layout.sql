-- 0293_create_user_dashboard_layout.sql
-- Préférence de mise en page du dashboard par utilisateur : GET/PUT
-- /v1/me/dashboard-layout. Liste ordonnée (jsonb) des identifiants de widgets
-- visibles, par app_user et par app (patient/pro/pharma/nurse) — un même
-- utilisateur peut avoir plusieurs apps (ex. pro + pharma), une ligne par app.
-- Même convention que `user_notification_preference` (0246) : RLS
-- user-scoped (app.current_user_id).
-- Issue : #7162

CREATE TABLE user_dashboard_layout (
  id            uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  app_user_id   uuid        NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  app           text        NOT NULL,
  layout        jsonb       NOT NULL DEFAULT '[]'::jsonb,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now(),
  UNIQUE (app_user_id, app)
);

GRANT SELECT, INSERT, UPDATE ON user_dashboard_layout TO nubia_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON user_dashboard_layout TO nubia_seed;

ALTER TABLE user_dashboard_layout ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_dashboard_layout FORCE ROW LEVEL SECURITY;

CREATE POLICY user_dashboard_layout_owner_select ON user_dashboard_layout
  FOR SELECT TO nubia_app
  USING (app_user_id = nullif(current_setting('app.current_user_id', true), '')::uuid);

CREATE POLICY user_dashboard_layout_owner_insert ON user_dashboard_layout
  FOR INSERT TO nubia_app
  WITH CHECK (app_user_id = nullif(current_setting('app.current_user_id', true), '')::uuid);

CREATE POLICY user_dashboard_layout_owner_update ON user_dashboard_layout
  FOR UPDATE TO nubia_app
  USING  (app_user_id = nullif(current_setting('app.current_user_id', true), '')::uuid)
  WITH CHECK (app_user_id = nullif(current_setting('app.current_user_id', true), '')::uuid);

-- nubia_seed : accès complet (données de démo fictives, pas de GUC en seed).
CREATE POLICY user_dashboard_layout_seed ON user_dashboard_layout
  FOR ALL TO nubia_seed
  USING (true) WITH CHECK (true);

COMMENT ON TABLE user_dashboard_layout IS 'Préférence de mise en page du dashboard par app_user et par app (liste ordonnée de widgets visibles). RLS user-scoped (app.current_user_id). Réf. #7162.';
