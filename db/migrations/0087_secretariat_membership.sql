-- 0087_secretariat_membership.sql
-- Table secretariat_membership : rôles du personnel d'un secrétariat (P11, §H.1).
-- Chaque entrée lie un app_user(kind=pro) à un secrétariat via un rôle (secretary/manager).
-- RLS cabinet-scoped (colonne cabinet_id directe, pattern tenant standard).
-- Issue : #1194

CREATE TABLE secretariat_membership (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    cabinet_id      UUID        NOT NULL REFERENCES cabinet(id) ON DELETE CASCADE,
    secretariat_id  UUID        NOT NULL REFERENCES secretariat(id) ON DELETE CASCADE,
    user_id         UUID        NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
    role            TEXT        NOT NULL CHECK (role IN ('secretary', 'manager')),
    active          BOOLEAN     NOT NULL DEFAULT true,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Index tenant-first (liste des membres par cabinet).
CREATE INDEX idx_secretariat_membership_cabinet
    ON secretariat_membership (cabinet_id);

-- Un user ne peut être actif qu'une seule fois dans le même secrétariat.
CREATE UNIQUE INDEX idx_secretariat_membership_unique
    ON secretariat_membership (secretariat_id, user_id)
    WHERE active = true;

GRANT SELECT, INSERT, UPDATE ON secretariat_membership TO nubia_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON secretariat_membership TO nubia_seed;

-- RLS : isolation par cabinet (même pattern que les tables tenant standard).
ALTER TABLE secretariat_membership ENABLE ROW LEVEL SECURITY;
ALTER TABLE secretariat_membership FORCE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON secretariat_membership
    USING      (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid)
    WITH CHECK (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid);

COMMENT ON TABLE secretariat_membership IS 'Rattachement du personnel (kind=pro) à un secrétariat avec rôle secretary/manager. Table tenant (cabinet_id). RLS fail-closed. Réf. P11 PLAN-ATOMIC §H.1.';
