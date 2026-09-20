-- 0288_create_treatment_session.sql
-- [DP-F16.a] Séances de plan de traitement + règles de découpage du cabinet
-- (#7174).
--
-- État actuel (db/AGENTS.md, api/src/treatment_phases.rs) : treatment_phase
-- (0010) regroupe des quote_item sous un intitulé de phase ('Phase 2 ·
-- Chirurgie implantaire') avec juste un compteur planned_sessions /
-- completed_sessions (0184, #4119) — aucune ligne individuelle ne modélise
-- une séance concrète (ordre, durée, actes réalisés, RDV lié). C'est l'écart
-- que comble treatment_session ici : phase = regroupement métier, session =
-- unité de découpage au fauteuil.
--
-- treatment_session : une séance individuelle d'un plan de traitement —
-- position (ordre), durée estimée, RDV lié une fois programmée (nullable :
-- une séance peut exister avant sa prise de RDV), statut.
-- treatment_session_act : les actes qui composent une séance, réalisés
-- (consultation_act) ou seulement devisés (quote_item) — jamais les deux à
-- la fois pour une même ligne (XOR), même esprit que quote_attachment
-- (0278).
-- cabinet_session_rules : réglage par cabinet des règles de découpage
-- utilisées par le futur algorithme de répartition des actes en séances
-- (durée max, ne pas mélanger maxillaire/mandibulaire, regrouper par
-- secteur, autoriser plusieurs endo dans la même séance). Une ligne par
-- cabinet, même esprit que cabinet_act_category_setting (0283) : absence de
-- ligne = valeurs par défaut appliquées côté API.
--
-- FK COMPOSITES (plan_id/appointment_id/session_id/consultation_act_id/
-- quote_item_id + cabinet_id) plutôt que des FK simples : PostgreSQL fait
-- bypasser la RLS aux vérifications d'intégrité référentielle (FK/UNIQUE/PK)
-- même sous FORCE ROW LEVEL SECURITY (#4137/migration 0190) — même pattern
-- que lab_work_order (0193) / treatment_plan_phase_quote_item_composite_fk
-- (0200). Les UNIQUE (id, cabinet_id) requis existent déjà : treatment_plan
-- (0200), appointment (0193), consultation_act (0190), quote_item (0193).
-- treatment_session est créée et référencée dans la même migration : son
-- UNIQUE (id, cabinet_id) est posé directement dans le CREATE TABLE (même
-- pattern que stock_item -> stock_movement, 0192).

CREATE TABLE treatment_session (
    id             uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    cabinet_id     uuid        NOT NULL REFERENCES cabinet(id),
    plan_id        uuid        NOT NULL,
    position       int         NOT NULL CHECK (position > 0),
    duration_min   integer     NOT NULL CHECK (duration_min > 0),
    appointment_id uuid,
    status         text        NOT NULL DEFAULT 'planned'
                    CHECK (status IN ('planned', 'scheduled', 'in_progress', 'done', 'cancelled')),
    created_at     timestamptz NOT NULL DEFAULT now(),
    updated_at     timestamptz NOT NULL DEFAULT now(),
    UNIQUE (id, cabinet_id),
    UNIQUE (plan_id, position),
    FOREIGN KEY (plan_id, cabinet_id)
        REFERENCES treatment_plan (id, cabinet_id),
    FOREIGN KEY (appointment_id, cabinet_id)
        REFERENCES appointment (id, cabinet_id)
);

CREATE INDEX idx_treatment_session_cabinet_plan
    ON treatment_session (cabinet_id, plan_id);
CREATE INDEX idx_treatment_session_appointment
    ON treatment_session (appointment_id)
    WHERE appointment_id IS NOT NULL;

CREATE TABLE treatment_session_act (
    id                  uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    cabinet_id          uuid        NOT NULL REFERENCES cabinet(id),
    session_id          uuid        NOT NULL,
    consultation_act_id uuid,
    quote_item_id       uuid,
    created_at          timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (session_id, cabinet_id)
        REFERENCES treatment_session (id, cabinet_id),
    FOREIGN KEY (consultation_act_id, cabinet_id)
        REFERENCES consultation_act (id, cabinet_id),
    FOREIGN KEY (quote_item_id, cabinet_id)
        REFERENCES quote_item (id, cabinet_id),
    CONSTRAINT treatment_session_act_source_xor
        CHECK (num_nonnulls(consultation_act_id, quote_item_id) = 1)
);

CREATE INDEX idx_treatment_session_act_cabinet_session
    ON treatment_session_act (cabinet_id, session_id);
CREATE UNIQUE INDEX idx_treatment_session_act_uniq_consultation_act
    ON treatment_session_act (session_id, consultation_act_id)
    WHERE consultation_act_id IS NOT NULL;
CREATE UNIQUE INDEX idx_treatment_session_act_uniq_quote_item
    ON treatment_session_act (session_id, quote_item_id)
    WHERE quote_item_id IS NOT NULL;

CREATE TABLE cabinet_session_rules (
    id                uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    cabinet_id        uuid        NOT NULL REFERENCES cabinet(id),
    max_duration_min  integer     CHECK (max_duration_min IS NULL OR max_duration_min > 0),
    separate_arches   boolean     NOT NULL DEFAULT false,
    group_by_sector   boolean     NOT NULL DEFAULT false,
    multi_endo        boolean     NOT NULL DEFAULT true,
    updated_at        timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT cabinet_session_rules_cabinet_uniq UNIQUE (cabinet_id)
);

-- RLS tenant (fail-closed : GUC absent → 0 ligne) sur les trois tables.
ALTER TABLE treatment_session ENABLE ROW LEVEL SECURITY;
ALTER TABLE treatment_session FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON treatment_session
    FOR ALL
    TO nubia_app
    USING      (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid)
    WITH CHECK (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid);

ALTER TABLE treatment_session_act ENABLE ROW LEVEL SECURITY;
ALTER TABLE treatment_session_act FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON treatment_session_act
    FOR ALL
    TO nubia_app
    USING      (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid)
    WITH CHECK (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid);

ALTER TABLE cabinet_session_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE cabinet_session_rules FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON cabinet_session_rules
    FOR ALL
    TO nubia_app
    USING      (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid)
    WITH CHECK (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid);

GRANT SELECT, INSERT, UPDATE, DELETE ON treatment_session TO nubia_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON treatment_session_act TO nubia_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON cabinet_session_rules TO nubia_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON treatment_session TO nubia_seed;
GRANT SELECT, INSERT, UPDATE, DELETE ON treatment_session_act TO nubia_seed;
GRANT SELECT, INSERT, UPDATE, DELETE ON cabinet_session_rules TO nubia_seed;

COMMENT ON TABLE treatment_session IS
    'Séance individuelle d''un plan de traitement (ordre, durée estimée, RDV lié optionnel, statut). Distinct de treatment_phase (regroupement métier, 0010). Table tenant (cabinet_id). RLS fail-closed. #7174.';
COMMENT ON TABLE treatment_session_act IS
    'Acte composant une séance : réalisé (consultation_act) ou seulement devisé (quote_item), jamais les deux (XOR). Table tenant (cabinet_id). RLS fail-closed. #7174.';
COMMENT ON TABLE cabinet_session_rules IS
    'Règles de découpage des séances par cabinet (durée max, séparation maxillaire/mandibulaire, regroupement par secteur, endo multiples autorisées). Une ligne par cabinet ; absence de ligne = défauts applicatifs. Table tenant (cabinet_id). RLS fail-closed. #7174.';
