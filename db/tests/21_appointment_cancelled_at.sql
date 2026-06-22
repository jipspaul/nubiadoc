-- 21_appointment_cancelled_at.sql — colonne cancelled_at + index partiel (issue #2512).
-- Tests :
--   COL1. cancelled_at présente sur appointment (has_column).
--   IDX1. idx_appointment_cancelled_at présent (has_index).
--   IDX2. Prédicat WHERE status = 'cancelled' déclaré dans pg_indexes.
-- Exécuté sous nubia_app (lecture pg_indexes).
BEGIN;
SELECT * FROM no_plan();

-- ---------------------------------------------------------------------------
-- COL1. Existence de la colonne cancelled_at
-- ---------------------------------------------------------------------------
SELECT has_column('appointment', 'cancelled_at',
  'COL1 appointment : colonne cancelled_at présente');

-- ---------------------------------------------------------------------------
-- IDX1. Existence de l'index partiel idx_appointment_cancelled_at
-- ---------------------------------------------------------------------------
SELECT has_index('appointment', 'idx_appointment_cancelled_at',
  'IDX1 appointment : index idx_appointment_cancelled_at présent');

-- ---------------------------------------------------------------------------
-- IDX2. Prédicat WHERE status = 'cancelled' déclaré dans pg_indexes
-- ---------------------------------------------------------------------------
SELECT ok(
    EXISTS(SELECT 1 FROM pg_indexes
      WHERE tablename = 'appointment'
        AND indexname = 'idx_appointment_cancelled_at'
        AND indexdef  LIKE '%status = ''cancelled''%'),
    'IDX2 appointment : prédicat WHERE status = ''cancelled'' vérifié dans pg_indexes');

SELECT * FROM finish();
ROLLBACK;
