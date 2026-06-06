-- 0052_create_device.sql
-- Table d'enregistrement des devices pour FCM push notifications.
-- Entité plateforme (liée à app_user, pas de cabinet_id) — RLS user-scoped.
-- Chaque device stocke un token FCM pour recevoir des notifications push.
-- UNIQUE actif partiel (deleted_at IS NULL) : un device actif par (user, platform).
-- Issue : #696

CREATE TABLE device (
    id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    app_user_id       UUID        NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
    fcm_token         TEXT        NOT NULL,
    platform          TEXT        NOT NULL CHECK (platform IN ('ios', 'android', 'web')),
    active            BOOL        NOT NULL DEFAULT true,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at        TIMESTAMPTZ
);

-- Un device actif par (utilisateur, plateforme) ; les devices soft-deletés
-- (deleted_at IS NOT NULL) libèrent la contrainte pour un nouveau device.
CREATE UNIQUE INDEX idx_device_active_platform
    ON device (app_user_id, platform) WHERE deleted_at IS NULL;

GRANT SELECT, INSERT, UPDATE, DELETE ON device TO nubia_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON device TO nubia_seed;

-- RLS : chaque utilisateur ne voit/modifie que ses propres devices.
ALTER TABLE device ENABLE ROW LEVEL SECURITY;
ALTER TABLE device FORCE ROW LEVEL SECURITY;

CREATE POLICY device_owner ON device
    FOR ALL TO nubia_app
    USING (app_user_id = nullif(current_setting('app.current_user_id', true), '')::uuid)
    WITH CHECK (app_user_id = nullif(current_setting('app.current_user_id', true), '')::uuid);

-- nubia_seed : accès complet (données de démo fictives, pas de GUC en seed)
CREATE POLICY device_seed ON device
    FOR ALL TO nubia_seed
    USING (true) WITH CHECK (true);

COMMENT ON TABLE device IS 'Enregistrement des devices pour FCM push notifications. RLS user-scoped (app.current_user_id). Réf. docs/12-api-reference.md §19.';
