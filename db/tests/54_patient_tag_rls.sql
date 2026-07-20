-- 54_patient_tag_rls.sql
-- pgTAP : RLS patient_tag — isolation cabinet (#4039).
-- Vérifie la policy tenant_isolation ajoutée par la migration 0158 :
--   PT1. Praticien du cabinet A voit l'étiquette de son cabinet
--   PT2. Praticien du cabinet B ne voit pas l'étiquette du cabinet A (cross-tenant)
--   PT3. Fail-closed : sans GUC app.current_cabinet_id positionné → 0 ligne visible
--   PT4. label vide (après trim) refusé par le CHECK patient_tag_label_not_blank
-- Exécuté par pg_prove sous nubia_app (NOSUPERUSER, NOBYPASSRLS).
-- Fixtures auto-contenues (BEGIN…ROLLBACK). Préfixe UUID 40390000.
-- Issue : #4039

BEGIN;
SELECT plan(4);

-- ===========================================================================
-- Fixtures : 2 cabinets (A, B), 1 praticien + 1 patient dans le cabinet A,
-- 1 étiquette posée sur ce patient.
-- ===========================================================================

SET LOCAL app.current_cabinet_id = '40390000-0000-0000-0000-000000000001';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('40390000-0000-0000-0000-000000000001', 'Cabinet PatientTag-4039-A');

SET LOCAL app.current_cabinet_id = '40390000-0000-0000-0000-000000000002';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('40390000-0000-0000-0000-000000000002', 'Cabinet PatientTag-4039-B');

SET LOCAL app.current_cabinet_id = '40390000-0000-0000-0000-000000000001';

INSERT INTO app_user (id, email, password_hash, kind) VALUES
  ('40390000-0000-0000-0000-000000000010', 'secretaire.4039@nubia.test', '$argon2id$fixture', 'pro');

INSERT INTO patient (id, cabinet_id, first_name, last_name) VALUES
  ('40390000-0000-0000-0000-000000000020',
   '40390000-0000-0000-0000-000000000001', 'Marc', 'Tag4039');

INSERT INTO patient_tag (id, cabinet_id, patient_id, label, color, created_by) VALUES
  ('40390000-0000-0000-0000-000000000030',
   '40390000-0000-0000-0000-000000000001',
   '40390000-0000-0000-0000-000000000020',
   'Paie en retard', '#F59E0B',
   '40390000-0000-0000-0000-000000000010');

-- ===========================================================================
-- PT1. Praticien du cabinet A voit l'étiquette de son cabinet.
-- ===========================================================================
SELECT is(
  (SELECT count(*)::int FROM patient_tag
   WHERE id = '40390000-0000-0000-0000-000000000030'),
  1,
  'PT1 patient_tag : cabinet A voit sa propre étiquette (tenant_isolation)');

-- ===========================================================================
-- PT2. Praticien du cabinet B ne voit pas l'étiquette du cabinet A (cross-tenant).
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '40390000-0000-0000-0000-000000000002';
SELECT is(
  (SELECT count(*)::int FROM patient_tag
   WHERE id = '40390000-0000-0000-0000-000000000030'),
  0,
  'PT2 patient_tag : cabinet B ne voit PAS l''étiquette du cabinet A (isolation cross-tenant)');

-- ===========================================================================
-- PT3. Fail-closed : sans GUC app.current_cabinet_id positionné → 0 ligne visible.
-- ===========================================================================
RESET app.current_cabinet_id;
SELECT is(
  (SELECT count(*)::int FROM patient_tag
   WHERE id = '40390000-0000-0000-0000-000000000030'),
  0,
  'PT3 patient_tag : fail-closed, 0 ligne visible sans GUC positionné');

-- ===========================================================================
-- PT4. label vide (après trim) refusé par le CHECK patient_tag_label_not_blank.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '40390000-0000-0000-0000-000000000001';
SELECT throws_ok(
  $$ INSERT INTO patient_tag (cabinet_id, patient_id, label, created_by)
     VALUES ('40390000-0000-0000-0000-000000000001',
             '40390000-0000-0000-0000-000000000020',
             '   ',
             '40390000-0000-0000-0000-000000000010') $$,
  '23514', NULL,
  'PT4 patient_tag_label_not_blank : label vide (après trim) refusé (23514)');

SELECT * FROM finish();
ROLLBACK;
