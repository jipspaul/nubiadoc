-- 19_appointment_idx.sql — Vérifie l'index partiel sur appointment(starts_at) (#2471).
-- Invariants couverts :
--   IDX1. idx_appointment_starts_at_confirmed présent sur la table appointment.
--   IDX2. Prédicat de l'index = WHERE status = 'confirmed'.
-- Exécuté sous nubia_app (lecture pg_indexes).
BEGIN;
SELECT * FROM no_plan();

-- ---------------------------------------------------------------------------
-- IDX1. Existence de l'index partiel idx_appointment_starts_at_confirmed
-- ---------------------------------------------------------------------------
SELECT has_index('appointment', 'idx_appointment_starts_at_confirmed');

-- ---------------------------------------------------------------------------
-- IDX2. Prédicat WHERE status = 'confirmed' déclaré dans pg_indexes
-- ---------------------------------------------------------------------------
SELECT ok(
    EXISTS(SELECT 1 FROM pg_indexes
      WHERE tablename  = 'appointment'
        AND indexname  = 'idx_appointment_starts_at_confirmed'
        AND indexdef   LIKE '%status = ''confirmed''%'),
    'IDX2 appointment : prédicat WHERE status = ''confirmed'' vérifié dans pg_indexes');

SELECT * FROM finish();
ROLLBACK;
