-- 04_rls_coverage.sql — Garde-fou automatisable (PROMPT, db/README §10, migrations §11).
-- Toute table portant cabinet_id DOIT avoir RLS activée + au moins une policy.
-- Si une table tenant est ajoutée sans policy, ce test échoue (et le merge doit échouer).
BEGIN;
SELECT * FROM no_plan();

-- Liste des tables avec cabinet_id dépourvues de RLS *ou* de policy : doit être VIDE.
SELECT is(
  (SELECT count(*)::int FROM (
     SELECT c.relname
     FROM pg_class c
     JOIN pg_namespace n ON n.oid = c.relnamespace AND n.nspname = 'public'
     JOIN pg_attribute a ON a.attrelid = c.oid AND a.attname = 'cabinet_id' AND NOT a.attisdropped
     WHERE c.relkind IN ('r','p')
       AND NOT c.relispartition          -- les partitions héritent de la RLS du parent
       AND ( c.relrowsecurity = false
             OR NOT EXISTS (SELECT 1 FROM pg_policies p
                             WHERE p.schemaname = 'public' AND p.tablename = c.relname) )
   ) missing),
  0,
  '⭐ garde-fou : aucune table avec cabinet_id sans RLS+policy');

-- Affiche les coupables s'il y en a (diagnostic).
SELECT diag('Tables tenant sans RLS/policy : ' || coalesce(string_agg(relname, ', '), '(aucune)'))
FROM (
  SELECT c.relname
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace AND n.nspname = 'public'
  JOIN pg_attribute a ON a.attrelid = c.oid AND a.attname = 'cabinet_id' AND NOT a.attisdropped
  WHERE c.relkind IN ('r','p')
    AND NOT c.relispartition
    AND ( c.relrowsecurity = false
          OR NOT EXISTS (SELECT 1 FROM pg_policies p
                          WHERE p.schemaname = 'public' AND p.tablename = c.relname) )
) z;

-- FORCE ROW LEVEL SECURITY effective sur un échantillon (s'applique même au owner)
SELECT ok( (SELECT relforcerowsecurity FROM pg_class WHERE relname='patient'),
  'patient : FORCE ROW LEVEL SECURITY');
SELECT ok( (SELECT relforcerowsecurity FROM pg_class WHERE relname='cabinet'),
  'cabinet : FORCE ROW LEVEL SECURITY');
SELECT ok( (SELECT relforcerowsecurity FROM pg_class WHERE relname='audit_log'),
  'audit_log : FORCE ROW LEVEL SECURITY');

-- La policy tenant_isolation existe sur les tables tenant standard
SELECT ok( EXISTS(SELECT 1 FROM pg_policies WHERE tablename='patient' AND policyname='tenant_isolation'),
  'patient : policy tenant_isolation présente');
SELECT ok( EXISTS(SELECT 1 FROM pg_policies WHERE tablename='clinical_note' AND policyname='tenant_isolation'),
  'clinical_note : policy tenant_isolation présente');

-- provider : entité plateforme -> lecture publique, PAS d'isolation cabinet stricte
SELECT ok( EXISTS(SELECT 1 FROM pg_policies WHERE tablename='provider' AND policyname='provider_public_read'),
  'provider : policy de lecture publique présente');

SELECT * FROM finish();
ROLLBACK;
