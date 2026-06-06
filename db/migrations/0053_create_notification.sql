-- 0053_create_notification.sql
-- Centre de notifications in-app (patients et pros).
-- Entité plateforme liée à app_user (pas de cabinet_id) — RLS user-scoped.
-- body_ciphertext : contenu chiffré (PII jamais en clair, core/crypto KMS).
-- data jsonb : métadonnées non-PII (type, deeplink, ids).
-- Append-only : pas de DELETE (archivage via read_at / archived_at).
-- Issue : #697

CREATE TABLE notification (
    id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    app_user_id      UUID        NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
    kind             TEXT        NOT NULL,
    title            TEXT        NOT NULL,
    body_ciphertext  BYTEA       NOT NULL,
    body_key_ref     TEXT        NOT NULL,
    data             JSONB       NOT NULL DEFAULT '{}',
    is_read          BOOL        NOT NULL DEFAULT false,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    read_at          TIMESTAMPTZ
);

-- Index principal : récupération des notifications non-lues par utilisateur, tri DESC.
CREATE INDEX idx_notification_user_read_created
    ON notification (app_user_id, is_read, created_at DESC);

GRANT SELECT, INSERT, UPDATE ON notification TO nubia_app;
-- Pas de DELETE pour nubia_app : append-only, archivage via read_at.
-- Les DEFAULT PRIVILEGES de 0001 accordent DELETE à nubia_app sur toute table créée par
-- nubia_owner ; on le révoque explicitement pour garantir l'append-only.
REVOKE DELETE ON notification FROM nubia_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON notification TO nubia_seed;

-- RLS : chaque utilisateur ne voit/modifie que ses propres notifications.
ALTER TABLE notification ENABLE ROW LEVEL SECURITY;
ALTER TABLE notification FORCE ROW LEVEL SECURITY;

-- SELECT borné à l'utilisateur courant.
CREATE POLICY notification_owner_select ON notification
    FOR SELECT TO nubia_app
    USING (app_user_id = nullif(current_setting('app.current_user_id', true), '')::uuid);

-- INSERT borné : on ne peut insérer que pour soi-même.
CREATE POLICY notification_owner_insert ON notification
    FOR INSERT TO nubia_app
    WITH CHECK (app_user_id = nullif(current_setting('app.current_user_id', true), '')::uuid);

-- UPDATE borné : mise à jour du statut de lecture (is_read, read_at).
CREATE POLICY notification_owner_update ON notification
    FOR UPDATE TO nubia_app
    USING  (app_user_id = nullif(current_setting('app.current_user_id', true), '')::uuid)
    WITH CHECK (app_user_id = nullif(current_setting('app.current_user_id', true), '')::uuid);

-- Pas de DELETE policy pour nubia_app (append-only).

-- nubia_seed : accès complet (données de démo fictives, pas de GUC en seed).
CREATE POLICY notification_seed ON notification
    FOR ALL TO nubia_seed
    USING (true) WITH CHECK (true);

COMMENT ON TABLE notification IS 'Notifications in-app (patients et pros). RLS user-scoped (app.current_user_id). body_ciphertext = contenu chiffré (core/crypto KMS). Append-only côté nubia_app. Réf. docs/12-api-reference.md §19.';
