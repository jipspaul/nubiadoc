-- 0311_pharmacy_nurse_seed_duplicate_cleanup.sql
-- #8037 : #6893 (3822553ba, PR #8018) a renuméroté les 8 pharmacies et
-- l'infirmière de démo de `f0000000-…`/`c0000000-…-c1` vers `60000000-…`/
-- `61000000-…-01` directement dans `db/seed/seed.sql`, inséré avec
-- `ON CONFLICT (id) DO NOTHING`. Changer l'`id` d'une ligne existante ne la
-- renomme pas : sur tout environnement où l'ancien seed avait déjà tourné,
-- ce `DO NOTHING` a laissé les 8 anciennes pharmacies (+ la nurse) en place
-- et simplement INSÉRÉ les 8 nouvelles à côté — même mode d'échec que 0271/
-- 0276/0277. Conséquences en live : annuaire patient à 16 pharmacies pour 8
-- officines (homonymes, adresse identique, indiscernables), double adhésion
-- du compte pharmacien démo sur les deux jumelles (`pharmacy_membership`),
-- et la collision d'UUID pharmacy/provider que #6893 visait à éliminer
-- toujours live côté anciens id `f0000000-…`.
--
-- Rattrapage one-shot : repointer toutes les FK vers le nouvel id puis
-- supprimer la ligne pharmacy/nurse legacy (`pharmacy_membership`,
-- `nurse_membership` et `visit_offer` suivent par ON DELETE CASCADE,
-- posé en 0121/0233/0234 — aucune action manuelle requise sur ces tables).

CREATE TEMP TABLE pharmacy_seed_id_remap (old_id uuid PRIMARY KEY, new_id uuid NOT NULL) ON COMMIT DROP;
INSERT INTO pharmacy_seed_id_remap (old_id, new_id) VALUES
  ('f0000000-0000-0000-0000-0000000000f1', '60000000-0000-0000-0000-000000000001'),
  ('f0000000-0000-0000-0000-0000000000f2', '60000000-0000-0000-0000-000000000002'),
  ('f0000000-0000-0000-0000-0000000000f3', '60000000-0000-0000-0000-000000000003'),
  ('f0000000-0000-0000-0000-0000000000f4', '60000000-0000-0000-0000-000000000004'),
  ('f0000000-0000-0000-0000-0000000000f5', '60000000-0000-0000-0000-000000000005'),
  ('f0000000-0000-0000-0000-0000000000f6', '60000000-0000-0000-0000-000000000006'),
  ('f0000000-0000-0000-0000-0000000000f7', '60000000-0000-0000-0000-000000000007'),
  ('f0000000-0000-0000-0000-0000000000f8', '60000000-0000-0000-0000-000000000008');

UPDATE pharmacy_order po SET pharmacy_id = r.new_id
  FROM pharmacy_seed_id_remap r WHERE po.pharmacy_id = r.old_id;

UPDATE patient_account pa SET pharmacy_id = r.new_id
  FROM pharmacy_seed_id_remap r WHERE pa.pharmacy_id = r.old_id;

UPDATE stock_request sr SET pharmacy_id = r.new_id
  FROM pharmacy_seed_id_remap r WHERE sr.pharmacy_id = r.old_id;

UPDATE pharmacy_quote pq SET pharmacy_id = r.new_id
  FROM pharmacy_seed_id_remap r WHERE pq.pharmacy_id = r.old_id;

-- conversation a une contrainte UNIQUE (patient_account_id, pharmacy_id) :
-- si un fil existe déjà sur le nouvel id pour le même compte, le doublon
-- legacy (et ses messages, pas de ON DELETE CASCADE sur message.conversation_id)
-- est supprimé plutôt que repointé.
DELETE FROM message m
  USING conversation old_c, conversation new_c, pharmacy_seed_id_remap r
  WHERE m.conversation_id = old_c.id
    AND old_c.pharmacy_id = r.old_id
    AND new_c.pharmacy_id = r.new_id
    AND new_c.patient_account_id = old_c.patient_account_id;

DELETE FROM conversation old_c
  USING conversation new_c, pharmacy_seed_id_remap r
  WHERE old_c.pharmacy_id = r.old_id
    AND new_c.pharmacy_id = r.new_id
    AND new_c.patient_account_id = old_c.patient_account_id;

UPDATE message m SET pharmacy_id = r.new_id
  FROM pharmacy_seed_id_remap r WHERE m.pharmacy_id = r.old_id;

UPDATE conversation c SET pharmacy_id = r.new_id
  FROM pharmacy_seed_id_remap r WHERE c.pharmacy_id = r.old_id;

DELETE FROM pharmacy p USING pharmacy_seed_id_remap r WHERE p.id = r.old_id;

-- Infirmière démo : même collision (c0000000-…-c1 -> 61000000-…-01).
UPDATE visit_request SET nurse_id = '61000000-0000-0000-0000-000000000001'
  WHERE nurse_id = 'c0000000-0000-0000-0000-0000000000c1';

DELETE FROM nurse WHERE id = 'c0000000-0000-0000-0000-0000000000c1';
