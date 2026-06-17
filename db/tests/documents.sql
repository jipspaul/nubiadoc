-- db/tests/documents.sql
-- Tests pgTAP : RLS document — isolation inter-compte patient.
-- Exécuté sous nubia_app (NOSUPERUSER, NOBYPASSRLS, FORCE RLS actif).
-- Issue : #2053 (BR3.c — tests auth + ownership scope + URL signée).

BEGIN;
SELECT plan(3);

-- Données de test : deux utilisateurs et leurs comptes patient
INSERT INTO app_user (id, email, password_hash, kind)
  VALUES
    ('a0000001-0000-0000-0000-000000000053'::uuid, 'rls-doc-a-2053@nubia.test', 'hash', 'patient'),
    ('b0000001-0000-0000-0000-000000000053'::uuid, 'rls-doc-b-2053@nubia.test', 'hash', 'patient');

INSERT INTO patient_account (id, app_user_id, first_name, last_name)
  VALUES
    ('a0000002-0000-0000-0000-000000000053'::uuid, 'a0000001-0000-0000-0000-000000000053'::uuid, 'Alice', 'RLS'),
    ('b0000002-0000-0000-0000-000000000053'::uuid, 'b0000001-0000-0000-0000-000000000053'::uuid, 'Bob',   'RLS');

-- Document plateforme appartenant au compte A (cabinet_id NULL, seul patient_account_id renseigné)
-- Requiert que app.patient_account_id = compte A pour passer le WITH CHECK de document_patient_owner.
SELECT set_config('app.patient_account_id', 'a0000002-0000-0000-0000-000000000053', true);

INSERT INTO document (id, patient_account_id, category, storage_key, filename, mime_type, sha256)
  VALUES (
    'd0000001-0000-0000-0000-000000000053'::uuid,
    'a0000002-0000-0000-0000-000000000053'::uuid,
    'ordonnance', 'rls-test-2053/doc-a', 'rls-a.pdf', 'application/pdf',
    repeat('a', 64)
  );

-- Test 1 : le compte A voit son propre document (document_patient_owner USING passe)
SELECT is(
    (SELECT count(*)::int FROM document WHERE id = 'd0000001-0000-0000-0000-000000000053'::uuid),
    1,
    'Patient A voit son propre document (RLS document_patient_owner passe)'
);

-- Test 2 : fail-closed — GUC vide → aucune ligne visible
SELECT set_config('app.patient_account_id', '', true);
SELECT is(
    (SELECT count(*)::int FROM document WHERE id = 'd0000001-0000-0000-0000-000000000053'::uuid),
    0,
    'Sans GUC app.patient_account_id → fail-closed (0 ligne)'
);

-- Test 3 : le compte B ne peut pas voir le document du compte A
SELECT set_config('app.patient_account_id', 'b0000002-0000-0000-0000-000000000053', true);
SELECT is(
    (SELECT count(*)::int FROM document WHERE id = 'd0000001-0000-0000-0000-000000000053'::uuid),
    0,
    'Patient B ne peut pas voir le document de patient A (RLS bloque le cross-account)'
);

SELECT * FROM finish();
ROLLBACK;
