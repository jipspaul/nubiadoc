-- 0218_document_patient_read_guardian.sql
-- Étend document_patient_read (migration 0034) à la branche tutelle
-- (#4598, QA-20260802-6), symétrique à appointment_patient_read (0196) et
-- prescription_patient_read (#4597).
--
-- Le document coffre-fort d'un dépendant (ex : PDF d'ordonnance signée,
-- cf. #4597 POST /cabinet/prescriptions/:id/sign) est rattaché au
-- patient_id du dépendant, jamais du tuteur. La policy actuelle ne connaît
-- que app.patient_account_id = compte de session, sans branche
-- guardianship — le document reste invisible/404 côté tuteur alors que
-- le cabinet le télécharge (200).
--
-- Fix : même branche tutelle que 0196 (account_guardianship, active=true).
-- La sous-requête account_guardianship reste soumise à sa propre policy
-- guardianship_owner_select (migration 0025), qui exige app.current_account_id
-- — les handlers patient (list_documents, get_document, download_document,
-- api/src/documents.rs) doivent donc poser AUSSI app.current_account_id,
-- en plus de app.patient_account_id, comme déjà fait pour les RDV (0196).

DROP POLICY document_patient_read ON document;
CREATE POLICY document_patient_read ON document
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

COMMENT ON POLICY document_patient_read ON document IS
  'Lecture patient (compte propre) OU tuteur légal actif (account_guardianship) du dépendant rattaché au document. #4598.';
