-- 69_patient_phone_trgm.sql — Vérifie l'index trigram sur le téléphone
-- patient (#4100, migration 0177).
--
-- Déviation documentée : l'issue demande de vérifier "l'utilisation de
-- l'index (EXPLAIN)" — aucun test de ce dépôt n'affirme l'usage d'un index
-- via EXPLAIN sur un jeu de données de fixture (quelques lignes) : le
-- planificateur PostgreSQL choisit quasi systématiquement un Seq Scan sur
-- une table aussi petite, indépendamment de l'existence de l'index — une
-- assertion EXPLAIN serait non fiable, pas un signal de régression. Suit le
-- pattern déjà établi (19_appointment_idx.sql, 18_indexes_perf.sql) :
-- existence + définition de l'index via le catalogue pg_indexes.
--
-- Invariants couverts :
--   IDX1. patient_phone_trgm présent sur la table patient.
--   IDX2. Méthode d'accès = gin (nécessaire pour gin_trgm_ops).
--   IDX3. Expression indexée = (contact ->> 'tel'::text) — pas une colonne
--         `phone` à plat, qui n'existe pas sur `patient`.
-- Exécuté sous nubia_app (lecture pg_indexes).

BEGIN;
SELECT * FROM no_plan();

SELECT has_index('patient', 'patient_phone_trgm');

SELECT ok(
    EXISTS(SELECT 1 FROM pg_indexes
      WHERE tablename  = 'patient'
        AND indexname  = 'patient_phone_trgm'
        AND indexdef   LIKE '%USING gin%'),
    'IDX2 patient_phone_trgm : méthode d''accès gin (gin_trgm_ops)');

SELECT ok(
    EXISTS(SELECT 1 FROM pg_indexes
      WHERE tablename  = 'patient'
        AND indexname  = 'patient_phone_trgm'
        AND indexdef   LIKE '%contact ->> ''tel''%'),
    'IDX3 patient_phone_trgm : expression indexée = contact ->> ''tel''');

SELECT * FROM finish();
ROLLBACK;
