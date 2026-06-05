-- 05_marketplace_taxonomy.sql — Contrat profession / specialty / medical_act (issue #530).
-- pgTAP. Exécuté par pg_prove (sous nubia_app). Réf. docs/05 §9.2.
BEGIN;
SELECT plan(8);

SELECT has_table('profession');
SELECT has_table('specialty');
SELECT has_table('medical_act');

SELECT fk_ok('specialty',   'profession_id', 'profession', 'id');
SELECT fk_ok('medical_act', 'specialty_id',  'specialty',  'id');

SELECT is((SELECT count(*)::int FROM profession),  2, 'seed 2 professions');
SELECT is((SELECT count(*)::int FROM specialty),   3, 'seed 3 specialties');
SELECT is((SELECT count(*)::int FROM medical_act), 5, 'seed 5 actes');

SELECT finish();
ROLLBACK;
