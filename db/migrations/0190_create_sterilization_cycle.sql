-- 0190_create_sterilization_cycle.sql
-- Traçabilité de stérilisation (#4137) : aucune trace dans le schéma
-- alors que le référentiel la qualifie de checkbox obligatoire en démo
-- (§4.3 point 6).
--
-- sterilization_cycle : un cycle d'autoclave, avec indicateur de contrôle
-- physico-chimique (test_kind/test_result) et verdict global (status).
-- sterilized_pouch : une pochette scellée issue d'un cycle, tracée par son
-- code datamatrix/barcode, optionnellement associée à l'acte pour lequel
-- elle a été utilisée (traçabilité lot ↔ patient ↔ acte).
--
-- consultation_act_id nullable + FK COMPOSITE (consultation_act_id,
-- cabinet_id) plutôt qu'une FK simple sur l'id seul : contrairement à une
-- intuition naturelle, PostgreSQL fait EXPLICITEMENT bypasser la RLS aux
-- vérifications d'intégrité référentielle (contraintes FK/UNIQUE/PK) — la
-- FORCE ROW LEVEL SECURITY de consultation_act (migration 0042) n'empêche
-- donc PAS de référencer un acte d'un AUTRE cabinet via une FK simple sur
-- l'id (vérifié : un premier essai avec FK simple laissait passer le cas
-- cross-tenant, la suite pgTAP complète l'a détecté). Fix standard
-- PostgreSQL pour un FK tenant-scopé : UNIQUE (id, cabinet_id) côté table
-- référencée + FK composite (consultation_act_id, cabinet_id) côté table
-- référençante — un mismatch de cabinet_id ne correspond à aucune ligne de
-- l'index unique, la FK échoue en 23503 indépendamment de la RLS.

CREATE TABLE sterilization_cycle (
    id            uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    cabinet_id    uuid        NOT NULL REFERENCES cabinet(id),
    autoclave_ref text        NOT NULL,
    cycle_number  integer     NOT NULL CHECK (cycle_number > 0),
    started_at    timestamptz NOT NULL DEFAULT now(),
    test_kind     text        NOT NULL CHECK (test_kind IN ('bowie_dick', 'helix')),
    test_result   text        NOT NULL,
    status        text        NOT NULL CHECK (status IN ('conforme', 'non_conforme')),
    created_at    timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_sterilization_cycle_cabinet
    ON sterilization_cycle (cabinet_id);

-- Index unique requis pour servir de cible à la FK composite ci-dessous
-- (id seul est déjà PK/unique, ce doublon (id, cabinet_id) est trivialement
-- satisfait pour toute ligne existante — aucun impact sur consultation_act).
ALTER TABLE consultation_act
    ADD CONSTRAINT consultation_act_id_cabinet_uniq UNIQUE (id, cabinet_id);

CREATE TABLE sterilized_pouch (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    cabinet_id          uuid NOT NULL REFERENCES cabinet(id),
    cycle_id            uuid NOT NULL REFERENCES sterilization_cycle(id),
    code                text NOT NULL,
    consultation_act_id uuid,
    FOREIGN KEY (consultation_act_id, cabinet_id)
        REFERENCES consultation_act (id, cabinet_id)
);

CREATE INDEX idx_sterilized_pouch_cycle
    ON sterilized_pouch (cycle_id);
CREATE INDEX idx_sterilized_pouch_consultation_act
    ON sterilized_pouch (consultation_act_id)
    WHERE consultation_act_id IS NOT NULL;

-- RLS tenant (fail-closed : GUC absent → 0 ligne) sur les deux tables.
ALTER TABLE sterilization_cycle ENABLE ROW LEVEL SECURITY;
ALTER TABLE sterilization_cycle FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON sterilization_cycle
    FOR ALL
    TO nubia_app
    USING      (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid)
    WITH CHECK (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid);

ALTER TABLE sterilized_pouch ENABLE ROW LEVEL SECURITY;
ALTER TABLE sterilized_pouch FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON sterilized_pouch
    FOR ALL
    TO nubia_app
    USING      (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid)
    WITH CHECK (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid);

GRANT SELECT, INSERT, UPDATE, DELETE ON sterilization_cycle TO nubia_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON sterilized_pouch TO nubia_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON sterilization_cycle TO nubia_seed;
GRANT SELECT, INSERT, UPDATE, DELETE ON sterilized_pouch TO nubia_seed;

COMMENT ON TABLE sterilization_cycle IS
    'Cycle de stérilisation autoclave (indicateur physico-chimique + verdict conforme/non_conforme). #4137.';
COMMENT ON TABLE sterilized_pouch IS
    'Pochette scellée issue d''un cycle, tracée par code datamatrix/barcode, optionnellement associée à l''acte où elle a été utilisée. #4137.';
