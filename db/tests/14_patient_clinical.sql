-- 14_patient_clinical.sql — Tests RLS patient, medical_record, dental_chart, clinical_note.
-- Vérifie :
--   1. patient : fail-closed, isolation cross-tenant, INSERT OK même-tenant.
--   2. medical_record : fail-closed (sans GUC = rôle sans contexte → 0 rows),
--      même-tenant (praticien → rows visibles), cross-tenant (cabinet B → 0 rows),
--      WITH CHECK cross-tenant refusé.
--   3. dental_chart : idem (fail-closed, même-tenant, cross-tenant, WITH CHECK).
--   4. clinical_note soft-delete : note avec deleted_at IS NOT NULL non visible
--      avec le filtre applicatif standard (WHERE deleted_at IS NULL) ;
--      isolation cross-tenant confirmée.
--
-- NOTE sur le cloisonnement praticien/secrétaire (R.4127-72, docs/07 §4.1) :
--   Ce cloisonnement est RBAC applicatif au-dessus de la RLS (db/README §4,
--   SCHEMA.md §3). La RLS isole uniquement par cabinet_id. Les tests
--   "secretary → 0 rows" simulent un utilisateur de cabinet B tentant
--   d'accéder aux données de cabinet A — la RLS le bloque au niveau cabinet.
-- Issue : #777
-- Exécuté par pg_prove sous nubia_app (NOSUPERUSER, NOBYPASSRLS).
BEGIN;
SELECT * FROM no_plan();

-- ===========================================================================
-- Fixtures — préfixe 77700000-... (propre à cette suite)
-- Cabinet 777-A : praticien + patient + medical_record + dental_chart + 2 notes.
-- Cabinet 777-B : utilisateur + patient (pour tests cross-tenant).
-- ===========================================================================

-- Cabinet 777-A
SET LOCAL app.current_cabinet_id = '77700000-0000-0000-0000-000000000001';
INSERT INTO cabinet (id, raison_sociale)
  VALUES ('77700000-0000-0000-0000-000000000001', 'Cabinet 777-A');

INSERT INTO app_user (id, email, password_hash, kind)
  VALUES ('77700000-0000-0000-0000-0000000000a1',
          'practitioner.777@example.test', '$argon2id$fixture', 'pro');

INSERT INTO practitioner (id, cabinet_id, user_id)
  VALUES ('77700000-0000-0000-0000-0000000000b1',
          '77700000-0000-0000-0000-000000000001',
          '77700000-0000-0000-0000-0000000000a1');

INSERT INTO patient (id, cabinet_id, first_name, last_name)
  VALUES ('77700000-0000-0000-0000-0000000000c1',
          '77700000-0000-0000-0000-000000000001', 'Denise', '777A');

INSERT INTO medical_record (id, cabinet_id, patient_id)
  VALUES ('77700000-0000-0000-0000-0000000000d1',
          '77700000-0000-0000-0000-000000000001',
          '77700000-0000-0000-0000-0000000000c1');

INSERT INTO dental_chart (id, cabinet_id, patient_id)
  VALUES ('77700000-0000-0000-0000-0000000000e1',
          '77700000-0000-0000-0000-000000000001',
          '77700000-0000-0000-0000-0000000000c1');

-- clinical_note active (non soft-deleted)
INSERT INTO clinical_note (id, cabinet_id, patient_id, author_id,
                           content_ciphertext, content_key_ref)
  VALUES ('77700000-0000-0000-0000-0000000000f1',
          '77700000-0000-0000-0000-000000000001',
          '77700000-0000-0000-0000-0000000000c1',
          '77700000-0000-0000-0000-0000000000a1',
          '\xCAFEBABE01', 'key_777_active');

-- clinical_note soft-deleted (deleted_at IS NOT NULL)
INSERT INTO clinical_note (id, cabinet_id, patient_id, author_id,
                           content_ciphertext, content_key_ref, deleted_at)
  VALUES ('77700000-0000-0000-0000-0000000000f2',
          '77700000-0000-0000-0000-000000000001',
          '77700000-0000-0000-0000-0000000000c1',
          '77700000-0000-0000-0000-0000000000a1',
          '\xDEADBEEF02', 'key_777_deleted',
          '2026-01-15 10:00:00+00');

-- Cabinet 777-B (pour les tests cross-tenant — simule un utilisateur d'un autre cabinet)
SET LOCAL app.current_cabinet_id = '77700000-0000-0000-0000-000000000002';
INSERT INTO cabinet (id, raison_sociale)
  VALUES ('77700000-0000-0000-0000-000000000002', 'Cabinet 777-B');

INSERT INTO app_user (id, email, password_hash, kind)
  VALUES ('77700000-0000-0000-0000-0000000000a2',
          'secretary.777b@example.test', '$argon2id$fixture', 'pro');

INSERT INTO patient (id, cabinet_id, first_name, last_name)
  VALUES ('77700000-0000-0000-0000-0000000000c2',
          '77700000-0000-0000-0000-000000000002', 'Alain', '777B');

-- ===========================================================================
-- 1. PATIENT — isolation cabinet
-- ===========================================================================

-- 1.1 Fail-closed : sans GUC positionné → 0 patient visible.
RESET app.current_cabinet_id;
SELECT is(
  (SELECT count(*) FROM patient
   WHERE cabinet_id = '77700000-0000-0000-0000-000000000001')::int, 0,
  '⭐ fail-closed patient : aucun patient visible sans app.current_cabinet_id');

-- 1.2 Même-tenant (praticien cabinet A) : GUC = A → patient 777-A visible.
SET LOCAL app.current_cabinet_id = '77700000-0000-0000-0000-000000000001';
SELECT is(
  (SELECT count(*) FROM patient
   WHERE cabinet_id = '77700000-0000-0000-0000-000000000001')::int, 1,
  '⭐ même-tenant patient : praticien 777-A voit son patient');

-- 1.3 Cross-tenant : contexte cabinet B → 0 patient de cabinet A.
--     (Simule tout utilisateur de cabinet B — secrétaire ou praticien.)
SET LOCAL app.current_cabinet_id = '77700000-0000-0000-0000-000000000002';
SELECT is(
  (SELECT count(*) FROM patient
   WHERE cabinet_id = '77700000-0000-0000-0000-000000000001')::int, 0,
  '⭐ cross-tenant patient : cabinet B voit 0 patient de cabinet A');

-- 1.4 INSERT OK : même-tenant, insertion d'un patient dans le cabinet courant.
SET LOCAL app.current_cabinet_id = '77700000-0000-0000-0000-000000000001';
SELECT lives_ok(
  $$ INSERT INTO patient (id, cabinet_id, first_name, last_name)
     VALUES ('77700000-0000-0000-0000-0000000000c3',
             '77700000-0000-0000-0000-000000000001', 'Marc', '777A') $$,
  '⭐ INSERT patient OK dans le cabinet courant (même-tenant)');

-- ===========================================================================
-- 2. MEDICAL_RECORD — practitioner-only via RLS cabinet
--    Le cloisonnement praticien/secrétaire (R.4127-72) est RBAC applicatif
--    (db/README §4). La RLS isole par cabinet_id.
--    "secretary → 0 rows" = utilisateur sans contexte ou contexte cross-cabinet.
-- ===========================================================================

-- 2.1 Fail-closed : sans GUC → 0 medical_record visible.
--     Simule : appel sans contexte cabinet (ex. secrétaire sans GUC positionné).
RESET app.current_cabinet_id;
SELECT is(
  (SELECT count(*) FROM medical_record
   WHERE id = '77700000-0000-0000-0000-0000000000d1')::int, 0,
  '⭐ fail-closed medical_record : 0 rows sans app.current_cabinet_id (rôle sans contexte)');

-- 2.2 Même-tenant (praticien cabinet A) : GUC = cabinet A → dossier visible.
SET LOCAL app.current_cabinet_id = '77700000-0000-0000-0000-000000000001';
SELECT is(
  (SELECT count(*) FROM medical_record
   WHERE cabinet_id = '77700000-0000-0000-0000-000000000001')::int, 1,
  '⭐ même-tenant medical_record : praticien 777-A voit le dossier médical');

-- 2.3 Cross-tenant (utilisateur cabinet B, simule secrétaire cabinet B) : 0 dossier de A.
SET LOCAL app.current_cabinet_id = '77700000-0000-0000-0000-000000000002';
SELECT is(
  (SELECT count(*) FROM medical_record
   WHERE cabinet_id = '77700000-0000-0000-0000-000000000001')::int, 0,
  '⭐ cross-tenant medical_record : secrétaire cabinet B voit 0 dossier médical de cabinet A');

-- 2.4 WITH CHECK : INSERT cross-tenant refusé (contexte B, cible cabinet A).
SELECT throws_ok(
  $$ INSERT INTO medical_record (cabinet_id, patient_id)
     VALUES ('77700000-0000-0000-0000-000000000001',
             '77700000-0000-0000-0000-0000000000c1') $$,
  '42501', NULL,
  '⭐ WITH CHECK medical_record : INSERT cross-tenant refusé (cabinet B ne peut pas écrire dans A)');

-- ===========================================================================
-- 3. DENTAL_CHART — rôle + cross-tenant
-- ===========================================================================

-- 3.1 Fail-closed : sans GUC positionné → 0 dental_chart visible.
RESET app.current_cabinet_id;
SELECT is(
  (SELECT count(*) FROM dental_chart
   WHERE id = '77700000-0000-0000-0000-0000000000e1')::int, 0,
  '⭐ fail-closed dental_chart : 0 rows sans app.current_cabinet_id');

-- 3.2 Même-tenant (praticien cabinet A) : GUC = cabinet A → odontogramme visible.
SET LOCAL app.current_cabinet_id = '77700000-0000-0000-0000-000000000001';
SELECT is(
  (SELECT count(*) FROM dental_chart
   WHERE cabinet_id = '77700000-0000-0000-0000-000000000001')::int, 1,
  '⭐ même-tenant dental_chart : praticien 777-A voit l''odontogramme de son cabinet');

-- 3.3 Cross-tenant (praticien cabinet B) : GUC = cabinet B → 0 odontogramme de cabinet A.
SET LOCAL app.current_cabinet_id = '77700000-0000-0000-0000-000000000002';
SELECT is(
  (SELECT count(*) FROM dental_chart
   WHERE cabinet_id = '77700000-0000-0000-0000-000000000001')::int, 0,
  '⭐ cross-tenant dental_chart : praticien cabinet B voit 0 odontogramme de cabinet A');

-- 3.4 WITH CHECK : INSERT cross-tenant refusé (contexte B, cible cabinet A).
SELECT throws_ok(
  $$ INSERT INTO dental_chart (cabinet_id, patient_id)
     VALUES ('77700000-0000-0000-0000-000000000001',
             '77700000-0000-0000-0000-0000000000c1') $$,
  '42501', NULL,
  '⭐ WITH CHECK dental_chart : INSERT cross-tenant refusé (praticien B ne peut pas écrire dans A)');

-- ===========================================================================
-- 4. CLINICAL_NOTE — soft-delete
--    La RLS isole par cabinet_id (db/README §4). Le filtre soft-delete
--    (WHERE deleted_at IS NULL) est applicatif (db/README §2). Ce test
--    valide que la note soft-deletée n'est PAS retournée par ce filtre.
-- ===========================================================================

SET LOCAL app.current_cabinet_id = '77700000-0000-0000-0000-000000000001';

-- 4.1 La note active est visible avec le filtre standard (WHERE deleted_at IS NULL).
SELECT is(
  (SELECT count(*) FROM clinical_note
   WHERE cabinet_id = '77700000-0000-0000-0000-000000000001'
     AND deleted_at IS NULL)::int, 1,
  '⭐ soft-delete clinical_note : note active visible (deleted_at IS NULL)');

-- 4.2 La note soft-deletée n'est PAS visible avec le filtre standard.
SELECT is(
  (SELECT count(*) FROM clinical_note
   WHERE id = '77700000-0000-0000-0000-0000000000f2'
     AND deleted_at IS NULL)::int, 0,
  '⭐ soft-delete clinical_note : note avec deleted_at IS NOT NULL invisible (filtre applicatif)');

-- 4.3 La note soft-deletée existe en base (no hard delete — soft-delete préservé).
SELECT is(
  (SELECT count(*) FROM clinical_note
   WHERE cabinet_id = '77700000-0000-0000-0000-000000000001')::int, 2,
  '⭐ soft-delete clinical_note : 2 notes au total en base (active + soft-deleted)');

-- 4.4 Cross-tenant : GUC = cabinet B → 0 note clinique de cabinet A.
SET LOCAL app.current_cabinet_id = '77700000-0000-0000-0000-000000000002';
SELECT is(
  (SELECT count(*) FROM clinical_note
   WHERE cabinet_id = '77700000-0000-0000-0000-000000000001')::int, 0,
  '⭐ cross-tenant clinical_note : cabinet B voit 0 note clinique de cabinet A');

SELECT * FROM finish();
ROLLBACK;
