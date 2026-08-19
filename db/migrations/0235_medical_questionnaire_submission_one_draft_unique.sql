-- 0235_medical_questionnaire_submission_one_draft_unique.sql
-- #5732 : le contrôle applicatif « un seul brouillon actif par
-- (patient_account_id, cabinet_id) » dans create_medical_questionnaire
-- (SELECT puis INSERT, sans verrou) est une race TOCTOU sous requêtes
-- concurrentes (double-tap/retry réseau) — même classe que #5725. Un index
-- unique partiel fait respecter l'invariant au niveau base, le handler
-- catchant ensuite le 23505 pour renvoyer le 409 métier existant.

-- 1. Backfill : le bug a déjà produit des doublons en env live (repro de
--   l'issue : 5 brouillons pour un même couple patient+cabinet). Pour
--   chaque couple avec >1 brouillon, on garde le PLUS RÉCEMMENT modifié et
--   on supprime les autres — même logique que 0099 (aucun statut
--   "superseded" n'existe dans le CHECK de 0180, la suppression est donc le
--   seul moyen d'assainir sans étendre le schéma pour ce correctif).
DO $$
DECLARE
  dup_count int := 0;
BEGIN
  WITH dups AS (
    SELECT patient_account_id, cabinet_id
    FROM medical_questionnaire_submission
    WHERE status = 'draft'
    GROUP BY patient_account_id, cabinet_id
    HAVING count(*) > 1
  ),
  losers AS (
    SELECT mqs.id
    FROM medical_questionnaire_submission mqs
    JOIN dups d
      ON d.patient_account_id = mqs.patient_account_id
     AND d.cabinet_id = mqs.cabinet_id
    WHERE mqs.status = 'draft'
      AND mqs.id NOT IN (
        SELECT DISTINCT ON (patient_account_id, cabinet_id) id
        FROM medical_questionnaire_submission
        WHERE status = 'draft'
        ORDER BY patient_account_id, cabinet_id, updated_at DESC, id DESC
      )
  )
  DELETE FROM medical_questionnaire_submission
  WHERE id IN (SELECT id FROM losers);

  GET DIAGNOSTICS dup_count = ROW_COUNT;
  IF dup_count > 0 THEN
    RAISE NOTICE '0235 backfill: % duplicate draft(s) deleted (medical_questionnaire_submission).', dup_count;
  END IF;
END $$;

-- 2. Index unique partiel.
CREATE UNIQUE INDEX IF NOT EXISTS medical_questionnaire_submission_one_draft_uidx
  ON medical_questionnaire_submission (patient_account_id, cabinet_id)
  WHERE status = 'draft';

COMMENT ON INDEX medical_questionnaire_submission_one_draft_uidx IS
  'Un seul brouillon (status=draft) actif par (patient_account_id, cabinet_id) — #5732.';
