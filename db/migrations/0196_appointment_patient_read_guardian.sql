-- 0196_appointment_patient_read_guardian.sql
-- Étend appointment_patient_read (migration 0029) à la branche tutelle
-- (#4274/QA-20260722-2) : un RDV pris `on_behalf_of` un dépendant
-- (patient_id rattaché au patient_account_id du DÉPENDANT, pas du tuteur —
-- appointments.rs::create_appointment) était invisible/ingérable côté
-- tuteur : GET détail 404, absent de GET /appointments, cancel/checkin 404.
-- Le RDV existait bien côté cabinet, orphelin côté patient — cul-de-sac.
--
-- La policy ne scope aujourd'hui que app.patient_account_id = compte de
-- session courant, sans branche guardianship — contrairement à
-- account_guardian_read (migration 0062) qui a déjà cette branche pour
-- patient_account. Applique la même logique ici, symétriquement.
--
-- Tous les handlers patient (get/list/cancel/checkin, appointments.rs)
-- posent app.patient_account_id = claims.account_id (le compte du TUTEUR
-- en session, jamais celui du dépendant) puis s'appuient entièrement sur
-- cette policy pour l'ownership check (simple SELECT ... WHERE id = $1,
-- aucun prédicat patient_id explicite côté application).
--
-- PIÈGE (découvert en vérifiant contre Postgres réel, pas juste en lisant le
-- schéma) : élargir SEULEMENT appointment_patient_read ne suffit PAS. Sa
-- sous-requête `SELECT id FROM patient WHERE ...` reste elle-même filtrée
-- par la policy RLS PROPRE à `patient` (patient_account_read, migration
-- 0029), qui ne connaît que app.patient_account_id = compte propre — donc
-- la ligne `patient` du DÉPENDANT restait invisible même après le premier
-- élargissement (0 lignes malgré une policy appointment_patient_read censée
-- matcher). Il faut élargir `patient_account_read` elle-même en miroir, sans
-- quoi la RLS de `patient` bloque la ligne avant même que le prédicat
-- explicite d'appointment_patient_read ne s'applique.
--
-- Et la sous-requête account_guardianship (dans les deux policies) est elle-
-- même soumise à sa policy `guardianship_owner_select` (migration 0025),
-- qui exige app.current_account_id — GUC DIFFÉRENT de app.patient_account_id.
-- Les 4 handlers (get/list/cancel/checkin) ont donc dû être étendus pour
-- poser AUSSI app.current_account_id = claims.account_id, exactement comme
-- create_appointment le fait déjà pour vérifier la tutelle à la création
-- (`on_behalf_of`).

-- 1. Fondation : patient_account_read (migration 0029) — tout le reste
--    (appointment/quote/payment/conversation/message) chaîne dessus via des
--    sous-requêtes qui restent soumises à CETTE policy.
DROP POLICY patient_account_read ON patient;
CREATE POLICY patient_account_read ON patient
  FOR SELECT
  TO nubia_app
  USING (
    patient_account_id = nullif(current_setting('app.patient_account_id', true), '')::uuid
    OR patient_account_id IN (
      SELECT dependent_account_id FROM account_guardianship
      WHERE guardian_account_id = nullif(current_setting('app.patient_account_id', true), '')::uuid
        AND active = true
    )
  );

COMMENT ON POLICY patient_account_read ON patient IS
  'Lecture patient (compte propre) OU tuteur légal actif (account_guardianship) du dépendant. #4274.';

-- 2. appointment_patient_read : même branche tutelle, symétrique.
DROP POLICY appointment_patient_read ON appointment;
CREATE POLICY appointment_patient_read ON appointment
  FOR SELECT
  TO nubia_app
  USING (
    patient_id IN (
      SELECT id FROM patient
      WHERE patient_account_id = nullif(current_setting('app.patient_account_id', true), '')::uuid
    )
    OR patient_id IN (
      SELECT id FROM patient
      WHERE patient_account_id IN (
        SELECT dependent_account_id FROM account_guardianship
        WHERE guardian_account_id = nullif(current_setting('app.patient_account_id', true), '')::uuid
          AND active = true
      )
    )
  );

COMMENT ON POLICY appointment_patient_read ON appointment IS
  'Lecture patient (compte propre) OU tuteur légal actif (account_guardianship) du dépendant rattaché au RDV. #4274.';
