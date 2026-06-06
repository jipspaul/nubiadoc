-- 04_rls_write.sql — RLS write policies : document + appointment cross-tenant.
-- Vérifie : WITH CHECK sur INSERT/UPDATE · fail-closed sans GUC · isolation cross-cabinet.
-- Exécuté par pg_prove sous nubia_app (NOSUPERUSER, NOBYPASSRLS).
-- Réf. : docs/12-api-reference §8 · db/SCHEMA.md §3 · Issue #855.
BEGIN;
SELECT * FROM no_plan();

-- ===========================================================================
-- Fixtures : deux cabinets A et B, chacun avec praticien + patient.
-- UUIDs figés (déterministes, hex uniquement).
-- ===========================================================================

-- Cabinet A + app_user A + practitioner A + patient A
SET LOCAL app.current_cabinet_id = 'a1000000-0000-0000-0000-000000000001';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('a1000000-0000-0000-0000-000000000001', 'Cabinet Write-A');
INSERT INTO app_user (id, email, password_hash, kind) VALUES
  ('a1000000-0000-0000-0000-a10000000001', 'prat.write.a@test.example', '$argon2id$fixture', 'pro');
INSERT INTO practitioner (id, cabinet_id, user_id) VALUES
  ('a1000000-0000-0000-0000-a10000000002', 'a1000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-a10000000001');
INSERT INTO patient (id, cabinet_id, first_name, last_name) VALUES
  ('a1000000-0000-0000-0000-000000000011', 'a1000000-0000-0000-0000-000000000001', 'Alice', 'Write');

-- Cabinet B + app_user B + practitioner B + patient B
SET LOCAL app.current_cabinet_id = 'b1000000-0000-0000-0000-000000000001';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('b1000000-0000-0000-0000-000000000001', 'Cabinet Write-B');
INSERT INTO app_user (id, email, password_hash, kind) VALUES
  ('b1000000-0000-0000-0000-b10000000001', 'prat.write.b@test.example', '$argon2id$fixture', 'pro');
INSERT INTO practitioner (id, cabinet_id, user_id) VALUES
  ('b1000000-0000-0000-0000-b10000000002', 'b1000000-0000-0000-0000-000000000001', 'b1000000-0000-0000-0000-b10000000001');
INSERT INTO patient (id, cabinet_id, first_name, last_name) VALUES
  ('b1000000-0000-0000-0000-000000000011', 'b1000000-0000-0000-0000-000000000001', 'Bob', 'Write');

-- app_user pour les patient_account (requis : app_user_id NOT NULL depuis 0015)
-- INSERT ouvert sur app_user (policy user_app_insert, pas de GUC requis)
RESET app.current_cabinet_id;
INSERT INTO app_user (id, email, password_hash, kind) VALUES
  ('a1000000-0000-0000-0000-000000000ac1', 'alice.write@patient.example', '$argon2id$fixture', 'patient');
INSERT INTO app_user (id, email, password_hash, kind) VALUES
  ('b1000000-0000-0000-0000-000000000bc1', 'bob.write@patient.example',   '$argon2id$fixture', 'patient');

-- patient_account PA et PB — INSERT ouvert (policy account_app_insert, pas de GUC requis)
INSERT INTO patient_account (id, app_user_id, first_name, last_name) VALUES
  ('a1000000-0000-0000-0000-000000000acc', 'a1000000-0000-0000-0000-000000000ac1', 'Alice', 'Account');
INSERT INTO patient_account (id, app_user_id, first_name, last_name) VALUES
  ('b1000000-0000-0000-0000-000000000bcc', 'b1000000-0000-0000-0000-000000000bc1', 'Bob',   'Account');

-- Lier les patients à leur compte (UPDATE sous le bon contexte cabinet)
SET LOCAL app.current_cabinet_id = 'a1000000-0000-0000-0000-000000000001';
UPDATE patient SET patient_account_id = 'a1000000-0000-0000-0000-000000000acc'
  WHERE id = 'a1000000-0000-0000-0000-000000000011';

SET LOCAL app.current_cabinet_id = 'b1000000-0000-0000-0000-000000000001';
UPDATE patient SET patient_account_id = 'b1000000-0000-0000-0000-000000000bcc'
  WHERE id = 'b1000000-0000-0000-0000-000000000011';

-- Document de référence pour patient A (inséré sous contexte A)
SET LOCAL app.current_cabinet_id = 'a1000000-0000-0000-0000-000000000001';
INSERT INTO document (id, cabinet_id, patient_id, category, storage_key, filename, mime_type, sha256) VALUES
  ('a1000000-0000-0000-0000-0000000000d1',
   'a1000000-0000-0000-0000-000000000001',
   'a1000000-0000-0000-0000-000000000011',
   'ordonnance', 'obj/a1/ord1', 'ordo1.pdf', 'application/pdf',
   'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');

-- ===========================================================================
-- 1. Cabinet A peut INSERT document dans son propre cabinet (tenant_isolation OK).
-- ===========================================================================
SET LOCAL app.current_cabinet_id = 'a1000000-0000-0000-0000-000000000001';
SELECT lives_ok(
  $$ INSERT INTO document (cabinet_id, patient_id, category, storage_key, filename, mime_type, sha256)
     VALUES ('a1000000-0000-0000-0000-000000000001',
             'a1000000-0000-0000-0000-000000000011',
             'radio', 'obj/a1/radio1', 'radio1.jpg', 'image/jpeg',
             'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb') $$,
  '⭐ cabinet A peut INSERT document dans son propre cabinet');

-- ===========================================================================
-- 2. Cabinet B ne peut PAS INSERT document pour cabinet A.
--    WITH CHECK : cabinet_id doit correspondre au GUC courant.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = 'b1000000-0000-0000-0000-000000000001';
SELECT throws_ok(
  $$ INSERT INTO document (cabinet_id, patient_id, category, storage_key, filename, mime_type, sha256)
     VALUES ('a1000000-0000-0000-0000-000000000001',
             'a1000000-0000-0000-0000-000000000011',
             'radio', 'obj/pirate/radio2', 'pirate.jpg', 'image/jpeg',
             'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc') $$,
  '42501', NULL,
  '⭐ WITH CHECK document : cabinet B ne peut PAS insérer dans cabinet A');

-- ===========================================================================
-- 3. Appointment booking cross-cabinet → échoue.
--    Contexte B, cible cabinet A : WITH CHECK refuse.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = 'b1000000-0000-0000-0000-000000000001';
SELECT throws_ok(
  $$ INSERT INTO appointment (cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status)
     VALUES ('a1000000-0000-0000-0000-000000000001',
             'a1000000-0000-0000-0000-000000000011',
             'a1000000-0000-0000-0000-a10000000002',
             '2026-09-01 10:00+00', '2026-09-01 10:30+00', 'confirmed') $$,
  '42501', NULL,
  '⭐ WITH CHECK appointment : booking cross-cabinet (B vers A) refusé');

-- ===========================================================================
-- 4. WITH CHECK : UPDATE cross-tenant sur document refusé.
--    Contexte A, tenter de déplacer le document vers cabinet B.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = 'a1000000-0000-0000-0000-000000000001';
SELECT throws_ok(
  $$ UPDATE document SET cabinet_id = 'b1000000-0000-0000-0000-000000000001'
     WHERE id = 'a1000000-0000-0000-0000-0000000000d1' $$,
  '42501', NULL,
  '⭐ WITH CHECK document : exfiltrer un document de A vers B via UPDATE refusé');

-- ===========================================================================
-- 5. Fail-closed : sans GUC positionné, INSERT document refuse.
--    Aucune policy ne matche (cabinet_id = NULL → WITH CHECK false).
-- ===========================================================================
RESET app.current_cabinet_id;
SELECT throws_ok(
  $$ INSERT INTO document (cabinet_id, patient_id, category, storage_key, filename, mime_type, sha256)
     VALUES ('a1000000-0000-0000-0000-000000000001',
             'a1000000-0000-0000-0000-000000000011',
             'radio', 'obj/noguc/doc', 'noguc.pdf', 'application/pdf',
             'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd') $$,
  '42501', NULL,
  '⭐ fail-closed : INSERT document sans GUC positionné refusé');

-- ===========================================================================
-- 6. Fail-closed : sans GUC positionné, INSERT appointment refuse.
-- ===========================================================================
RESET app.current_cabinet_id;
SELECT throws_ok(
  $$ INSERT INTO appointment (cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status)
     VALUES ('a1000000-0000-0000-0000-000000000001',
             'a1000000-0000-0000-0000-000000000011',
             'a1000000-0000-0000-0000-a10000000002',
             '2026-09-02 09:00+00', '2026-09-02 09:30+00', 'confirmed') $$,
  '42501', NULL,
  '⭐ fail-closed : INSERT appointment sans GUC positionné refusé');

-- ===========================================================================
-- 7. WITH CHECK : UPDATE appointment cross-cabinet refusé.
--    Contexte A, tenter de déplacer le RDV vers cabinet B.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = 'a1000000-0000-0000-0000-000000000001';
INSERT INTO appointment (id, cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status)
  VALUES ('a1000000-0000-0000-0000-0000000000e1',
          'a1000000-0000-0000-0000-000000000001',
          'a1000000-0000-0000-0000-000000000011',
          'a1000000-0000-0000-0000-a10000000002',
          '2026-09-03 10:00+00', '2026-09-03 10:30+00', 'confirmed');

SELECT throws_ok(
  $$ UPDATE appointment SET cabinet_id = 'b1000000-0000-0000-0000-000000000001'
     WHERE id = 'a1000000-0000-0000-0000-0000000000e1' $$,
  '42501', NULL,
  '⭐ WITH CHECK appointment : exfiltrer un RDV de A vers B via UPDATE refusé');

SELECT * FROM finish();
ROLLBACK;
