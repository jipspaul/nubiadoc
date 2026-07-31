-- 0211_prescription_orthodontic_composite_fk.sql
-- #4291 : les 2 autres candidats déjà nommés dans l'issue d'origine, tous
-- deux simples à traiter isolément (une seule colonne FK convertie chacun).
--
-- prescription.consultation_id -> consultation_session(id) : FK simple
-- (0102), nullable. consultation_session n'avait pas encore UNIQUE(id,
-- cabinet_id) — ajoutée ici.
--
-- orthodontic_treatment.treatment_plan_id -> treatment_plan(id) : FK simple
-- (0189), nullable. treatment_plan a déjà UNIQUE(id, cabinet_id) (migration
-- 0200) — seule la conversion composite côté orthodontic_treatment manquait.
--
-- Même raisonnement que tous les fix précédents de cette série (0190, 0198,
-- 0200, 0210) : PostgreSQL fait bypasser la RLS aux vérifications FK/UNIQUE/
-- PK, donc une session du cabinet B pouvait rattacher sa prescription/son
-- traitement ortho à une consultation_session/un treatment_plan du cabinet
-- A, invisible en SELECT sous ce même GUC. Les deux handlers Rust
-- (prescriptions.rs::create_prescription, orthodontics.rs) valident déjà le
-- cabinet_id en amont de l'INSERT (SELECT ... WHERE cabinet_id = $2) — la
-- conversion ne peut casser aucune ligne existante, c'est un invariant DB
-- défense-en-profondeur qui ne doit pas dépendre de la correction éternelle
-- du code applicatif.
--
-- Vérifié contre Postgres réel (17.10 + pgTAP, chaîne complète des 211
-- migrations + suite pgTAP intégrale, aucune régression) : insert légitime
-- même-cabinet accepté, exploit cross-cabinet sur les deux colonnes bloqué
-- en 23503.

ALTER TABLE consultation_session
    ADD CONSTRAINT consultation_session_id_cabinet_uniq UNIQUE (id, cabinet_id);

ALTER TABLE prescription
    DROP CONSTRAINT prescription_consultation_id_fkey;
ALTER TABLE prescription
    ADD CONSTRAINT prescription_consultation_id_cabinet_fkey
    FOREIGN KEY (consultation_id, cabinet_id)
    REFERENCES consultation_session (id, cabinet_id);

ALTER TABLE orthodontic_treatment
    DROP CONSTRAINT orthodontic_treatment_treatment_plan_id_fkey;
ALTER TABLE orthodontic_treatment
    ADD CONSTRAINT orthodontic_treatment_plan_id_cabinet_fkey
    FOREIGN KEY (treatment_plan_id, cabinet_id)
    REFERENCES treatment_plan (id, cabinet_id);
