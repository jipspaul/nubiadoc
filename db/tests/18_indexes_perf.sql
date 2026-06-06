-- 18_indexes_perf.sql — Vérifie existence des index de performance (#854).
-- GIN patient_account.contact + composites appointment date range.
-- Exécuté sous nubia_app (lecture pg_indexes).
BEGIN;
SELECT * FROM no_plan();

-- ---------------------------------------------------------------------------
-- 1. Index GIN sur patient_account.contact (jsonb_path_ops)
-- ---------------------------------------------------------------------------
SELECT ok(
  EXISTS(SELECT 1 FROM pg_indexes
    WHERE tablename  = 'patient_account'
      AND indexname  = 'idx_patient_account_contact'
      AND indexdef   LIKE '%gin%'),
  'patient_account : index GIN idx_patient_account_contact présent (0056)');

-- ---------------------------------------------------------------------------
-- 2. Index composé appointment(cabinet_id, starts_at DESC)
-- ---------------------------------------------------------------------------
SELECT ok(
  EXISTS(SELECT 1 FROM pg_indexes
    WHERE tablename = 'appointment'
      AND indexname = 'idx_appointment_cabinet_starts_at'),
  'appointment : index idx_appointment_cabinet_starts_at présent (0056)');

-- ---------------------------------------------------------------------------
-- 3. Index appointment(patient_id, starts_at DESC) pour dashboard patient
-- ---------------------------------------------------------------------------
SELECT ok(
  EXISTS(SELECT 1 FROM pg_indexes
    WHERE tablename = 'appointment'
      AND indexname = 'idx_appointment_patient_starts_at'),
  'appointment : index idx_appointment_patient_starts_at présent (0056)');

SELECT * FROM finish();
ROLLBACK;
