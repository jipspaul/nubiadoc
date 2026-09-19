-- 0277_app_user_seed_backfill_identity_secretaries.sql
-- #7371 : 0276 (#7343) n'a rattrapé que les 4 membres historiques du
-- cabinet démo (a0000000-…-0000000000a1..a4). `db/seed/seed.sql` insère
-- deux secrétaires supplémentaires — lena.monceau (…-000000000a10) et
-- marie.secretaire (…-000000000011) — dont l'INSERT d'origine n'a jamais
-- porté first_name/last_name du tout (pas un `ON CONFLICT DO NOTHING`
-- comme pour a1..a4, mais des colonnes absentes de l'INSERT). Même
-- conséquence en live : `assignee_display_name: null` sur la feature
-- « Tâches » (#7211) dès qu'une de ces deux secrétaires est assignée.
-- Migration immuable (règle db/migrations/README.md) : rattrapage one-shot
-- via UPDATE, valeurs identiques à celles de db/seed/seed.sql.

UPDATE app_user SET first_name = 'Léna', last_name = 'Monceau'
WHERE id = 'a0000000-0000-0000-0000-000000000a10'
  AND first_name IS NULL AND last_name IS NULL;

UPDATE app_user SET first_name = 'Marie', last_name = 'Secrétaire'
WHERE id = 'a0000000-0000-0000-0000-000000000011'
  AND first_name IS NULL AND last_name IS NULL;
