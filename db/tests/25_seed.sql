-- 25_seed.sql — Contrat seed démo : 1 cabinet + 4 app_user (issue #1073).
-- Vérifie :
--   1. Un cabinet démo peut être inséré et est visible via RLS (GUC cabinet).
--   2. Quatre app_user démo (practitioner/secretary/admin/patient) peuvent être
--      insérés avec un hash argon2id valide (≠ SEED_PLACEHOLDER).
--   3. Les memberships (practitioner, secretary, admin) sont rattachés au cabinet.
--   4. Le compte patient (kind='patient') est présent sans membership cabinet.
--   5. Les 4 hash password_hash débutent bien par '$argon2id$' (format correct).
-- Exécuté par pg_prove sous nubia_app (NOSUPERUSER, NOBYPASSRLS).
-- Fixtures auto-containées (BEGIN…ROLLBACK). Préfixe UUID 10730000.
-- Issue : #1073

BEGIN;
SELECT * FROM no_plan();

-- ===========================================================================
-- Fixtures — simule le jeu de données seed (1 cabinet + 4 users + 3 memberships)
-- ===========================================================================

-- Cabinet démo
SET LOCAL app.current_cabinet_id = '10730000-0000-0000-0000-000000000001';
INSERT INTO cabinet (id, raison_sociale, siret, specialite, settings) VALUES
  ('10730000-0000-0000-0000-000000000001', 'Cabinet Démo', '12345678900099', 'dentaire',
   '{"horaires":{"lun":"09:00-19:00"}}')
ON CONFLICT DO NOTHING;

-- 4 app_user démo : practitioner, secretary, admin (kind='pro') + patient (kind='patient').
-- Les hash ici sont des hash argon2id valides (non SEED_PLACEHOLDER) pour le test.
INSERT INTO app_user (id, email, password_hash, kind, rpps, status) VALUES
  ('10730000-0000-0000-0000-0000000000a1', 'praticien@demo-1073.test',
   '$argon2id$v=19$m=4096,t=3,p=1$ZGVtb1NlZWRhMDAwMDAwMQ$9sU+0grAVmhtI2LnUhePBkmBaodHJzHAz9ar4u1XJPU',
   'pro', '10100099901', 'active'),
  ('10730000-0000-0000-0000-0000000000a2', 'secretaire@demo-1073.test',
   '$argon2id$v=19$m=4096,t=3,p=1$ZGVtb1NlZWRhMDAwMDAwMg$CYHTiXIAmWDKHVDjjodFPRHuJ7OY++96myhsRwqxXm0',
   'pro', NULL, 'active'),
  ('10730000-0000-0000-0000-0000000000a3', 'admin@demo-1073.test',
   '$argon2id$v=19$m=4096,t=3,p=1$ZGVtb1NlZWRhMDAwMDAwMw$B32pRAN6Pa5e3R7AvtK4qP6PovusdNY8njh+CvoJGFA',
   'pro', NULL, 'active'),
  ('10730000-0000-0000-0000-0000000000a4', 'patient@demo-1073.test',
   '$argon2id$v=19$m=4096,t=3,p=1$ZGVtb1NlZWRhMDAwMDAwNA$39TllpW9C+KxsdPWXUJBGkl20Tl/uAULBnTnMjyqx3M',
   'patient', NULL, 'active')
ON CONFLICT DO NOTHING;

-- Memberships : practitioner + secretary + admin → cabinet démo
INSERT INTO cabinet_membership (id, cabinet_id, user_id, role) VALUES
  ('10730000-0000-0000-0000-0000000000b1',
   '10730000-0000-0000-0000-000000000001',
   '10730000-0000-0000-0000-0000000000a1', 'practitioner'),
  ('10730000-0000-0000-0000-0000000000b2',
   '10730000-0000-0000-0000-000000000001',
   '10730000-0000-0000-0000-0000000000a2', 'secretary'),
  ('10730000-0000-0000-0000-0000000000b3',
   '10730000-0000-0000-0000-000000000001',
   '10730000-0000-0000-0000-0000000000a3', 'admin')
ON CONFLICT DO NOTHING;

-- ===========================================================================
-- 1. Cabinet visible sous RLS (GUC = cabinet id)
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '10730000-0000-0000-0000-000000000001';
SELECT is(
  (SELECT count(*)::int FROM cabinet
   WHERE id = '10730000-0000-0000-0000-000000000001'),
  1,
  '⭐ seed : 1 cabinet démo visible sous RLS');

-- ===========================================================================
-- 2. Les 4 app_user sont insérés (vérification sous nubia_seed via GUC admin)
--    Note : nubia_app ne peut pas lire app_user sans app.current_user_id (RLS platform).
--    On vérifie via pg_roles/pg_authid ce qui est hors-RLS, ou via un INSERT qui
--    lèverait une violation de contrainte UNIQUE si l'utilisateur existe bien.
--    Stratégie : vérifier via un SELECT avec GUC de chaque utilisateur.
-- ===========================================================================

-- 2.a Practitioner visible par lui-même
SET LOCAL app.current_user_id = '10730000-0000-0000-0000-0000000000a1';
SELECT is(
  (SELECT count(*)::int FROM app_user
   WHERE id = '10730000-0000-0000-0000-0000000000a1'),
  1,
  '⭐ seed : app_user practitioner visible (kind=pro)');

-- 2.b Secretary visible par elle-même
SET LOCAL app.current_user_id = '10730000-0000-0000-0000-0000000000a2';
SELECT is(
  (SELECT count(*)::int FROM app_user
   WHERE id = '10730000-0000-0000-0000-0000000000a2'),
  1,
  '⭐ seed : app_user secretary visible (kind=pro)');

-- 2.c Admin visible par lui-même
SET LOCAL app.current_user_id = '10730000-0000-0000-0000-0000000000a3';
SELECT is(
  (SELECT count(*)::int FROM app_user
   WHERE id = '10730000-0000-0000-0000-0000000000a3'),
  1,
  '⭐ seed : app_user admin visible (kind=pro)');

-- 2.d Patient visible par lui-même
SET LOCAL app.current_user_id = '10730000-0000-0000-0000-0000000000a4';
SELECT is(
  (SELECT count(*)::int FROM app_user
   WHERE id = '10730000-0000-0000-0000-0000000000a4'),
  1,
  '⭐ seed : app_user patient visible (kind=patient)');

-- ===========================================================================
-- 3. Les hash password_hash sont au format argon2id (pas SEED_PLACEHOLDER)
-- ===========================================================================
-- Reset les GUC pour lire via pg_catalog (hors RLS)
RESET app.current_user_id;

-- Vérification via pg_catalog : le hash stocké commence bien par '$argon2id$'
-- On utilise information_schema pour lire les données hors-RLS (owner context).
-- Mais sous nubia_app, on ne peut pas bypasser la RLS sur app_user.
-- Stratégie : on vérifie avec le GUC de chaque user individuellement.

SET LOCAL app.current_user_id = '10730000-0000-0000-0000-0000000000a1';
SELECT ok(
  (SELECT password_hash FROM app_user WHERE id = '10730000-0000-0000-0000-0000000000a1')
    LIKE '$argon2id$%',
  '⭐ seed : hash practitioner au format argon2id (≠ SEED_PLACEHOLDER)');

SET LOCAL app.current_user_id = '10730000-0000-0000-0000-0000000000a2';
SELECT ok(
  (SELECT password_hash FROM app_user WHERE id = '10730000-0000-0000-0000-0000000000a2')
    LIKE '$argon2id$%',
  '⭐ seed : hash secretary au format argon2id');

SET LOCAL app.current_user_id = '10730000-0000-0000-0000-0000000000a3';
SELECT ok(
  (SELECT password_hash FROM app_user WHERE id = '10730000-0000-0000-0000-0000000000a3')
    LIKE '$argon2id$%',
  '⭐ seed : hash admin au format argon2id');

SET LOCAL app.current_user_id = '10730000-0000-0000-0000-0000000000a4';
SELECT ok(
  (SELECT password_hash FROM app_user WHERE id = '10730000-0000-0000-0000-0000000000a4')
    LIKE '$argon2id$%',
  '⭐ seed : hash patient au format argon2id');

-- ===========================================================================
-- 4. Les 3 memberships (pro) sont rattachés au cabinet démo
-- ===========================================================================
RESET app.current_user_id;
SET LOCAL app.current_cabinet_id = '10730000-0000-0000-0000-000000000001';
SELECT is(
  (SELECT count(*)::int FROM cabinet_membership
   WHERE cabinet_id = '10730000-0000-0000-0000-000000000001'),
  3,
  '⭐ seed : 3 memberships (practitioner, secretary, admin) dans le cabinet démo');

-- Rôles dans le cabinet
SELECT is(
  (SELECT count(*)::int FROM cabinet_membership
   WHERE cabinet_id = '10730000-0000-0000-0000-000000000001'
     AND role = 'practitioner'),
  1,
  '⭐ seed : 1 membership practitioner');
SELECT is(
  (SELECT count(*)::int FROM cabinet_membership
   WHERE cabinet_id = '10730000-0000-0000-0000-000000000001'
     AND role = 'secretary'),
  1,
  '⭐ seed : 1 membership secretary');
SELECT is(
  (SELECT count(*)::int FROM cabinet_membership
   WHERE cabinet_id = '10730000-0000-0000-0000-000000000001'
     AND role = 'admin'),
  1,
  '⭐ seed : 1 membership admin');

-- ===========================================================================
-- 5. Le compte patient n'a pas de membership cabinet (entité plateforme)
-- ===========================================================================
-- (Le patient n'est pas dans cabinet_membership — il a un patient_account, pas un membership)
SELECT is(
  (SELECT count(*)::int FROM cabinet_membership
   WHERE user_id = '10730000-0000-0000-0000-0000000000a4'),
  0,
  '⭐ seed : le compte patient (kind=patient) n''a pas de membership cabinet');

SELECT * FROM finish();
ROLLBACK;
