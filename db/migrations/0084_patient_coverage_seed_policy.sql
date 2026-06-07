-- 0084_patient_coverage_seed_policy.sql
-- Ajoute la policy nubia_seed sur patient_coverage.
-- La table patient_coverage (0023) a FORCE ROW LEVEL SECURITY mais ne
-- déclarait pas de policy pour nubia_seed → INSERT seed bloqué.
-- Correction minimale : policy permissive pour nubia_seed (données fictives).
-- Issue : #1097

CREATE POLICY patient_coverage_seed
  ON patient_coverage
  FOR ALL
  TO nubia_seed
  USING (true)
  WITH CHECK (true);
