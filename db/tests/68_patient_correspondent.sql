-- 68_patient_correspondent.sql
-- pgTAP : patient_correspondent — multi-correspondants (#4099, migration 0176).
--   PC1. Un patient peut avoir 2 correspondants de rôles différents.
--   PC2. RLS patient-scoped : GUC account A → voit ses correspondants,
--        pas ceux de B (isolation cross-tenant).
--   PC3. Fail-closed : sans GUC app.patient_account_id → 0 ligne visible.
--   PC4. XOR provider_id/free_name : les deux renseignés en même temps refusé.
--   PC5. role hors énum refusé par le CHECK.
-- Exécuté par pg_prove sous nubia_app (NOSUPERUSER, NOBYPASSRLS).
-- Fixtures auto-contenues (BEGIN…ROLLBACK). Préfixe UUID 40990000.
-- Issue : #4099

BEGIN;
SELECT plan(5);

-- ===========================================================================
-- Fixtures : 2 comptes plateforme (A, B).
-- ===========================================================================
INSERT INTO app_user (id, email, password_hash, kind) VALUES
  ('40990000-0000-0000-0000-0000000000a1', 'correspondent.a@nubia.test', '$argon2id$fixture', 'patient');
INSERT INTO app_user (id, email, password_hash, kind) VALUES
  ('40990000-0000-0000-0000-0000000000a2', 'correspondent.b@nubia.test', '$argon2id$fixture', 'patient');

INSERT INTO patient_account (id, app_user_id, first_name, last_name) VALUES
  ('40990000-0000-0000-0000-0000000000e1', '40990000-0000-0000-0000-0000000000a1', 'Patient', 'CorrespondentA');
INSERT INTO patient_account (id, app_user_id, first_name, last_name) VALUES
  ('40990000-0000-0000-0000-0000000000e2', '40990000-0000-0000-0000-0000000000a2', 'Patient', 'CorrespondentB');

-- Provider réel (pour PC4 : évite une confusion avec une violation FK).
-- provider_cabinet_manage exige cabinet_id = GUC courant pour l'INSERT.
INSERT INTO app_user (id, email, password_hash, kind) VALUES
  ('40990000-0000-0000-0000-0000000000a3', 'correspondent.provider@nubia.test', '$argon2id$fixture', 'pro');
SET LOCAL app.current_cabinet_id = '40990000-0000-0000-0000-000000000c01';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('40990000-0000-0000-0000-000000000c01', 'Cabinet PatientCorrespondent-4099');
INSERT INTO provider (id, cabinet_id, user_id, display_name) VALUES
  ('40990000-0000-0000-0000-000000000f01', '40990000-0000-0000-0000-000000000c01',
   '40990000-0000-0000-0000-0000000000a3', 'Dr Fournisseur Test');
RESET app.current_cabinet_id;

-- ===========================================================================
-- PC1. Un patient peut avoir 2 correspondants de rôles différents.
-- ===========================================================================
SET LOCAL app.patient_account_id = '40990000-0000-0000-0000-0000000000e1';
INSERT INTO patient_correspondent (id, patient_account_id, role, free_name) VALUES
  ('40990000-0000-0000-0000-000000000010',
   '40990000-0000-0000-0000-0000000000e1', 'medecin_traitant', 'Dr Généraliste');
INSERT INTO patient_correspondent (id, patient_account_id, role, free_name) VALUES
  ('40990000-0000-0000-0000-000000000011',
   '40990000-0000-0000-0000-0000000000e1', 'specialiste', 'Dr Cardiologue');
SELECT is(
  (SELECT count(*)::int FROM patient_correspondent
   WHERE patient_account_id = '40990000-0000-0000-0000-0000000000e1'),
  2,
  'PC1 patient_correspondent : un patient peut avoir 2 correspondants de rôles différents');

-- ===========================================================================
-- PC2. RLS : GUC account B → ne voit PAS les correspondants de A.
-- ===========================================================================
SET LOCAL app.patient_account_id = '40990000-0000-0000-0000-0000000000e2';
SELECT is(
  (SELECT count(*)::int FROM patient_correspondent
   WHERE patient_account_id = '40990000-0000-0000-0000-0000000000e1'),
  0,
  '⭐ PC2 patient_correspondent_owner : compte B ne voit PAS les correspondants de A');

-- ===========================================================================
-- PC3. Fail-closed : sans GUC → 0 ligne visible.
-- ===========================================================================
RESET app.patient_account_id;
SELECT is(
  (SELECT count(*)::int FROM patient_correspondent),
  0,
  '⭐ PC3 patient_correspondent : fail-closed, 0 ligne visible sans GUC positionné');

-- ===========================================================================
-- PC4. XOR provider_id/free_name : les deux renseignés en même temps refusé.
-- ===========================================================================
SET LOCAL app.patient_account_id = '40990000-0000-0000-0000-0000000000e1';
SELECT throws_ok(
  $$ INSERT INTO patient_correspondent
       (patient_account_id, role, provider_id, free_name)
     VALUES ('40990000-0000-0000-0000-0000000000e1', 'adressage',
             '40990000-0000-0000-0000-000000000f01', 'Dr Les Deux') $$,
  '23514', NULL,
  'PC4 patient_correspondent_ref_xor_free : provider_id ET free_name refusé (23514)');

-- ===========================================================================
-- PC5. role hors énum refusé par le CHECK.
-- ===========================================================================
SELECT throws_ok(
  $$ INSERT INTO patient_correspondent
       (patient_account_id, role, free_name)
     VALUES ('40990000-0000-0000-0000-0000000000e1', 'kine', 'Dr Invalide') $$,
  '23514', NULL,
  'PC5 patient_correspondent_role_check : role hors énum refusé (23514)');

SELECT * FROM finish();
ROLLBACK;
