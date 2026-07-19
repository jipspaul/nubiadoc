-- 0148_interop_client.sql
-- Socle auth partenaire OAuth2 (lot A1, interop FHIR/HL7v2) : identifie les
-- clients machine-à-machine (grant client_credentials) autorisés à consommer
-- l'API partenaire /v1/interop/*. Un interop_client appartient à UN cabinet ;
-- ses secrets (interop_client_secret) vivent dans une table enfant pour
-- permettre la rotation (insert nouveau secret actif + not_after sur
-- l'ancien) sans jamais stocker le secret en clair (argon2, cf. crate
-- integrations-interop).
--
-- interop_client_find_by_client_id() / interop_client_secret_find_active() :
-- lookups SECURITY DEFINER pour POST /v1/interop/oauth/token, appelés AVANT
-- que le GUC app.current_cabinet_id ne soit posé (pas encore de tenant connu
-- à ce stade — même précédent que payment_find_by_provider_ref, migration
-- 0103, et quote_find_by_id, migration 0133).

CREATE TABLE interop_client (
    id           uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    client_id    text        NOT NULL UNIQUE,
    cabinet_id   uuid        NOT NULL REFERENCES cabinet(id),
    display_name text        NOT NULL,
    scopes       text[]      NOT NULL,
    status       text        NOT NULL DEFAULT 'active'
                     CHECK (status IN ('active', 'revoked')),
    created_at   timestamptz NOT NULL DEFAULT now(),
    created_by   uuid
);

CREATE INDEX idx_interop_client_cabinet ON interop_client (cabinet_id);

REVOKE ALL ON interop_client FROM nubia_app;
GRANT SELECT, INSERT, UPDATE ON interop_client TO nubia_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON interop_client TO nubia_seed;

ALTER TABLE interop_client ENABLE ROW LEVEL SECURITY;
ALTER TABLE interop_client FORCE ROW LEVEL SECURITY;

CREATE POLICY interop_client_tenant_isolation ON interop_client
    FOR ALL TO nubia_app
    USING (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid)
    WITH CHECK (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid);

CREATE POLICY interop_client_seed_all ON interop_client
    TO nubia_seed USING (true) WITH CHECK (true);

COMMENT ON TABLE interop_client IS
    'Client OAuth2 (client_credentials) partenaire FHIR/HL7v2, scoping cabinet. Lot A1.';

-- Table enfant : secrets hashés (argon2), rotation par insert + not_after sur
-- l'ancien. Pas de cabinet_id direct — la RLS remonte via une jointure sur
-- interop_client (même pattern que la policy cabinet_patient_read /
-- migration 0035, qui remonte de patient vers cabinet).
CREATE TABLE interop_client_secret (
    id            uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    client_id_ref uuid        NOT NULL REFERENCES interop_client(id),
    secret_hash   text        NOT NULL,
    status        text        NOT NULL DEFAULT 'active'
                      CHECK (status IN ('active', 'retired')),
    not_after     timestamptz,
    created_at    timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_interop_client_secret_client ON interop_client_secret (client_id_ref);

REVOKE ALL ON interop_client_secret FROM nubia_app;
GRANT SELECT, INSERT, UPDATE ON interop_client_secret TO nubia_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON interop_client_secret TO nubia_seed;

ALTER TABLE interop_client_secret ENABLE ROW LEVEL SECURITY;
ALTER TABLE interop_client_secret FORCE ROW LEVEL SECURITY;

CREATE POLICY interop_client_secret_tenant_isolation ON interop_client_secret
    FOR ALL TO nubia_app
    USING (
        client_id_ref IN (
            SELECT id FROM interop_client
            WHERE cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid
        )
    )
    WITH CHECK (
        client_id_ref IN (
            SELECT id FROM interop_client
            WHERE cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid
        )
    );

CREATE POLICY interop_client_secret_seed_all ON interop_client_secret
    TO nubia_seed USING (true) WITH CHECK (true);

COMMENT ON TABLE interop_client_secret IS
    'Secrets hashés (argon2) d''un interop_client — rotation par insert + not_after. RLS via jointure interop_client (lot A1).';

-- SECURITY DEFINER : lookup par client_id, appelé hors contexte tenant (avant
-- l'émission du JWT interop, donc avant que app.current_cabinet_id existe).
-- STABLE, search_path figé, lecture seule.
CREATE OR REPLACE FUNCTION interop_client_find_by_client_id(p_client_id text)
RETURNS interop_client
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
    SELECT * FROM interop_client
    WHERE client_id = p_client_id
    LIMIT 1;
$$;

GRANT EXECUTE ON FUNCTION interop_client_find_by_client_id(text) TO nubia_app;

-- SECURITY DEFINER : secrets actifs (non retirés, non expirés) d'un client —
-- appelé juste après interop_client_find_by_client_id, donc encore hors
-- contexte tenant. Plusieurs lignes possibles en fenêtre de rotation.
CREATE OR REPLACE FUNCTION interop_client_secret_find_active(p_client_id_ref uuid)
RETURNS SETOF interop_client_secret
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
    SELECT * FROM interop_client_secret
    WHERE client_id_ref = p_client_id_ref
      AND status = 'active'
      AND (not_after IS NULL OR not_after > now())
    ORDER BY created_at DESC;
$$;

GRANT EXECUTE ON FUNCTION interop_client_secret_find_active(uuid) TO nubia_app;
