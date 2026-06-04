-- 0025_patient_coverage_unique_account.sql
-- Ajoute la contrainte UNIQUE (patient_account_id) sur patient_coverage,
-- requise pour l'upsert ON CONFLICT dans PATCH /v1/account/coverage (#243).
-- Un patient n'a qu'une seule ligne de couverture (1-1 avec patient_account).

ALTER TABLE patient_coverage
  ADD CONSTRAINT patient_coverage_patient_account_id_key
  UNIQUE (patient_account_id);
