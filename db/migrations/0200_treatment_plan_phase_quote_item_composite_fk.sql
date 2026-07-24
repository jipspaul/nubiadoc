-- 0200_quote_item_phase_composite_fk.sql
-- quote_item.phase_id référençait treatment_phase via une FK SIMPLE — gap
-- de la même classe que #4137/#4291 : PostgreSQL fait bypasser la RLS aux
-- vérifications d'intégrité référentielle (FK/UNIQUE/PK), donc une session
-- du cabinet B pouvait rattacher sa ligne quote_item à une treatment_phase
-- du cabinet A, alors même que cette phase est invisible en SELECT sous ce
-- GUC (tenant_isolation, migration 0011). Candidat identifié dans l'audit
-- systémique #4291 (quote_item a déjà UNIQUE(id, cabinet_id), migration
-- 0193 — il ne manquait que le pendant côté treatment_phase).
--
-- En inspectant treatment_phase pour ce fix, même gap trouvé juste à côté :
-- treatment_phase.plan_id → treatment_plan(id), FK simple elle aussi.
-- Corrigée dans la même migration (même classe de bug, même table touchée).
--
-- Les deux colonnes concernées (phase_id nullable, plan_id NOT NULL) : les
-- lignes existantes n'ont pu être insérées que via une session déjà scopée
-- à un cabinet cohérent (RLS write oblige) — la conversion en composite ne
-- peut casser aucune ligne existante.

ALTER TABLE treatment_plan
    ADD CONSTRAINT treatment_plan_id_cabinet_uniq UNIQUE (id, cabinet_id);

ALTER TABLE treatment_phase
    ADD CONSTRAINT treatment_phase_id_cabinet_uniq UNIQUE (id, cabinet_id);

ALTER TABLE treatment_phase
    DROP CONSTRAINT treatment_phase_plan_id_fkey;

ALTER TABLE treatment_phase
    ADD CONSTRAINT treatment_phase_plan_id_cabinet_fkey
    FOREIGN KEY (plan_id, cabinet_id)
    REFERENCES treatment_plan (id, cabinet_id);

ALTER TABLE quote_item
    DROP CONSTRAINT quote_item_phase_id_fkey;

ALTER TABLE quote_item
    ADD CONSTRAINT quote_item_phase_id_cabinet_fkey
    FOREIGN KEY (phase_id, cabinet_id)
    REFERENCES treatment_phase (id, cabinet_id);
