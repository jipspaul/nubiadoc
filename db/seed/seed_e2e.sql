-- =====================================================================
-- seed_e2e.sql — fixtures complémentaires pour les flows Playwright
-- (web-console/tests/flows/*). Données FICTIVES uniquement.
--
-- Complète db/seed/seed.sql (qui doit être appliqué AVANT) :
--   - comptes *.demo@nubia.test attendus par les flows (mot de passe
--     commun "NubiaDemo1!", hash argon2id figé ci-dessous)
--   - compte MFA (TOTP actif, secret RFC de test JBSWY3DPEHPK3PXP)
--   - compte reset (flux mot de passe oublié EP7)
--   - cabinet B « Annecy » + secrétariat pour les flows
--     multi-établissement (ED5)
--   - secrétaire multi-secrétariats (ES5 / EW52)
--
-- Idempotent : ON CONFLICT DO NOTHING partout. Rôle : nubia_seed.
-- =====================================================================
\set ON_ERROR_STOP on

-- Hash argon2id du mot de passe démo commun "NubiaDemo1!".
-- (généré par l'API /v1/auth/register, salt figé — comptes fictifs only)
-- $argon2id$v=19$m=19456,t=2,p=1$TblEa5Fu9Sp4xoK0NIeVMg$4p+yGjeHCuw1ciiKab85753f4YS8YUxh6ypBUNVNlqM

-- =====================================================================
-- Bloc 1 — comptes plateforme (app_user / patient_account, hors RLS cabinet)
-- =====================================================================
BEGIN;

-- ---------------------------------------------------------------------
-- 1. Comptes pro *.demo@nubia.test (mot de passe : NubiaDemo1!)
-- ---------------------------------------------------------------------
INSERT INTO app_user (id, email, password_hash, kind, status, first_name, last_name) VALUES
  -- Secrétaire du Secrétariat A (Lyon) — ED5 « secrétaire A »
  ('aee00000-0000-0000-0000-000000000003', 'secretaire-a.demo@nubia.test',
   '$argon2id$v=19$m=19456,t=2,p=1$TblEa5Fu9Sp4xoK0NIeVMg$4p+yGjeHCuw1ciiKab85753f4YS8YUxh6ypBUNVNlqM',
   'pro', 'active', 'Anna', 'Secrétaire'),
  -- Secrétaire du Secrétariat B (Lyon) — EX4 « secrétaire B »
  ('aee00000-0000-0000-0000-000000000004', 'secretaire-b.demo@nubia.test',
   '$argon2id$v=19$m=19456,t=2,p=1$TblEa5Fu9Sp4xoK0NIeVMg$4p+yGjeHCuw1ciiKab85753f4YS8YUxh6ypBUNVNlqM',
   'pro', 'active', 'Bérénice', 'Secrétaire'),
  -- Secrétaire multi-secrétariats (Lyon A + B) — ES5 / EW52
  ('aee00000-0000-0000-0000-000000000005', 'secretaire-multi.demo@nubia.test',
   '$argon2id$v=19$m=19456,t=2,p=1$TblEa5Fu9Sp4xoK0NIeVMg$4p+yGjeHCuw1ciiKab85753f4YS8YUxh6ypBUNVNlqM',
   'pro', 'active', 'Mona', 'Secrétaire'),
  -- Praticien multi-établissements (Lyon + Annecy) — ED5
  ('aee00000-0000-0000-0000-000000000006', 'praticien-multi.demo@nubia.test',
   '$argon2id$v=19$m=19456,t=2,p=1$TblEa5Fu9Sp4xoK0NIeVMg$4p+yGjeHCuw1ciiKab85753f4YS8YUxh6ypBUNVNlqM',
   'pro', 'active', 'Marius', 'Praticien'),
  -- Secrétaire du secrétariat Annecy (cabinet B) — ED5 « secrétaire B »
  ('aee00000-0000-0000-0000-000000000007', 'secretaire-annecy.demo@nubia.test',
   '$argon2id$v=19$m=19456,t=2,p=1$TblEa5Fu9Sp4xoK0NIeVMg$4p+yGjeHCuw1ciiKab85753f4YS8YUxh6ypBUNVNlqM',
   'pro', 'active', 'Alice', 'Secrétaire'),
  -- Manager Annecy (assignations provider↔secrétariat côté B) — ED5
  ('aee00000-0000-0000-0000-000000000008', 'manager-annecy.demo@nubia.test',
   '$argon2id$v=19$m=19456,t=2,p=1$TblEa5Fu9Sp4xoK0NIeVMg$4p+yGjeHCuw1ciiKab85753f4YS8YUxh6ypBUNVNlqM',
   'pro', 'active', 'Margaux', 'Manager')
ON CONFLICT (id) DO NOTHING;

-- Compte MFA (TOTP actif) — EP7. kind='pro' : le challenge TOTP au login
-- ne s'applique qu'aux comptes pro (api/src/auth/login.rs).
INSERT INTO app_user (id, email, password_hash, kind, status, totp_secret, totp_enabled, first_name, last_name) VALUES
  ('aee00000-0000-0000-0000-000000000001', 'patient.mfa@nubia.test',
   '$argon2id$v=19$m=19456,t=2,p=1$TblEa5Fu9Sp4xoK0NIeVMg$4p+yGjeHCuw1ciiKab85753f4YS8YUxh6ypBUNVNlqM',
   'pro', 'active', 'JBSWY3DPEHPK3PXP', true, 'Mathilde', 'Mfa')
ON CONFLICT (id) DO NOTHING;

-- Compte reset mot de passe — EP7.
INSERT INTO app_user (id, email, password_hash, kind, status, first_name, last_name) VALUES
  ('aee00000-0000-0000-0000-000000000002', 'patient.reset@nubia.test',
   '$argon2id$v=19$m=19456,t=2,p=1$TblEa5Fu9Sp4xoK0NIeVMg$4p+yGjeHCuw1ciiKab85753f4YS8YUxh6ypBUNVNlqM',
   'patient', 'active', 'Rémi', 'Reset')
ON CONFLICT (id) DO NOTHING;

INSERT INTO patient_account (id, app_user_id, first_name, last_name) VALUES
  ('bee00000-0000-0000-0000-000000000002', 'aee00000-0000-0000-0000-000000000002', 'Rémi', 'Reset')
ON CONFLICT (id) DO NOTHING;

COMMIT;

-- =====================================================================
-- Bloc 2 — données du cabinet Lyon (RLS : GUC tenant Lyon)
-- =====================================================================
BEGIN;
SET LOCAL app.current_cabinet_id = '11111111-1111-1111-1111-111111111111';

INSERT INTO cabinet_membership (id, cabinet_id, user_id, role, active) VALUES
  ('cee00000-0000-0000-0000-000000000001','11111111-1111-1111-1111-111111111111','aee00000-0000-0000-0000-000000000003','secretary', true),
  ('cee00000-0000-0000-0000-000000000002','11111111-1111-1111-1111-111111111111','aee00000-0000-0000-0000-000000000004','secretary', true),
  ('cee00000-0000-0000-0000-000000000003','11111111-1111-1111-1111-111111111111','aee00000-0000-0000-0000-000000000005','secretary', true),
  ('cee00000-0000-0000-0000-000000000004','11111111-1111-1111-1111-111111111111','aee00000-0000-0000-0000-000000000006','practitioner', true),
  ('cee00000-0000-0000-0000-000000000005','11111111-1111-1111-1111-111111111111','aee00000-0000-0000-0000-000000000001','practitioner', true)
ON CONFLICT (id) DO NOTHING;

INSERT INTO secretariat_membership (id, cabinet_id, secretariat_id, user_id, role, active) VALUES
  -- secretaire-a → Lyon A
  ('dee00000-0000-0000-0000-000000000001','11111111-1111-1111-1111-111111111111','19870000-0000-0000-0000-000000000001','aee00000-0000-0000-0000-000000000003','secretary', true),
  -- secretaire-b → Lyon B
  ('dee00000-0000-0000-0000-000000000002','11111111-1111-1111-1111-111111111111','19870000-0000-0000-0000-000000000002','aee00000-0000-0000-0000-000000000004','secretary', true),
  -- secretaire-multi → Lyon A + Lyon B (multi-contexte)
  ('dee00000-0000-0000-0000-000000000003','11111111-1111-1111-1111-111111111111','19870000-0000-0000-0000-000000000001','aee00000-0000-0000-0000-000000000005','secretary', true),
  ('dee00000-0000-0000-0000-000000000004','11111111-1111-1111-1111-111111111111','19870000-0000-0000-0000-000000000002','aee00000-0000-0000-0000-000000000005','secretary', true)
ON CONFLICT (id) DO NOTHING;

COMMIT;

-- =====================================================================
-- Bloc 3 — cabinet B « Annecy » (RLS : GUC tenant Annecy)
-- =====================================================================
BEGIN;
SET LOCAL app.current_cabinet_id = '22222222-2222-2222-2222-222222222222';

INSERT INTO cabinet (id, raison_sociale, specialite, settings) VALUES
  ('22222222-2222-2222-2222-222222222222', 'Cabinet Démo Annecy', 'dentaire', '{}')
ON CONFLICT (id) DO NOTHING;

INSERT INTO secretariat (id, cabinet_id, name) VALUES
  ('29870000-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222', 'Secrétariat Annecy')
ON CONFLICT (id) DO NOTHING;

INSERT INTO cabinet_membership (id, cabinet_id, user_id, role, active) VALUES
  ('cee00000-0000-0000-0000-000000000006','22222222-2222-2222-2222-222222222222','aee00000-0000-0000-0000-000000000006','practitioner', true),
  ('cee00000-0000-0000-0000-000000000007','22222222-2222-2222-2222-222222222222','aee00000-0000-0000-0000-000000000007','secretary', true),
  ('cee00000-0000-0000-0000-000000000008','22222222-2222-2222-2222-222222222222','aee00000-0000-0000-0000-000000000008','admin', true)
ON CONFLICT (id) DO NOTHING;

INSERT INTO secretariat_membership (id, cabinet_id, secretariat_id, user_id, role, active) VALUES
  -- secretaire-annecy → Annecy
  ('dee00000-0000-0000-0000-000000000005','22222222-2222-2222-2222-222222222222','29870000-0000-0000-0000-000000000001','aee00000-0000-0000-0000-000000000007','secretary', true),
  -- manager-annecy → Annecy (manager)
  ('dee00000-0000-0000-0000-000000000006','22222222-2222-2222-2222-222222222222','29870000-0000-0000-0000-000000000001','aee00000-0000-0000-0000-000000000008','manager', true)
ON CONFLICT (id) DO NOTHING;

COMMIT;

\echo '✓ seed e2e chargé (comptes *.demo@nubia.test, cabinet Annecy, MFA/reset)'
