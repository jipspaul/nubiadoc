-- 0276_app_user_seed_backfill_identity.sql
-- #7343 : #6170 a ajouté first_name/last_name à `db/seed/seed.sql` via un
-- `INSERT ... ON CONFLICT (id) DO NOTHING` (lignes 42-55). Sur tout
-- environnement où les 4 lignes historiques du cabinet démo
-- (a0000000-…-0000000000a1..a4) existaient déjà, ce `DO NOTHING` ignore
-- purement les nouvelles valeurs et first_name/last_name restent NULL pour
-- toujours — même mode d'échec que 0271 (cabinet.settings.contact.phone),
-- qui utilise le même remède : un vrai `UPDATE`. Conséquence en live : la
-- messagerie interne du cabinet signe « Membre du cabinet » pour ces 4
-- membres (api/src/cabinet_team_messages.rs) et la feature « Tâches »
-- (#7211) renvoie `assignee_display_name: null` dès qu'un de ces membres
-- est assigné.
-- Migration immuable (règle db/migrations/README.md) : rattrapage one-shot
-- via UPDATE, valeurs identiques à celles de db/seed/seed.sql:42-55.

UPDATE app_user SET first_name = 'Hugo', last_name = 'Marin'
WHERE id = 'a0000000-0000-0000-0000-0000000000a1'
  AND first_name IS NULL AND last_name IS NULL;

UPDATE app_user SET first_name = 'Claire', last_name = 'Lefèvre'
WHERE id = 'a0000000-0000-0000-0000-0000000000a2'
  AND first_name IS NULL AND last_name IS NULL;

UPDATE app_user SET first_name = 'Sonia', last_name = 'Accueil'
WHERE id = 'a0000000-0000-0000-0000-0000000000a3'
  AND first_name IS NULL AND last_name IS NULL;

UPDATE app_user SET first_name = 'Admin', last_name = ''
WHERE id = 'a0000000-0000-0000-0000-0000000000a4'
  AND first_name IS NULL AND last_name IS NULL;
