-- 0071_consultation_session_rls.sql
-- RLS tenant_isolation + grants sur consultation_session.
-- Séparée de 0070 (DDL) pour audit explicite de la couverture RLS.
-- Issue : #700

ALTER TABLE consultation_session ENABLE ROW LEVEL SECURITY;
ALTER TABLE consultation_session FORCE ROW LEVEL SECURITY;

CREATE POLICY consultation_session_tenant_isolation ON consultation_session
    FOR ALL
    USING  (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid)
    WITH CHECK (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid);

GRANT SELECT, INSERT, UPDATE, DELETE ON consultation_session TO nubia_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON consultation_session TO nubia_seed;
