-- 0090_backfill_secretariat_per_cabinet.sql
-- P10.b — Backfill : 1 secrétariat par cabinet existant.
-- Chaque cabinet sans secrétariat reçoit un secrétariat 'Secrétariat principal'.
-- Idempotent : ON CONFLICT DO NOTHING + WHERE NOT IN garantissent qu'aucun doublon
-- n'est créé si la migration est rejouée (ou si 0086 a déjà inséré des lignes).
-- Issue : #1402

INSERT INTO secretariat (id, cabinet_id, name)
SELECT gen_random_uuid(), id, 'Secrétariat principal'
FROM cabinet
WHERE id NOT IN (SELECT cabinet_id FROM secretariat)
ON CONFLICT DO NOTHING;
