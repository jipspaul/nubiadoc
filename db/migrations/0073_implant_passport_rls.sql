-- 0073_implant_passport_rls.sql
-- RLS tenant_isolation + grants sur implant_passport.
-- Séparée de 0072 (DDL) pour audit explicite de la couverture RLS.
-- Issue : #699

ALTER TABLE implant_passport ENABLE ROW LEVEL SECURITY;
ALTER TABLE implant_passport FORCE ROW LEVEL SECURITY;

CREATE POLICY implant_passport_tenant_isolation ON implant_passport
    FOR ALL
    USING  (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid)
    WITH CHECK (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid);

GRANT SELECT, INSERT, UPDATE, DELETE ON implant_passport TO nubia_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON implant_passport TO nubia_seed;
