-- 0280_cabinet_correspondent.sql
-- Carnet de correspondants du cabinet (#7195, DP-F8.a).
--
-- Distinct de `patient_correspondent` (0176) et `patient_referring_doctor`
-- (0129) : ces deux tables lient un patient à un correspondant en texte
-- libre (free_name/free_phone/free_address), sans entité partagée au
-- cabinet — impossible de mesurer "combien de patients ce correspondant
-- a-t-il adressés" sans regrouper des chaînes de texte libre.
-- `cabinet_correspondent` est l'annuaire des correspondants DU CABINET
-- (nom, spécialité, coordonnées, RPPS) ; `patient.referred_by_correspondent_id`
-- pointe vers une ligne de cet annuaire pour mesurer les adressages et le
-- CA apporté (nullable : la majorité des patients n'ont pas été adressés).
-- Table tenant (cabinet_id), même pattern RLS que patient_tag (0158).
--
-- FK COMPOSITE (referred_by_correspondent_id, cabinet_id) plutôt qu'une FK
-- simple sur l'id seul : PostgreSQL fait bypasser la RLS aux vérifications
-- d'intégrité référentielle (FK/UNIQUE/PK) même sous FORCE ROW LEVEL
-- SECURITY — même fix standard que 0190/0193/0212 : UNIQUE (id, cabinet_id)
-- sur le parent, un mismatch de cabinet_id ne correspond à aucune ligne de
-- cet index, la FK échoue en 23503 indépendamment de la RLS.

CREATE TABLE cabinet_correspondent (
    id           uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    cabinet_id   uuid        NOT NULL REFERENCES cabinet(id),
    display_name text        NOT NULL,
    specialty    text,
    email        text,
    phone        text,
    address      text,
    rpps         text,
    notes        text,
    created_at   timestamptz NOT NULL DEFAULT now(),
    updated_at   timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT cabinet_correspondent_display_name_not_blank CHECK (btrim(display_name) <> ''),
    CONSTRAINT cabinet_correspondent_id_cabinet_uniq UNIQUE (id, cabinet_id)
);

CREATE INDEX idx_cabinet_correspondent_cabinet
    ON cabinet_correspondent (cabinet_id);

GRANT SELECT, INSERT, UPDATE, DELETE ON cabinet_correspondent TO nubia_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON cabinet_correspondent TO nubia_seed;

-- RLS : isolation par cabinet (même pattern que patient_tag, migration 0158).
ALTER TABLE cabinet_correspondent ENABLE ROW LEVEL SECURITY;
ALTER TABLE cabinet_correspondent FORCE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON cabinet_correspondent
    USING      (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid)
    WITH CHECK (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid);

COMMENT ON TABLE cabinet_correspondent IS 'Carnet de correspondants du cabinet (nom, spécialité, coordonnées, RPPS). Table tenant (cabinet_id). RLS fail-closed. Issue #7195.';

-- Lien « patient adressé par » : nullable, un correspondant du même cabinet.
ALTER TABLE patient ADD COLUMN referred_by_correspondent_id uuid;
ALTER TABLE patient
    ADD CONSTRAINT patient_referred_by_correspondent_cabinet_fkey
    FOREIGN KEY (referred_by_correspondent_id, cabinet_id)
    REFERENCES cabinet_correspondent (id, cabinet_id);

CREATE INDEX idx_patient_referred_by_correspondent
    ON patient (referred_by_correspondent_id) WHERE referred_by_correspondent_id IS NOT NULL;
