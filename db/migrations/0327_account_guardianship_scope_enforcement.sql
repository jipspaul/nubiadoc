-- 0327_account_guardianship_scope_enforcement.sql
-- Issue #8556 (QA-20261102-R172-3) : le périmètre consenti par l'invité sur
-- `POST /v1/account/access-requests/:id/accept` (`scope`, ex. `scope: []`)
-- était stocké, intersecté, re-rendu fidèlement… mais jamais lu par aucun
-- contrôle d'accès : `account_guardianship` (seule table matérialisant
-- l'accès réel, cf. auth/mod.rs #6935) n'avait pas de colonne scope, donc
-- un invité retirant TOUS les droits laissait quand même le demandeur
-- prendre ET annuler ses RDV (`rendez_vous` jamais vérifié).
--
-- 1. Colonne scope sur account_guardianship, NULL = tutelle pleine (authority
--    'full'/'legal_guardian', mineur — pas de périmètre à borner). Pour un
--    lien `authority = 'delegated'` issu d'une demande acceptée, scope est
--    désormais le périmètre consenti (éventuellement vide).
ALTER TABLE account_guardianship
  ADD COLUMN IF NOT EXISTS scope TEXT[];

-- 2. appointment_patient_read (migration 0196) : la branche tutelle doit
--    désormais exiger `rendez_vous` dans le scope consenti (ou scope NULL =
--    tutelle pleine). Redéfinition complète de la policy (DROP/CREATE), même
--    pattern que 0196 ; seule la branche tutelle change.
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
          AND (scope IS NULL OR 'rendez_vous' = ANY(scope))
      )
    )
  );

COMMENT ON POLICY appointment_patient_read ON appointment IS
  'Lecture patient (compte propre) OU tuteur légal actif (account_guardianship) du dépendant rattaché au RDV, borné au scope consenti (#8556). #4274.';
