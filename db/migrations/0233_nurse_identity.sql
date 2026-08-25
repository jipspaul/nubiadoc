-- 0233_nurse_identity.sql
-- Nouveau type de tenant « infirmier·ère » (soins à domicile) : socle du flux
-- « demande de visite → infirmière proche accepte » (type Uber v1). Calqué sur
-- le tenant pharmacie (0121) : tables nurse + nurse_membership, RLS fail-closed
-- sur le GUC dédié app.current_nurse_id (jamais app.current_cabinet_id :
-- cloisonnement structurel vis-à-vis des cabinets/pharmacies).
-- Annuaire public : seules les infirmières is_listed sont visibles sans GUC ;
-- is_online + geo alimentent le matching de proximité (ST_DWithin, cf. 0234).
-- Épic : app infirmières (Uber v1) — voir tracking issue.

CREATE TABLE nurse (
    id             UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    display_name   TEXT        NOT NULL,
    adeli          TEXT,                      -- n° ADELI/RPPS infirmier (gate onboarding, cf. provider 0058)
    address        JSONB       NOT NULL DEFAULT '{}',
    geo            geography(Point, 4326),    -- base/position déclarée pour le matching
    service_radius_m INTEGER   NOT NULL DEFAULT 20000,   -- rayon d'intervention (m)
    phone          TEXT,
    settings       JSONB       NOT NULL DEFAULT '{}',
    is_listed      BOOLEAN     NOT NULL DEFAULT false,   -- annuaire public
    is_online      BOOLEAN     NOT NULL DEFAULT false,   -- disponible maintenant (reçoit des offres)
    last_seen_geo  geography(Point, 4326),               -- dernière position heartbeat
    last_seen_at   TIMESTAMPTZ,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at     TIMESTAMPTZ
);

-- Matching de proximité (offres aux infirmières proches, annuaire patient).
CREATE INDEX idx_nurse_geo ON nurse USING GIST (geo);
-- Filtre rapide des candidates dispo à l'insertion d'une demande.
CREATE INDEX idx_nurse_online ON nurse (is_online) WHERE is_online AND deleted_at IS NULL;

CREATE TABLE nurse_membership (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    nurse_id    UUID        NOT NULL REFERENCES nurse(id) ON DELETE CASCADE,
    user_id     UUID        NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
    role        TEXT        NOT NULL CHECK (role IN ('nurse', 'admin')),
    active      BOOLEAN     NOT NULL DEFAULT true,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    left_at     TIMESTAMPTZ,
    UNIQUE (nurse_id, user_id)
);

CREATE INDEX idx_nurse_membership_nurse ON nurse_membership (nurse_id);
CREATE INDEX idx_nurse_membership_user ON nurse_membership (user_id);

GRANT SELECT, INSERT, UPDATE ON nurse TO nubia_app;
GRANT SELECT, INSERT, UPDATE ON nurse_membership TO nubia_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON nurse TO nubia_seed;
GRANT SELECT, INSERT, UPDATE, DELETE ON nurse_membership TO nubia_seed;

ALTER TABLE nurse ENABLE ROW LEVEL SECURITY;
ALTER TABLE nurse FORCE ROW LEVEL SECURITY;
ALTER TABLE nurse_membership ENABLE ROW LEVEL SECURITY;
ALTER TABLE nurse_membership FORCE ROW LEVEL SECURITY;

-- Tenant : une infirmière ne voit et ne modifie qu'elle-même.
CREATE POLICY nurse_self ON nurse
    USING      (id = nullif(current_setting('app.current_nurse_id', true), '')::uuid)
    WITH CHECK (id = nullif(current_setting('app.current_nurse_id', true), '')::uuid);

-- Annuaire public (recherche patient + matching de proximité) : lecture seule
-- des infirmières listées et non supprimées.
CREATE POLICY nurse_public_read ON nurse
    FOR SELECT
    USING (is_listed AND deleted_at IS NULL);

CREATE POLICY nurse_membership_tenant ON nurse_membership
    USING      (nurse_id = nullif(current_setting('app.current_nurse_id', true), '')::uuid)
    WITH CHECK (nurse_id = nullif(current_setting('app.current_nurse_id', true), '')::uuid);

-- Seed démo (données fictives uniquement, cf. barrière G3).
CREATE POLICY nurse_seed_all ON nurse
    TO nubia_seed USING (true) WITH CHECK (true);
CREATE POLICY nurse_membership_seed_all ON nurse_membership
    TO nubia_seed USING (true) WITH CHECK (true);

-- Fonction SECURITY DEFINER : memberships infirmiers actifs d'un utilisateur,
-- en contournant la RLS nurse-scoped (nécessaire pour
-- POST /v1/auth/select-nurse-context avec un token login sans nurse_id).
-- Pattern identique à user_pharmacy_memberships (0122).
CREATE OR REPLACE FUNCTION user_nurse_memberships(p_user_id uuid)
    RETURNS TABLE(nurse_id uuid, role text)
    LANGUAGE sql
    SECURITY DEFINER
    STABLE
    SET search_path = public
AS $$
    SELECT nm.nurse_id, nm.role
    FROM nurse_membership nm
    WHERE nm.user_id = p_user_id
      AND nm.active  = true
    ORDER BY nm.created_at ASC;
$$;

GRANT EXECUTE ON FUNCTION user_nurse_memberships(uuid) TO nubia_app;

COMMENT ON TABLE nurse IS
    'Infirmier·ère (soins à domicile) : tenant dédié (GUC app.current_nurse_id, distinct des tenants cabinet/pharmacie). Annuaire + matching via is_listed/is_online/geo. Épic app infirmières.';
COMMENT ON TABLE nurse_membership IS
    'Appartenance d''un app_user à un tenant infirmier (rôles nurse/admin). RLS nurse-scoped fail-closed. Clone de pharmacy_membership (0121).';
