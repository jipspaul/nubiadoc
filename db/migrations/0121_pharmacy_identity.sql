-- 0121_pharmacy_identity.sql
-- Nouveau type de tenant « pharmacie » : socle du flux click-and-collect.
-- Tables pharmacy + pharmacy_membership, RLS fail-closed sur le GUC dédié
-- app.current_pharmacy_id (jamais app.current_cabinet_id : cloisonnement
-- structurel vis-à-vis des cabinets, cf. docs/07-conformite.md §4).
-- Annuaire public : seules les pharmacies is_listed sont visibles sans GUC.
-- Issue : #3306

CREATE TABLE pharmacy (
    id             UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    raison_sociale TEXT        NOT NULL,
    siret          CHAR(14),
    finess         TEXT,
    address        JSONB       NOT NULL DEFAULT '{}',
    geo            geography(Point, 4326),
    phone          TEXT,
    settings       JSONB       NOT NULL DEFAULT '{}',
    is_listed      BOOLEAN     NOT NULL DEFAULT false,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at     TIMESTAMPTZ
);

-- Recherche de proximité (annuaire patient/praticien).
CREATE INDEX idx_pharmacy_geo ON pharmacy USING GIST (geo);

CREATE TABLE pharmacy_membership (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    pharmacy_id UUID        NOT NULL REFERENCES pharmacy(id) ON DELETE CASCADE,
    user_id     UUID        NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
    role        TEXT        NOT NULL CHECK (role IN ('pharmacist', 'preparator', 'admin')),
    active      BOOLEAN     NOT NULL DEFAULT true,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    left_at     TIMESTAMPTZ,
    UNIQUE (pharmacy_id, user_id)
);

CREATE INDEX idx_pharmacy_membership_pharmacy ON pharmacy_membership (pharmacy_id);
CREATE INDEX idx_pharmacy_membership_user ON pharmacy_membership (user_id);

GRANT SELECT, INSERT, UPDATE ON pharmacy TO nubia_app;
GRANT SELECT, INSERT, UPDATE ON pharmacy_membership TO nubia_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON pharmacy TO nubia_seed;
GRANT SELECT, INSERT, UPDATE, DELETE ON pharmacy_membership TO nubia_seed;

ALTER TABLE pharmacy ENABLE ROW LEVEL SECURITY;
ALTER TABLE pharmacy FORCE ROW LEVEL SECURITY;
ALTER TABLE pharmacy_membership ENABLE ROW LEVEL SECURITY;
ALTER TABLE pharmacy_membership FORCE ROW LEVEL SECURITY;

-- Tenant : une pharmacie ne voit et ne modifie qu'elle-même.
CREATE POLICY pharmacy_self ON pharmacy
    USING      (id = nullif(current_setting('app.current_pharmacy_id', true), '')::uuid)
    WITH CHECK (id = nullif(current_setting('app.current_pharmacy_id', true), '')::uuid);

-- Annuaire public (recherche patient/praticien) : lecture seule des pharmacies listées.
CREATE POLICY pharmacy_public_read ON pharmacy
    FOR SELECT
    USING (is_listed AND deleted_at IS NULL);

CREATE POLICY pharmacy_membership_tenant ON pharmacy_membership
    USING      (pharmacy_id = nullif(current_setting('app.current_pharmacy_id', true), '')::uuid)
    WITH CHECK (pharmacy_id = nullif(current_setting('app.current_pharmacy_id', true), '')::uuid);

-- Seed démo (données fictives uniquement, cf. barrière G3).
CREATE POLICY pharmacy_seed_all ON pharmacy
    TO nubia_seed USING (true) WITH CHECK (true);
CREATE POLICY pharmacy_membership_seed_all ON pharmacy_membership
    TO nubia_seed USING (true) WITH CHECK (true);

COMMENT ON TABLE pharmacy IS
    'Pharmacie : tenant dédié (GUC app.current_pharmacy_id, distinct du tenant cabinet). Annuaire public via is_listed. Réf. épic #3323.';
COMMENT ON TABLE pharmacy_membership IS
    'Appartenance d''un app_user à une pharmacie (rôles pharmacist/preparator/admin). RLS pharmacy-scoped fail-closed.';
