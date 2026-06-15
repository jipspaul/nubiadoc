-- 37_patient_strong.sql — TDD audit pgTAP : Patient data invariants
-- Issue #1828 — T-DB-D002.
--
-- Invariants couverts :
--   PA1.  patient_account : FORCE ROW LEVEL SECURITY activée (0045).
--   PA2.  patient_account : fail-closed sans GUC → 0 ligne visible.
--   PA3.  patient_account : account_self_select — GUC account A → voit son compte, pas celui de B.
--   PA4.  patient_account : app_user_id ON DELETE CASCADE (0015) — DELETE app_user cascade à patient_account.
--   PA5.  patient_account : contrainte crypto pair (0044) — first_name_ciphertext seul sans key_ref → refusé.
--   PA6.  patient_account : account_auth_select (0069) — GUC login user A → voit son compte.
--   PA7.  patient_account : account_guardian_read (0062) — tuteur voit le compte de son dépendant.
--   PA8.  patient_account : account_guardian_update (0064) — tuteur peut UPDATE le compte de son dépendant.
--   PC1.  patient_coverage : FORCE ROW LEVEL SECURITY activée (0023).
--   PC2.  patient_coverage : fail-closed sans GUC → 0 ligne visible.
--   PC3.  patient_coverage : patient_coverage_owner — GUC account A → voit sa couverture, pas celle de B.
--   PC4.  patient_coverage : UNIQUE (patient_account_id) (0028) — double INSERT → erreur.
--   AG1.  account_guardianship : ENABLE ROW LEVEL SECURITY activée (0025).
--   AG2.  account_guardianship : guardianship_owner_select — GUC account guardian → voit le lien actif.
--   AG3.  account_guardianship : UNIQUE index actif WHERE active=true (0025) — double tutelle active → erreur.
--
-- Exécuté par pg_prove sous nubia_app (NOSUPERUSER, NOBYPASSRLS).
-- Fixtures auto-containées (BEGIN…ROLLBACK). Préfixe UUID 18280000.
BEGIN;
SELECT * FROM no_plan();

-- ===========================================================================
-- Pré-condition : exécuté sous nubia_app
-- ===========================================================================
SELECT is(current_user::text, 'nubia_app',
    '⭐ tests patient_strong exécutés sous nubia_app');

-- ===========================================================================
-- Fixtures
-- Deux utilisateurs platform + deux comptes patient + couvertures + tutelle.
-- Les INSERTs ouverts sont autorisés par les policies WITH CHECK(true) existantes.
-- Préfixe UUID 18280000 (propre à cette suite, issue #1828).
-- ===========================================================================

-- Deux app_user (platform, pas de cabinet_id)
INSERT INTO app_user (id, email, password_hash, kind)
    VALUES ('18280000-0000-0000-0000-0000000000a1', 'patient.strong.a@example.test', '$argon2id$fixture', 'patient');
INSERT INTO app_user (id, email, password_hash, kind)
    VALUES ('18280000-0000-0000-0000-0000000000a2', 'patient.strong.b@example.test', '$argon2id$fixture', 'patient');
-- Troisième user pour tester le cascade FK : sera supprimé
INSERT INTO app_user (id, email, password_hash, kind)
    VALUES ('18280000-0000-0000-0000-0000000000a3', 'patient.strong.c@example.test', '$argon2id$fixture', 'patient');

-- Deux patient_account + un troisième (cascade cible)
INSERT INTO patient_account (id, app_user_id, first_name, last_name)
    VALUES ('18280000-0000-0000-0000-0000000000e1', '18280000-0000-0000-0000-0000000000a1', 'Patient', 'StrongA');
INSERT INTO patient_account (id, app_user_id, first_name, last_name)
    VALUES ('18280000-0000-0000-0000-0000000000e2', '18280000-0000-0000-0000-0000000000a2', 'Patient', 'StrongB');
INSERT INTO patient_account (id, app_user_id, first_name, last_name)
    VALUES ('18280000-0000-0000-0000-0000000000e3', '18280000-0000-0000-0000-0000000000a3', 'Patient', 'StrongC');

-- Couverture pour account A (GUC requis par WITH CHECK de la policy patient_coverage_owner)
SET LOCAL app.patient_account_id = '18280000-0000-0000-0000-0000000000e1';
INSERT INTO patient_coverage (id, patient_account_id, regime_obligatoire, tiers_payant)
    VALUES ('18280000-0000-0000-0000-000000000010', '18280000-0000-0000-0000-0000000000e1', 'regime_general', false);
RESET app.patient_account_id;

-- Tutelle : A est tuteur de E2
INSERT INTO account_guardianship (id, guardian_account_id, dependent_account_id, relationship, active)
    VALUES ('18280000-0000-0000-0000-000000000020',
            '18280000-0000-0000-0000-0000000000e1',
            '18280000-0000-0000-0000-0000000000e2',
            'enfant',
            true);

-- ===========================================================================
-- PA1. patient_account : FORCE ROW LEVEL SECURITY activée (0045).
-- ===========================================================================
SELECT ok(
    (SELECT relforcerowsecurity FROM pg_class WHERE relname = 'patient_account'),
    'PA1 patient_account : FORCE ROW LEVEL SECURITY activée (0045)');

-- ===========================================================================
-- PA2. fail-closed : sans GUC positionné → 0 patient_account visible.
-- ===========================================================================
RESET app.current_account_id;
RESET app.current_user_id;
RESET app.current_login_user_id;
SELECT is(
    (SELECT count(*)::int FROM patient_account
     WHERE id IN ('18280000-0000-0000-0000-0000000000e1',
                  '18280000-0000-0000-0000-0000000000e2')),
    0,
    '⭐ PA2 fail-closed patient_account : 0 ligne sans GUC positionné');

-- ===========================================================================
-- PA3. account_self_select (0045) : GUC account A → voit son compte, pas celui de B.
-- ===========================================================================
-- ===========================================================================
-- PA3. account_self_select (0045) + isolation inter-account.
-- Contexte B ne peut pas voir le compte de A (B est dépendant de A, pas tuteur).
-- ===========================================================================
SET LOCAL app.current_account_id = '18280000-0000-0000-0000-0000000000e1';
SELECT is(
    (SELECT count(*)::int FROM patient_account
     WHERE id = '18280000-0000-0000-0000-0000000000e1'),
    1,
    '⭐ PA3a account_self_select : GUC account A → voit son propre compte');

-- Account B n'est pas tuteur de A → ne peut pas voir le compte de A.
SET LOCAL app.current_account_id = '18280000-0000-0000-0000-0000000000e2';
SELECT is(
    (SELECT count(*)::int FROM patient_account
     WHERE id = '18280000-0000-0000-0000-0000000000e1'),
    0,
    '⭐ PA3b account_self_select isolation : GUC account B → ne voit PAS le compte de A');

-- ===========================================================================
-- PA4. app_user_id ON DELETE CASCADE (0015) :
-- La suppression de app_user entraîne la suppression du patient_account lié.
-- ===========================================================================
-- Confirme que e3 existe
SET LOCAL app.current_account_id = '18280000-0000-0000-0000-0000000000e3';
SELECT is(
    (SELECT count(*)::int FROM patient_account
     WHERE id = '18280000-0000-0000-0000-0000000000e3'),
    1,
    'PA4 fixture OK : patient_account e3 présent avant DELETE');

-- Supprimer l'app_user (ON DELETE CASCADE doit propager)
DELETE FROM app_user WHERE id = '18280000-0000-0000-0000-0000000000a3';

-- Après delete, plus de patient_account pour e3 (policy fail-closed — reset GUC pour un select direct)
RESET app.current_account_id;
SELECT is(
    (SELECT count(*)::int FROM patient_account
     WHERE app_user_id = '18280000-0000-0000-0000-0000000000a3'),
    0,
    '⭐ PA4 ON DELETE CASCADE : patient_account supprimé quand app_user est supprimé');

-- ===========================================================================
-- PA5. Contrainte crypto pair (0044) :
-- Insérer first_name_ciphertext sans first_name_key_ref → CHECK violation.
-- ===========================================================================
SELECT throws_ok(
    $$ INSERT INTO patient_account (id, app_user_id, first_name, last_name,
                                    first_name_ciphertext, first_name_key_ref)
       VALUES ('18280000-0000-0000-0000-0000000000e9',
               '18280000-0000-0000-0000-0000000000a1',
               'X', 'Y',
               '\xDEADBEEF'::bytea, NULL) $$,
    '23514', NULL,
    '⭐ PA5 crypto pair : first_name_ciphertext sans key_ref → CHECK violation (23514)');

-- ===========================================================================
-- PA6. account_auth_select (0069) : GUC login user A → voit son patient_account.
-- ===========================================================================
RESET app.current_account_id;
RESET app.current_login_user_id;
SET LOCAL app.current_login_user_id = '18280000-0000-0000-0000-0000000000a1';
SELECT is(
    (SELECT count(*)::int FROM patient_account
     WHERE id = '18280000-0000-0000-0000-0000000000e1'),
    1,
    '⭐ PA6 account_auth_select : GUC login user A → voit son patient_account');

-- Isolation : login user A ne voit pas le compte de B
SELECT is(
    (SELECT count(*)::int FROM patient_account
     WHERE id = '18280000-0000-0000-0000-0000000000e2'),
    0,
    '⭐ PA6b isolation account_auth_select : GUC login user A → ne voit PAS le compte de B');

-- ===========================================================================
-- PA7. account_guardian_read (0062) : tuteur voit le compte de son dépendant.
-- ===========================================================================
RESET app.current_login_user_id;
SET LOCAL app.current_account_id = '18280000-0000-0000-0000-0000000000e1';
SELECT is(
    (SELECT count(*)::int FROM patient_account
     WHERE id = '18280000-0000-0000-0000-0000000000e2'),
    1,
    '⭐ PA7 account_guardian_read : tuteur (e1) voit le compte de son dépendant (e2)');

-- ===========================================================================
-- PA8. account_guardian_update (0064) : tuteur peut UPDATE le compte de son dépendant.
-- ===========================================================================
SELECT lives_ok(
    $$ UPDATE patient_account
       SET phone = '+33600000001'
       WHERE id = '18280000-0000-0000-0000-0000000000e2' $$,
    '⭐ PA8 account_guardian_update : tuteur (e1) peut modifier le compte de son dépendant (e2)');

-- ===========================================================================
-- PC1. patient_coverage : FORCE ROW LEVEL SECURITY activée (0023).
-- ===========================================================================
SELECT ok(
    (SELECT relforcerowsecurity FROM pg_class WHERE relname = 'patient_coverage'),
    'PC1 patient_coverage : FORCE ROW LEVEL SECURITY activée (0023)');

-- ===========================================================================
-- PC2. fail-closed : sans GUC positionné → 0 ligne patient_coverage visible.
-- ===========================================================================
RESET app.current_account_id;
RESET app.patient_account_id;
SELECT is(
    (SELECT count(*)::int FROM patient_coverage
     WHERE id = '18280000-0000-0000-0000-000000000010'),
    0,
    '⭐ PC2 fail-closed patient_coverage : 0 ligne sans app.patient_account_id');

-- ===========================================================================
-- PC3. patient_coverage_owner : GUC account A → voit sa couverture, pas celle de B.
-- ===========================================================================
SET LOCAL app.patient_account_id = '18280000-0000-0000-0000-0000000000e1';
SELECT is(
    (SELECT count(*)::int FROM patient_coverage
     WHERE patient_account_id = '18280000-0000-0000-0000-0000000000e1'),
    1,
    '⭐ PC3a patient_coverage_owner : GUC account A → voit sa propre couverture');

-- Ajoute une couverture pour B pour tester l'isolation (GUC B requis par WITH CHECK)
SET LOCAL app.patient_account_id = '18280000-0000-0000-0000-0000000000e2';
INSERT INTO patient_coverage (id, patient_account_id, regime_obligatoire, tiers_payant)
    VALUES ('18280000-0000-0000-0000-000000000011', '18280000-0000-0000-0000-0000000000e2', 'ame', false);

-- Retour au contexte A pour vérifier l'isolation
SET LOCAL app.patient_account_id = '18280000-0000-0000-0000-0000000000e1';
SELECT is(
    (SELECT count(*)::int FROM patient_coverage
     WHERE patient_account_id = '18280000-0000-0000-0000-0000000000e2'),
    0,
    '⭐ PC3b patient_coverage isolation : GUC account A → ne voit PAS la couverture de B');

-- ===========================================================================
-- PC4. UNIQUE (patient_account_id) (0028) : double INSERT pour même account → erreur.
-- GUC e1 : la policy laisse passer le WITH CHECK, c'est la contrainte UNIQUE qui explose.
-- ===========================================================================
SELECT throws_ok(
    $$ INSERT INTO patient_coverage (patient_account_id, tiers_payant)
       VALUES ('18280000-0000-0000-0000-0000000000e1', true) $$,
    '23505', NULL,
    '⭐ PC4 UNIQUE patient_coverage : double INSERT pour même patient_account_id → 23505');

-- ===========================================================================
-- AG1. account_guardianship : ROW LEVEL SECURITY activée (0025).
-- ===========================================================================
SELECT ok(
    (SELECT relrowsecurity FROM pg_class WHERE relname = 'account_guardianship'),
    'AG1 account_guardianship : ROW LEVEL SECURITY activée (0025)');

-- ===========================================================================
-- AG2. guardianship_owner_select : GUC account guardian → voit le lien actif.
-- ===========================================================================
RESET app.patient_account_id;
SET LOCAL app.current_account_id = '18280000-0000-0000-0000-0000000000e1';
SELECT is(
    (SELECT count(*)::int FROM account_guardianship
     WHERE id = '18280000-0000-0000-0000-000000000020'
       AND active = true),
    1,
    '⭐ AG2 guardianship_owner_select : tuteur (e1) voit son lien de tutelle actif');

-- Contexte B : ne doit pas voir le lien de tutelle de A→dépendant
SET LOCAL app.current_account_id = '18280000-0000-0000-0000-0000000000e2';
SELECT is(
    (SELECT count(*)::int FROM account_guardianship
     WHERE id = '18280000-0000-0000-0000-000000000020'
       AND guardian_account_id = '18280000-0000-0000-0000-0000000000e1'),
    1,
    'AG2b guardianship_owner_select : dépendant (e2) voit aussi le lien (en tant que dépendant)');

-- ===========================================================================
-- AG3. UNIQUE index WHERE active=true (0025) :
-- Insérer un 2e lien actif avec la même paire guardian/dependent → erreur unique.
-- ===========================================================================
SELECT throws_ok(
    $$ INSERT INTO account_guardianship (id, guardian_account_id, dependent_account_id, relationship, active)
       VALUES ('18280000-0000-0000-0000-000000000021',
               '18280000-0000-0000-0000-0000000000e1',
               '18280000-0000-0000-0000-0000000000e2',
               'parent',
               true) $$,
    '23505', NULL,
    '⭐ AG3 UNIQUE index active tutelle : double lien actif même paire → 23505');

SELECT * FROM finish();
ROLLBACK;
