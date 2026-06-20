-- db/tests/050_is_clinical_role.sql
-- pgTAP : tests unitaires de la fonction is_clinical_role(text).
-- Issue : #2235

BEGIN;
SELECT plan(6);
SELECT ok(is_clinical_role('practitioner'), 'practitioner is clinical');
SELECT ok(is_clinical_role('assistant_clinical'), 'assistant_clinical is clinical');
SELECT ok(NOT is_clinical_role('secretariat'), 'secretariat is NOT clinical');
SELECT ok(NOT is_clinical_role('admin'), 'admin is NOT clinical');
SELECT ok(NOT is_clinical_role(NULL), 'NULL is NOT clinical');
SELECT ok(NOT is_clinical_role('unknown_role'), 'unknown role is NOT clinical');
SELECT * FROM finish();
ROLLBACK;
