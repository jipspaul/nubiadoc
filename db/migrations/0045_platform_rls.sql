-- 0045_platform_rls.sql
-- RLS plateforme sur app_user et patient_account.
--
-- Modèle : entités platform (pas de cabinet_id) isolées par leur propre identifiant :
--   app_user      → app.current_user_id
--   patient_account → app.current_account_id
--
-- Fail-closed : sans GUC positionné, current_setting(..., true) = NULL → 0 ligne visible.
-- SELECT/UPDATE/DELETE : borné à la propre ligne (identifiant = GUC).
-- INSERT : ouvert pour nubia_app (contrôle applicatif ; email UNIQUE suffit pour app_user).
-- nubia_seed : accès complet (données de démo fictives, pas de GUC en seed).
-- Issue : #718

-- ---------------------------------------------------------------------------
-- app_user
-- ---------------------------------------------------------------------------
ALTER TABLE app_user ENABLE ROW LEVEL SECURITY;
ALTER TABLE app_user FORCE ROW LEVEL SECURITY;

-- nubia_app : SELECT borné à sa propre ligne
CREATE POLICY user_self_select ON app_user
  FOR SELECT TO nubia_app
  USING (id = nullif(current_setting('app.current_user_id', true), '')::uuid);

-- nubia_app : INSERT libre (création de compte ; contrôle applicatif)
CREATE POLICY user_app_insert ON app_user
  FOR INSERT TO nubia_app
  WITH CHECK (true);

-- nubia_app : UPDATE/DELETE bornés à sa propre ligne
CREATE POLICY user_self_update ON app_user
  FOR UPDATE TO nubia_app
  USING (id = nullif(current_setting('app.current_user_id', true), '')::uuid)
  WITH CHECK (id = nullif(current_setting('app.current_user_id', true), '')::uuid);

CREATE POLICY user_self_delete ON app_user
  FOR DELETE TO nubia_app
  USING (id = nullif(current_setting('app.current_user_id', true), '')::uuid);

-- nubia_seed : accès complet (données de démo fictives)
CREATE POLICY user_seed ON app_user
  FOR ALL TO nubia_seed
  USING (true) WITH CHECK (true);

-- ---------------------------------------------------------------------------
-- patient_account
-- ---------------------------------------------------------------------------
ALTER TABLE patient_account ENABLE ROW LEVEL SECURITY;
ALTER TABLE patient_account FORCE ROW LEVEL SECURITY;

-- nubia_app : SELECT borné au compte courant
CREATE POLICY account_self_select ON patient_account
  FOR SELECT TO nubia_app
  USING (id = nullif(current_setting('app.current_account_id', true), '')::uuid);

-- nubia_app : INSERT libre (création de compte patient)
CREATE POLICY account_app_insert ON patient_account
  FOR INSERT TO nubia_app
  WITH CHECK (true);

-- nubia_app : UPDATE/DELETE bornés au compte courant
CREATE POLICY account_self_update ON patient_account
  FOR UPDATE TO nubia_app
  USING (id = nullif(current_setting('app.current_account_id', true), '')::uuid)
  WITH CHECK (id = nullif(current_setting('app.current_account_id', true), '')::uuid);

CREATE POLICY account_self_delete ON patient_account
  FOR DELETE TO nubia_app
  USING (id = nullif(current_setting('app.current_account_id', true), '')::uuid);

-- nubia_seed : accès complet (données de démo fictives)
CREATE POLICY account_seed ON patient_account
  FOR ALL TO nubia_seed
  USING (true) WITH CHECK (true);
