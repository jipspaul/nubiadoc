-- 0198_sterilized_pouch_cycle_composite_fk.sql
-- Complète 0190 : sterilized_pouch.cycle_id référençait sterilization_cycle
-- via une FK SIMPLE, laissée de côté alors que ce même fichier avait déjà
-- composite-fixé sterilized_pouch.consultation_act_id → consultation_act
-- (id, cabinet_id) pour exactement cette raison (cf. commentaire 0190 :
-- PostgreSQL fait bypasser la RLS aux vérifications FK/UNIQUE/PK — une FK
-- simple laisse une session du cabinet B référencer un sterilization_cycle
-- du cabinet A). Gap découvert lors de l'audit systémique #4291.
--
-- cycle_id est NOT NULL (contrairement à consultation_act_id) : toutes les
-- lignes existantes ont déjà un cabinet_id cohérent avec leur cycle (seul
-- moyen d'avoir été insérées jusqu'ici, RLS write oblige) — la conversion en
-- composite ne peut pas casser de ligne existante.

ALTER TABLE sterilization_cycle
    ADD CONSTRAINT sterilization_cycle_id_cabinet_uniq UNIQUE (id, cabinet_id);

ALTER TABLE sterilized_pouch
    DROP CONSTRAINT sterilized_pouch_cycle_id_fkey;

ALTER TABLE sterilized_pouch
    ADD CONSTRAINT sterilized_pouch_cycle_id_cabinet_fkey
    FOREIGN KEY (cycle_id, cabinet_id)
    REFERENCES sterilization_cycle (id, cabinet_id);
