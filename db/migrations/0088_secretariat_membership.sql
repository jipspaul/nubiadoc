-- 0088_secretariat_membership.sql
-- Table secretariat_membership : rattache un utilisateur à un secrétariat avec un rôle.
-- Fondement du cloisonnement intra-établissement (PLAN-ATOMIC §H P11) : une secrétaire
-- ne voit que les docteurs/patients du secrétariat auquel elle est rattachée.
-- RLS cabinet-scoped via secretariat.cabinet_id (EXISTS subquery, même pattern que
-- provider_secretariat / 0087).
-- Issue : #1200

CREATE TABLE secretariat_membership (
    id             UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    secretariat_id UUID        NOT NULL REFERENCES secretariat(id),
    user_id        UUID        NOT NULL REFERENCES app_user(id),
    role           TEXT        NOT NULL CHECK (role IN ('secretary', 'manager')),
    active         BOOLEAN     NOT NULL DEFAULT true,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Un seul lien actif par couple (user, secretariat).
-- Les entrées inactives (révocations) ne sont pas contraintes → audit trail.
CREATE UNIQUE INDEX idx_secretariat_membership_unique_active
    ON secretariat_membership (secretariat_id, user_id)
    WHERE active;

-- Index tenant-first : liste des membres d'un secrétariat.
CREATE INDEX idx_secretariat_membership_secretariat
    ON secretariat_membership (secretariat_id);

GRANT SELECT, INSERT, UPDATE ON secretariat_membership TO nubia_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON secretariat_membership TO nubia_seed;

-- RLS : isolation cabinet via secretariat.cabinet_id.
-- La RLS sur secretariat s'applique au subquery → cohérence garantie sans cabinet_id direct.
ALTER TABLE secretariat_membership ENABLE ROW LEVEL SECURITY;
ALTER TABLE secretariat_membership FORCE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON secretariat_membership
    USING (
        EXISTS (
            SELECT 1 FROM secretariat s
            WHERE s.id = secretariat_membership.secretariat_id
              AND s.cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM secretariat s
            WHERE s.id = secretariat_membership.secretariat_id
              AND s.cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid
        )
    );

COMMENT ON TABLE secretariat_membership IS 'Membre d''un secrétariat (multi-établissement §H). Lie un app_user à un secretariat avec un rôle (secretary/manager). RLS cabinet-scoped via secretariat.cabinet_id. active=false = révocation sans DELETE. Réf. P11 PLAN-ATOMIC.';
