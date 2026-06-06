-- 20_rls_roles.sql — RLS multi-tenant : clinical_note + rôles cabinet_membership.
-- Vérifie :
--   1. fail-closed : sans GUC → 0 note clinique visible.
--   2. même-tenant : cabinet X avec GUC = 1 note visible.
--   3. cross-tenant = 0 rows : cabinet Y ne voit AUCUNE note de cabinet X.
--   4. secrétaire cross-cabinet : secrétaire de cabinet Y = 0 note clinique de X.
--   5. admin même-cabinet : RLS isole par cabinet_id (pas par rôle) ;
--      l'admin de cabinet X avec GUC cabinet X voit tout le data du cabinet.
--      (Cloisonnement secretary/praticien = RBAC applicatif — docs/05 §2,
--       db/README §4 — pas au niveau DB.)
--   6. WITH CHECK : écriture cross-tenant dans clinical_note refusée.
-- Issue : #793
-- Exécuté par pg_prove sous nubia_app (NOSUPERUSER, NOBYPASSRLS).
BEGIN;
SELECT * FROM no_plan();

-- ===========================================================================
-- Fixtures — préfixe 79300000-... (propre à cette suite)
-- Cabinet X : praticien + secrétaire + admin + patient + 1 note clinique.
-- Cabinet Y : secrétaire (pour tests cross-tenant).
-- ===========================================================================

-- Cabinet X
SET LOCAL app.current_cabinet_id = '79300000-0000-0000-0000-000000000001';
INSERT INTO cabinet (id, raison_sociale)
  VALUES ('79300000-0000-0000-0000-000000000001', 'Cabinet RLS-X');

-- app_user du cabinet X (praticien, secrétaire, admin)
INSERT INTO app_user (id, email, password_hash, kind)
  VALUES ('79300000-0000-0000-0000-000000000011', 'practitioner.x@rls793.test', '$argon2id$fixture', 'pro');
INSERT INTO app_user (id, email, password_hash, kind)
  VALUES ('79300000-0000-0000-0000-000000000012', 'secretary.x@rls793.test',    '$argon2id$fixture', 'pro');
INSERT INTO app_user (id, email, password_hash, kind)
  VALUES ('79300000-0000-0000-0000-000000000013', 'admin.x@rls793.test',        '$argon2id$fixture', 'pro');

-- memberships dans cabinet X
INSERT INTO cabinet_membership (id, cabinet_id, user_id, role)
  VALUES ('79300000-0000-0000-0000-000000000021', '79300000-0000-0000-0000-000000000001', '79300000-0000-0000-0000-000000000011', 'practitioner');
INSERT INTO cabinet_membership (id, cabinet_id, user_id, role)
  VALUES ('79300000-0000-0000-0000-000000000022', '79300000-0000-0000-0000-000000000001', '79300000-0000-0000-0000-000000000012', 'secretary');
INSERT INTO cabinet_membership (id, cabinet_id, user_id, role)
  VALUES ('79300000-0000-0000-0000-000000000023', '79300000-0000-0000-0000-000000000001', '79300000-0000-0000-0000-000000000013', 'admin');

INSERT INTO practitioner (id, cabinet_id, user_id)
  VALUES ('79300000-0000-0000-0000-000000000041', '79300000-0000-0000-0000-000000000001', '79300000-0000-0000-0000-000000000011');

INSERT INTO patient (id, cabinet_id, first_name, last_name)
  VALUES ('79300000-0000-0000-0000-000000000031', '79300000-0000-0000-0000-000000000001', 'Claire', 'X');

INSERT INTO clinical_note (id, cabinet_id, patient_id, author_id, content_ciphertext, content_key_ref)
  VALUES ('79300000-0000-0000-0000-000000000051',
          '79300000-0000-0000-0000-000000000001',
          '79300000-0000-0000-0000-000000000031',
          '79300000-0000-0000-0000-000000000011',
          '\xDEADBEEF00', 'key_x_1');

-- Cabinet Y : secrétaire cross-cabinet (pour les tests d'isolation)
SET LOCAL app.current_cabinet_id = '79300000-0000-0000-0000-000000000002';
INSERT INTO cabinet (id, raison_sociale)
  VALUES ('79300000-0000-0000-0000-000000000002', 'Cabinet RLS-Y');
INSERT INTO app_user (id, email, password_hash, kind)
  VALUES ('79300000-0000-0000-0000-000000000014', 'secretary.y@rls793.test', '$argon2id$fixture', 'pro');
INSERT INTO cabinet_membership (id, cabinet_id, user_id, role)
  VALUES ('79300000-0000-0000-0000-000000000024', '79300000-0000-0000-0000-000000000002', '79300000-0000-0000-0000-000000000014', 'secretary');

-- ===========================================================================
-- 1. FAIL-CLOSED : sans GUC positionné → 0 note clinique visible.
-- ===========================================================================
RESET app.current_cabinet_id;
SELECT is(
  (SELECT count(*) FROM clinical_note
   WHERE cabinet_id = '79300000-0000-0000-0000-000000000001')::int, 0,
  '⭐ fail-closed clinical_note : aucune note visible sans app.current_cabinet_id');

-- ===========================================================================
-- 2. MÊME-TENANT : cabinet X avec GUC = 1 note visible.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '79300000-0000-0000-0000-000000000001';
SELECT is(
  (SELECT count(*) FROM clinical_note
   WHERE cabinet_id = '79300000-0000-0000-0000-000000000001')::int, 1,
  '⭐ même-tenant : 1 note clinique visible dans cabinet X (GUC = X)');

-- ===========================================================================
-- 3. CROSS-TENANT = 0 rows : cabinet Y ne voit AUCUNE note de cabinet X.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '79300000-0000-0000-0000-000000000002';
SELECT is(
  (SELECT count(*) FROM clinical_note
   WHERE cabinet_id = '79300000-0000-0000-0000-000000000001')::int, 0,
  '⭐ cross-tenant : contexte cabinet Y = 0 note clinique du cabinet X');

-- ===========================================================================
-- 4. SECRÉTAIRE cross-cabinet = 0 notes cliniques du cabinet X.
--    Même si l'utilisateur a le rôle 'secretary' dans cabinet Y, il ne peut
--    pas lire les notes cliniques de cabinet X.
--    (La RLS isole par cabinet_id, pas par rôle : le cloisonnement
--     secretary/praticien est applicatif — db/README §4.)
-- ===========================================================================
-- GUC cabinet Y = simule la secrétaire de Y tentant de lire les notes de X
SELECT is(
  (SELECT count(*) FROM clinical_note)::int, 0,
  '⭐ secrétaire cabinet Y (GUC=Y) = 0 note clinique (cabinet X invisible)');

-- ===========================================================================
-- 5. ADMIN MÊME-CABINET : RLS isole par cabinet_id, pas par rôle.
--    L'admin de cabinet X, avec GUC = cabinet X, voit tout le data du cabinet.
--    (Idem pour le praticien ou la secrétaire de cabinet X avec GUC = X ;
--     les 3 rôles DB sont confondus au niveau RLS — la distinction est RBAC
--     applicatif, cf. docs/05 §2 et db/README §4.)
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '79300000-0000-0000-0000-000000000001';
SELECT is(
  (SELECT count(*) FROM clinical_note)::int, 1,
  'admin cabinet X (GUC=X) : 1 note clinique visible — tout le cabinet');
SELECT is(
  (SELECT count(*) FROM patient
   WHERE cabinet_id = '79300000-0000-0000-0000-000000000001')::int, 1,
  'admin cabinet X (GUC=X) : 1 patient visible — tout le cabinet');
SELECT is(
  (SELECT count(*) FROM cabinet_membership
   WHERE cabinet_id = '79300000-0000-0000-0000-000000000001')::int, 3,
  'admin cabinet X (GUC=X) : 3 membres visible — tout le cabinet');

-- ===========================================================================
-- 6. WITH CHECK : secrétaire de cabinet Y ne peut pas écrire dans cabinet X.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '79300000-0000-0000-0000-000000000002';
SELECT throws_ok(
  $$ INSERT INTO clinical_note
       (cabinet_id, patient_id, author_id, content_ciphertext, content_key_ref)
     VALUES (
       '79300000-0000-0000-0000-000000000001',
       '79300000-0000-0000-0000-000000000031',
       '79300000-0000-0000-0000-000000000014',
       '\xFACEFEED00', 'key_pirate'
     ) $$,
  '42501', NULL,
  '⭐ secrétaire cabinet Y ne peut PAS insérer une note clinique dans cabinet X');

SELECT * FROM finish();
ROLLBACK;
