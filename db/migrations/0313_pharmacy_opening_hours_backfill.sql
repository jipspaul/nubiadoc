-- 0313_pharmacy_opening_hours_backfill.sql
-- #8068 : #8063 (pour #8061) a ajouté `pharmacy.opening_hours` (0312, défaut
-- `{}`) et enrichi `db/seed/seed.sql` avec les horaires des 8 pharmacies de
-- démo, mais l'INSERT seed utilise `ON CONFLICT (id) DO NOTHING` — sur tout
-- environnement où ces 8 lignes existaient déjà (c'est le cas en live),
-- `DO NOTHING` ne met pas à jour `opening_hours` : il reste à `{}` et la
-- carte pharmacie patient n'affiche toujours aucun horaire, exactement le
-- symptôme que #8061 visait à corriger — même mode d'échec que 0311/0271/
-- 0276/0277.
--
-- Rattrapage one-shot : les 8 pharmacies de démo ont toutes le même horaire
-- standard (lun-sam 9h-19h, fermé dimanche), déjà posé dans seed.sql.

UPDATE pharmacy SET opening_hours =
  '{"lun": "09:00-19:00", "mar": "09:00-19:00", "mer": "09:00-19:00", "jeu": "09:00-19:00", "ven": "09:00-19:00", "sam": "09:00-19:00"}'
WHERE id IN (
  '60000000-0000-0000-0000-000000000001',
  '60000000-0000-0000-0000-000000000002',
  '60000000-0000-0000-0000-000000000003',
  '60000000-0000-0000-0000-000000000004',
  '60000000-0000-0000-0000-000000000005',
  '60000000-0000-0000-0000-000000000006',
  '60000000-0000-0000-0000-000000000007',
  '60000000-0000-0000-0000-000000000008'
) AND opening_hours = '{}';
