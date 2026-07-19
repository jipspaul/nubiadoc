-- 0149_interop_subscription.sql
-- Sync sortante FHIR (lot A7) : abonnements partenaires (interop_subscription)
-- et journal de livraison (interop_delivery) pour les notifications HMAC
-- déclenchées après écriture d'une ressource FHIR (Appointment pour ce lot,
-- cf. api/src/interop/appointment.rs::create_appointment/update_appointment_status).
--
-- `criteria` est un simple filtre "type de ressource" (ex. 'Appointment'),
-- PAS un critère de recherche FHIR complet — hors scope de ce lot.
--
-- Secret partagé (colonne secret_hash) : PAS un hash argon2 comme
-- interop_client_secret (migration 0148). Argon2 convient à un secret que
-- Nubia ne fait que VÉRIFIER (le client_secret soumis par le partenaire à
-- /oauth/token) : un hash à sens unique suffit. Ici c'est l'INVERSE : c'est
-- NUBIA qui doit SIGNER (HMAC-SHA256) chaque livraison sortante avec CE
-- secret exact — un hash à sens unique rendrait toute signature impossible
-- dès la deuxième livraison (bug de correction silencieux). Choix retenu
-- (cf. api/src/interop/subscription.rs, derive_subscription_secret) : le
-- secret n'est JAMAIS stocké (ni en clair, ni chiffré) — il est re-dérivé à
-- la demande via HMAC-SHA256(clé serveur INTEROP_SIGNING_KEY,
-- subscription.id), fonction déterministe de l'id (immuable) de
-- l'abonnement. `secret_hash` stocke un hash argon2 de ce secret dérivé,
-- à des fins d'audit/défense uniquement (jamais lu sur le chemin de
-- signature) — le nom de colonne reste celui prévu par le schéma du lot.

CREATE TABLE interop_subscription (
    id           uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    cabinet_id   uuid        NOT NULL REFERENCES cabinet(id),
    criteria     text        NOT NULL,
    endpoint_url text        NOT NULL,
    secret_hash  text        NOT NULL,
    status       text        NOT NULL DEFAULT 'active'
                     CHECK (status IN ('active', 'disabled')),
    created_at   timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_interop_subscription_cabinet ON interop_subscription (cabinet_id);
CREATE INDEX idx_interop_subscription_active_criteria
    ON interop_subscription (cabinet_id, criteria)
    WHERE status = 'active';

REVOKE ALL ON interop_subscription FROM nubia_app;
GRANT SELECT, INSERT, UPDATE ON interop_subscription TO nubia_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON interop_subscription TO nubia_seed;

ALTER TABLE interop_subscription ENABLE ROW LEVEL SECURITY;
ALTER TABLE interop_subscription FORCE ROW LEVEL SECURITY;

CREATE POLICY interop_subscription_tenant_isolation ON interop_subscription
    FOR ALL TO nubia_app
    USING (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid)
    WITH CHECK (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid);

CREATE POLICY interop_subscription_seed_all ON interop_subscription
    TO nubia_seed USING (true) WITH CHECK (true);

COMMENT ON TABLE interop_subscription IS
    'Abonnement partenaire FHIR rest-hook (lot A7). criteria = filtre simple type de ressource (pas de FHIR search complet). secret_hash = hash argon2 défensif, PAS le secret de signature (re-dérivé, cf. commentaire de migration et api/src/interop/subscription.rs).';

-- interop_delivery : pas de cabinet_id direct — RLS via jointure sur
-- interop_subscription, même pattern que interop_client_secret (migration
-- 0148, qui remonte vers interop_client).
CREATE TABLE interop_delivery (
    id              uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    subscription_id uuid        NOT NULL REFERENCES interop_subscription(id),
    resource_type   text        NOT NULL,
    resource_id     uuid        NOT NULL,
    status          text        NOT NULL DEFAULT 'pending'
                        CHECK (status IN ('pending', 'delivered', 'failed')),
    attempts        int         NOT NULL DEFAULT 0,
    last_error      text,
    next_attempt_at timestamptz,
    created_at      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_interop_delivery_subscription ON interop_delivery (subscription_id);

REVOKE ALL ON interop_delivery FROM nubia_app;
GRANT SELECT, INSERT, UPDATE ON interop_delivery TO nubia_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON interop_delivery TO nubia_seed;

ALTER TABLE interop_delivery ENABLE ROW LEVEL SECURITY;
ALTER TABLE interop_delivery FORCE ROW LEVEL SECURITY;

CREATE POLICY interop_delivery_tenant_isolation ON interop_delivery
    FOR ALL TO nubia_app
    USING (
        subscription_id IN (
            SELECT id FROM interop_subscription
            WHERE cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid
        )
    )
    WITH CHECK (
        subscription_id IN (
            SELECT id FROM interop_subscription
            WHERE cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid
        )
    );

CREATE POLICY interop_delivery_seed_all ON interop_delivery
    TO nubia_seed USING (true) WITH CHECK (true);

COMMENT ON TABLE interop_delivery IS
    'Journal de livraison HMAC des notifications sortantes (lot A7) — statut/attempts/next_attempt_at pensés pour un futur worker de retry (non implémenté dans cette tranche : livraison synchrone best-effort à l''enqueue, cf. api/src/interop/subscription.rs).';
