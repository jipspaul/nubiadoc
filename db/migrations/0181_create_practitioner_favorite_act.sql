-- 0181_create_practitioner_favorite_act.sql
-- Actes CCAM favoris par praticien (#4111) : `search_ccam_acts` (#3226,
-- migration 0119) renvoie toujours les 25 premiers résultats alphabétiques
-- du catalogue `ccam_act`, aucune personnalisation par praticien n'existe —
-- un praticien qui pose surtout des couronnes doit retaper "couronne" à
-- chaque consultation au lieu d'avoir ses actes habituels en tête de liste.
--
-- `position` : ordre d'affichage choisi par le praticien (pas de contrainte
-- d'unicité sur (practitioner_id, position) — non demandée par l'issue,
-- l'API qui exploitera cette table pourra réordonner sans transaction
-- multi-lignes complexe).
--
-- RLS tenant (cabinet_id) comme demandé par l'issue — le filtrage par
-- practitioner_id (un praticien ne voit que ses propres favoris, pas ceux
-- d'un confrère du même cabinet) relève de la couche API, pas de la RLS
-- (même découpage que patient_tag/provider_unavailability : RLS = isolation
-- cabinet, ownership fin = application).

CREATE TABLE practitioner_favorite_act (
    id              uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    practitioner_id uuid        NOT NULL REFERENCES practitioner(id),
    cabinet_id      uuid        NOT NULL REFERENCES cabinet(id),
    ccam_code       text        NOT NULL REFERENCES ccam_act(code),
    position        integer     NOT NULL,
    created_at      timestamptz NOT NULL DEFAULT now(),
    UNIQUE (practitioner_id, ccam_code)
);

CREATE INDEX idx_practitioner_favorite_act_practitioner
    ON practitioner_favorite_act (practitioner_id, position);

ALTER TABLE practitioner_favorite_act ENABLE ROW LEVEL SECURITY;
ALTER TABLE practitioner_favorite_act FORCE ROW LEVEL SECURITY;

CREATE POLICY practitioner_favorite_act_tenant_isolation
    ON practitioner_favorite_act
    FOR ALL
    TO nubia_app
    USING      (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid)
    WITH CHECK (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid);

GRANT SELECT, INSERT, UPDATE, DELETE ON practitioner_favorite_act TO nubia_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON practitioner_favorite_act TO nubia_seed;

COMMENT ON TABLE practitioner_favorite_act IS 'Actes CCAM favoris par praticien, pour personnaliser search_ccam_acts. RLS tenant (cabinet_id) ; ownership practitioner_id appliqué côté API. Issue #4111.';
