-- 0047_refresh_mfa_rls.sql
-- RLS plateforme sur refresh_token et mfa_enrollment.
-- Modèle : entités user-scoped (app_user_id), isolées par app.current_user_id.
-- Fail-closed : nullif(current_setting('app.current_user_id', true), '') = NULL → 0 ligne.
-- INSERT ouvert (contrôle applicatif) — SELECT/UPDATE/DELETE bornés à l'utilisateur courant.
-- nubia_seed : accès complet (données de démo fictives, pas de GUC en seed).
-- Issue : #719

-- ---------------------------------------------------------------------------
-- refresh_token (table créée en 0016, sans RLS à l'époque)
-- ---------------------------------------------------------------------------
ALTER TABLE refresh_token ENABLE ROW LEVEL SECURITY;
ALTER TABLE refresh_token FORCE ROW LEVEL SECURITY;

CREATE POLICY token_user_select ON refresh_token
    FOR SELECT TO nubia_app
    USING (app_user_id = nullif(current_setting('app.current_user_id', true), '')::uuid);

CREATE POLICY token_user_insert ON refresh_token
    FOR INSERT TO nubia_app
    WITH CHECK (true);

CREATE POLICY token_user_update ON refresh_token
    FOR UPDATE TO nubia_app
    USING (app_user_id = nullif(current_setting('app.current_user_id', true), '')::uuid)
    WITH CHECK (app_user_id = nullif(current_setting('app.current_user_id', true), '')::uuid);

CREATE POLICY token_seed ON refresh_token
    FOR ALL TO nubia_seed
    USING (true) WITH CHECK (true);

-- refresh_token créé après la migration 0011 (GRANT ALL TABLES) : nubia_seed n'a pas le GRANT.
GRANT SELECT, INSERT, UPDATE, DELETE ON refresh_token TO nubia_seed;

-- ---------------------------------------------------------------------------
-- mfa_enrollment (table créée en 0046)
-- ---------------------------------------------------------------------------
ALTER TABLE mfa_enrollment ENABLE ROW LEVEL SECURITY;
ALTER TABLE mfa_enrollment FORCE ROW LEVEL SECURITY;

CREATE POLICY mfa_user_select ON mfa_enrollment
    FOR SELECT TO nubia_app
    USING (app_user_id = nullif(current_setting('app.current_user_id', true), '')::uuid);

CREATE POLICY mfa_user_insert ON mfa_enrollment
    FOR INSERT TO nubia_app
    WITH CHECK (true);

CREATE POLICY mfa_user_update ON mfa_enrollment
    FOR UPDATE TO nubia_app
    USING (app_user_id = nullif(current_setting('app.current_user_id', true), '')::uuid)
    WITH CHECK (app_user_id = nullif(current_setting('app.current_user_id', true), '')::uuid);

CREATE POLICY mfa_user_delete ON mfa_enrollment
    FOR DELETE TO nubia_app
    USING (app_user_id = nullif(current_setting('app.current_user_id', true), '')::uuid);

CREATE POLICY mfa_seed ON mfa_enrollment
    FOR ALL TO nubia_seed
    USING (true) WITH CHECK (true);
