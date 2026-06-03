-- 02_audit.sql — Audit append-only garanti par privilège (db/README §3, §7 ; docs/05 §6).
-- nubia_app : INSERT seul. Aucun UPDATE/DELETE. audit_log partitionné par mois.
BEGIN;
SELECT * FROM no_plan();

-- audit_log est bien une table partitionnée (RANGE occurred_at)
SELECT is(
  (SELECT relkind FROM pg_class WHERE relname = 'audit_log')::text, 'p',
  'audit_log est partitionnée (relkind = p)');

-- au moins une partition mensuelle existe
SELECT ok(
  (SELECT count(*) FROM pg_inherits i JOIN pg_class c ON c.oid = i.inhparent
    WHERE c.relname = 'audit_log') >= 1,
  'audit_log a au moins une partition');

-- nubia_app : INSERT autorisé dans son cabinet
SET LOCAL app.current_cabinet_id = 'a0000000-0000-0000-0000-000000000001';
SELECT lives_ok(
  $$ INSERT INTO audit_log (cabinet_id, action, entity)
     VALUES ('a0000000-0000-0000-0000-000000000001','login','app_user') $$,
  'nubia_app peut INSÉRER dans audit_log');

-- nubia_app : UPDATE refusé (pas le privilège -> append-only)
SELECT throws_ok(
  $$ UPDATE audit_log SET action = 'tamper' $$,
  '42501', NULL, 'nubia_app ne peut PAS UPDATE audit_log (append-only)');

-- nubia_app : DELETE refusé
SELECT throws_ok(
  $$ DELETE FROM audit_log $$,
  '42501', NULL, 'nubia_app ne peut PAS DELETE audit_log (append-only)');

-- la privilège INSERT existe, UPDATE/DELETE non (catalogue)
SELECT ok( has_table_privilege('nubia_app','audit_log','INSERT'),
  'nubia_app a INSERT sur audit_log');
SELECT ok( NOT has_table_privilege('nubia_app','audit_log','UPDATE'),
  'nubia_app n''a PAS UPDATE sur audit_log');
SELECT ok( NOT has_table_privilege('nubia_app','audit_log','DELETE'),
  'nubia_app n''a PAS DELETE sur audit_log');

SELECT * FROM finish();
ROLLBACK;
