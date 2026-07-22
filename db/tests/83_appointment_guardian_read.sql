-- 83_appointment_guardian_read.sql
-- pgTAP : RLS appointment — branche tutelle de appointment_patient_read
-- (migration 0196, #4274/QA-20260722-2).
--   GR1. Tuteur (guardianship active) voit le RDV du dépendant.
--   GR2. Tuteur SANS guardianship active (révoquée) ne voit plus le RDV.
--   GR3. Un tiers (aucun lien) ne voit pas le RDV.
--   GR4. Le compte propre du RDV (own-account branch, inchangée) reste visible.
-- Exécuté par pg_prove sous nubia_app (NOSUPERUSER, NOBYPASSRLS).
-- Fixtures auto-contenues (BEGIN…ROLLBACK). Préfixe UUID 42740000.
-- Issue : #4274

BEGIN;
SELECT plan(4);

-- ===========================================================================
-- Fixtures : 1 cabinet, 1 praticien, 1 tuteur (Marc), 1 dépendant (Jade),
-- 1 tiers (Karim), 1 RDV rattaché au dépendant.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '42740000-0000-0000-0000-000000000001';

INSERT INTO cabinet (id, raison_sociale) VALUES
  ('42740000-0000-0000-0000-000000000001', 'Cabinet RLS-4274');

INSERT INTO app_user (id, email, password_hash, kind) VALUES
  ('42740000-0000-0000-0000-000000000010', 'prat.4274@nubia.test',  '$argon2id$fixture', 'pro'),
  ('42740000-0000-0000-0000-000000000011', 'marc.4274@nubia.test',  '$argon2id$fixture', 'patient'),
  ('42740000-0000-0000-0000-000000000012', 'karim.4274@nubia.test', '$argon2id$fixture', 'patient'),
  ('42740000-0000-0000-0000-000000000013', 'jade.4274@nubia.test',  '$argon2id$fixture', 'patient');

-- patient_account.app_user_id est NOT NULL (migration 0015) : même Jade
-- (dépendante mineure) a son propre compte plateforme — la tutelle vit dans
-- account_guardianship, pas dans une absence d'app_user.
INSERT INTO patient_account (id, app_user_id, first_name, last_name) VALUES
  ('42740000-0000-0000-0000-000000000020', '42740000-0000-0000-0000-000000000011', 'Marc',  'RLS4274'),
  ('42740000-0000-0000-0000-000000000021', '42740000-0000-0000-0000-000000000013', 'Jade',  'RLS4274'),
  ('42740000-0000-0000-0000-000000000022', '42740000-0000-0000-0000-000000000012', 'Karim', 'RLS4274');

INSERT INTO patient (id, cabinet_id, patient_account_id, first_name, last_name) VALUES
  ('42740000-0000-0000-0000-000000000030',
   '42740000-0000-0000-0000-000000000001',
   '42740000-0000-0000-0000-000000000021', 'Jade', 'RLS4274');

INSERT INTO practitioner (id, cabinet_id, user_id) VALUES
  ('42740000-0000-0000-0000-000000000040',
   '42740000-0000-0000-0000-000000000001',
   '42740000-0000-0000-0000-000000000010');

INSERT INTO appointment (id, cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status) VALUES
  ('42740000-0000-0000-0000-000000000050',
   '42740000-0000-0000-0000-000000000001',
   '42740000-0000-0000-0000-000000000030',
   '42740000-0000-0000-0000-000000000040',
   now() + interval '2 days',
   now() + interval '2 days' + interval '30 min',
   'requested');

INSERT INTO account_guardianship (id, guardian_account_id, dependent_account_id, relationship, active) VALUES
  ('42740000-0000-0000-0000-000000000060',
   '42740000-0000-0000-0000-000000000020',
   '42740000-0000-0000-0000-000000000021',
   'enfant', true);

-- Second patient/RDV pour Marc lui-même (branche compte propre, GR4) — créé
-- ici, sous contexte cabinet, avant tout SET de app.patient_account_id
-- (les policies d'INSERT sur patient/appointment n'autorisent pas
-- l'écriture depuis un contexte patient).
INSERT INTO patient (id, cabinet_id, patient_account_id, first_name, last_name) VALUES
  ('42740000-0000-0000-0000-000000000031',
   '42740000-0000-0000-0000-000000000001',
   '42740000-0000-0000-0000-000000000020', 'Marc', 'RLS4274');

INSERT INTO appointment (id, cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status) VALUES
  ('42740000-0000-0000-0000-000000000051',
   '42740000-0000-0000-0000-000000000001',
   '42740000-0000-0000-0000-000000000031',
   '42740000-0000-0000-0000-000000000040',
   now() + interval '3 days',
   now() + interval '3 days' + interval '30 min',
   'requested');

RESET app.current_cabinet_id;

-- ===========================================================================
-- GR1. Marc (tuteur, guardianship active) voit le RDV de Jade.
-- Les deux GUCs sont posés, comme le font désormais les handlers patient
-- (get/list/cancel/checkin, appointments.rs) : app.patient_account_id pour
-- l'ownership direct, app.current_account_id pour la lecture RLS de
-- account_guardianship (policy guardianship_owner_select, migration 0025).
-- ===========================================================================
SELECT set_config('app.patient_account_id', '42740000-0000-0000-0000-000000000020', true);
SELECT set_config('app.current_account_id', '42740000-0000-0000-0000-000000000020', true);

SELECT is(
  (SELECT count(*)::int FROM appointment WHERE id = '42740000-0000-0000-0000-000000000050'),
  1,
  '⭐ GR1 appointment_patient_read : le tuteur voit le RDV du dépendant (guardianship active)');

-- ===========================================================================
-- GR2. Guardianship révoquée → Marc ne voit plus le RDV.
-- ===========================================================================
UPDATE account_guardianship SET active = false
  WHERE id = '42740000-0000-0000-0000-000000000060';

SELECT is(
  (SELECT count(*)::int FROM appointment WHERE id = '42740000-0000-0000-0000-000000000050'),
  0,
  '⭐ GR2 appointment_patient_read : guardianship révoquée → RDV du dépendant invisible');

-- Réactive pour la suite des assertions.
UPDATE account_guardianship SET active = true
  WHERE id = '42740000-0000-0000-0000-000000000060';

-- ===========================================================================
-- GR3. Karim (aucun lien de tutelle) ne voit pas le RDV de Jade.
-- ===========================================================================
SELECT set_config('app.patient_account_id', '42740000-0000-0000-0000-000000000022', true);
SELECT set_config('app.current_account_id', '42740000-0000-0000-0000-000000000022', true);

SELECT is(
  (SELECT count(*)::int FROM appointment WHERE id = '42740000-0000-0000-0000-000000000050'),
  0,
  '⭐ GR3 appointment_patient_read : un tiers sans lien de tutelle ne voit pas le RDV');

-- ===========================================================================
-- GR4. Branche compte propre (inchangée) : Marc reste visible sur SES propres RDV.
-- ===========================================================================
SELECT set_config('app.patient_account_id', '42740000-0000-0000-0000-000000000020', true);
SELECT set_config('app.current_account_id', '42740000-0000-0000-0000-000000000020', true);

SELECT is(
  (SELECT count(*)::int FROM appointment WHERE id = '42740000-0000-0000-0000-000000000051'),
  1,
  '⭐ GR4 appointment_patient_read : Marc voit toujours son propre RDV (branche compte propre)');

SELECT * FROM finish();
ROLLBACK;
