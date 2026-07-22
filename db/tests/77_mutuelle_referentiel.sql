-- 77_mutuelle_referentiel.sql
-- pgTAP : mutuelle_referentiel (#4127, migration 0187) + FK optionnelle
-- patient_coverage.amc_referentiel_id (migration 0188).
--   MR1. Lecture publique de mutuelle_referentiel sans GUC (catalogue non
--        tenant, comme ccam_act) : SELECT ne lève pas d'erreur.
--   MR2. Écriture refusée pour nubia_app (catalogue plateforme, écriture
--        réservée à nubia_seed — même pattern que ccam_act).
--   MR3. patient_coverage.amc_referentiel_id : FK vers un id inexistant
--        refusée (23503).
--   MR4. patient_coverage : mutuelle absente du référentiel reste
--        saisissable via amc (texte libre) SANS amc_referentiel_id, sans
--        erreur — comportement demandé explicitement par #4127.
-- Exécuté par pg_prove sous nubia_app (NOSUPERUSER, NOBYPASSRLS).
--
-- Pas de test de "recherche retourne les conditions d'une mutuelle" ici :
-- nubia_app n'a que SELECT sur mutuelle_referentiel (écriture réservée à
-- nubia_seed, cf. MR2) — la suite pgTAP tourne exclusivement sous
-- nubia_app (db/README §3), donc aucune fixture ne peut être insérée dans
-- la table depuis ce fichier. Même limite déjà documentée pour
-- ccam_act/ccam_act_bundle/ccam_act_incompatibility (aucun fichier de test
-- dédié dans ce dépôt) : la correction structurelle (index unique sur
-- nom, colonnes) est couverte ici ; la recherche sur données réelles
-- relèvera d'un test API une fois une route de lecture ajoutée.
--
-- Fixtures auto-contenues (BEGIN…ROLLBACK). Préfixe UUID 41270000.
-- Issue : #4127

BEGIN;
SELECT plan(4);

-- ===========================================================================
-- MR1. Lecture publique sans GUC : SELECT ne lève pas d'erreur.
-- ===========================================================================
SELECT lives_ok(
  $$ SELECT count(*) FROM mutuelle_referentiel $$,
  'MR1 mutuelle_referentiel : lecture publique sans GUC (catalogue non tenant)');

-- ===========================================================================
-- MR2. Écriture refusée pour nubia_app (42501 insufficient_privilege).
-- ===========================================================================
SELECT throws_ok(
  $$ INSERT INTO mutuelle_referentiel (nom) VALUES ('Mutuelle Test') $$,
  '42501', NULL,
  'MR2 mutuelle_referentiel : INSERT refusé pour nubia_app (42501)');

-- ===========================================================================
-- Fixtures : compte patient plateforme.
-- ===========================================================================
INSERT INTO app_user (id, email, password_hash, kind) VALUES
  ('41270000-0000-0000-0000-0000000000a1', 'mutuelle.ref.a@nubia.test', '$argon2id$fixture', 'patient');
INSERT INTO patient_account (id, app_user_id, first_name, last_name) VALUES
  ('41270000-0000-0000-0000-0000000000e1', '41270000-0000-0000-0000-0000000000a1', 'Patient', 'MutuelleRef');
SET LOCAL app.patient_account_id = '41270000-0000-0000-0000-0000000000e1';

-- ===========================================================================
-- MR3. FK vers un id de référentiel inexistant refusée (23503).
-- ===========================================================================
SELECT throws_ok(
  $$ INSERT INTO patient_coverage
       (patient_account_id, tiers_payant, amc_referentiel_id)
     VALUES ('41270000-0000-0000-0000-0000000000e1', false,
             '41270000-0000-0000-0000-000000000bad') $$,
  '23503', NULL,
  'MR3 patient_coverage_amc_referentiel_id_fkey : id inexistant refusé (23503)');

-- ===========================================================================
-- MR4. Mutuelle absente du référentiel : amc texte libre + amc_referentiel_id
-- NULL, aucune erreur (#4127 — comportement explicitement demandé).
-- ===========================================================================
SELECT lives_ok(
  $$ INSERT INTO patient_coverage
       (patient_account_id, tiers_payant, amc)
     VALUES ('41270000-0000-0000-0000-0000000000e1', false, 'Petite mutuelle locale inconnue') $$,
  'MR4 patient_coverage : mutuelle absente du référentiel saisissable en texte libre sans erreur');

SELECT * FROM finish();
ROLLBACK;
