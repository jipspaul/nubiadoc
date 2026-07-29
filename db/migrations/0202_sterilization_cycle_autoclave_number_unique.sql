-- 0202_sterilization_cycle_autoclave_number_unique.sql
-- Empêche deux cycles de stérilisation portant le même (autoclave_ref,
-- cycle_number) pour un cabinet (#4489) : create_sterilization_cycle
-- insérait sans aucune contrainte d'unicité ni pré-vérification -- un
-- cycle_number pour un autoclave donné est un compteur physique unique
-- dans le monde réel (registre de traçabilité médico-légale), mais deux
-- POST identiques créaient deux lignes distinctes, sans aucun endpoint de
-- correction (pas d'UPDATE/DELETE sur sterilization-cycles).
--
-- Neutralise d'abord les doublons préexistants (le repro de #4489 en a créé
-- un en production, autoclave_ref='QA-STERIL-25952' cycle_number=42) : pour
-- chaque (cabinet_id, autoclave_ref, cycle_number) en double, seul le cycle
-- le plus ancien (created_at) reste ; les pochettes scellées
-- (sterilized_pouch) rattachées aux doublons sont réassignées au cycle
-- survivant avant suppression des lignes excédentaires (FK
-- sterilized_pouch -> sterilization_cycle, sans ON DELETE CASCADE).

WITH ranked AS (
  SELECT id, cabinet_id, autoclave_ref, cycle_number,
         row_number() OVER (
           PARTITION BY cabinet_id, autoclave_ref, cycle_number
           ORDER BY created_at ASC, id ASC
         ) AS rn
  FROM sterilization_cycle
),
survivors AS (
  SELECT cabinet_id, autoclave_ref, cycle_number, id AS keep_id
  FROM ranked WHERE rn = 1
)
UPDATE sterilized_pouch sp
SET cycle_id = s.keep_id
FROM ranked r
JOIN survivors s
  ON s.cabinet_id = r.cabinet_id
 AND s.autoclave_ref = r.autoclave_ref
 AND s.cycle_number = r.cycle_number
WHERE r.rn > 1 AND sp.cycle_id = r.id;

WITH ranked AS (
  SELECT id,
         row_number() OVER (
           PARTITION BY cabinet_id, autoclave_ref, cycle_number
           ORDER BY created_at ASC, id ASC
         ) AS rn
  FROM sterilization_cycle
)
DELETE FROM sterilization_cycle
WHERE id IN (SELECT id FROM ranked WHERE rn > 1);

ALTER TABLE sterilization_cycle
  ADD CONSTRAINT sterilization_cycle_cabinet_autoclave_number_uniq
  UNIQUE (cabinet_id, autoclave_ref, cycle_number);
