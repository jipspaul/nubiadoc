-- 0299_cabinet_invite_link_provider_signature.sql
-- [DP-F25.a] Liens d'invitation par rôle + signature/tampon du praticien (#7149).
--
-- cabinet_invite_link : jusqu'ici seule l'invitation nominative par e-mail
-- existe (app_user.password_hash nullable, migration 0021). Ici on ajoute un
-- lien d'invitation générique par rôle (un admin génère une URL à usage
-- multiple pour recruter des collaborateurs sans connaître leur e-mail à
-- l'avance), avec expiration et quota d'utilisations.
--
-- RLS : contrairement aux autres tables tenant (policy tenant_isolation
-- stricte sur app.current_cabinet_id), la résolution d'un lien par `token`
-- se fait par un visiteur NON authentifié qui n'a pas encore de contexte
-- cabinet (il découvre le cabinet/rôle avant de créer son compte). Un GUC
-- app.current_cabinet_id ne peut donc pas être posé pour cette lecture.
-- Même problème déjà résolu pour account_access_request (migration 0241,
-- invitation nominative d'un proche) : policy nubia_app ouverte, filtrage
-- explicite par les handlers (WHERE cabinet_id = ... pour l'admin, WHERE
-- token = ... pour l'invité). Pas de DELETE pour nubia_app : révocation via
-- expires_at (soft, traçable), jamais un DELETE SQL.
--
-- role reprend l'énumération actuelle de cabinet_membership.role (migration
-- 0098 : practitioner/secretary/admin/manager/doctor) : le rôle du lien doit
-- correspondre à celui qui sera posé sur cabinet_membership à l'acceptation.

CREATE TABLE cabinet_invite_link (
    id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    cabinet_id  uuid        NOT NULL REFERENCES cabinet(id),
    role        text        NOT NULL
                   CHECK (role IN ('practitioner', 'secretary', 'admin', 'manager', 'doctor')),
    token       text        NOT NULL,
    expires_at  timestamptz NOT NULL,
    max_uses    integer     NOT NULL DEFAULT 1 CHECK (max_uses > 0),
    uses        integer     NOT NULL DEFAULT 0 CHECK (uses >= 0),
    created_by  uuid        REFERENCES app_user(id),
    created_at  timestamptz NOT NULL DEFAULT now(),
    revoked_at  timestamptz,
    CONSTRAINT cabinet_invite_link_token_uniq UNIQUE (token),
    CONSTRAINT cabinet_invite_link_uses_within_max CHECK (uses <= max_uses)
);

CREATE INDEX idx_cabinet_invite_link_cabinet_role
    ON cabinet_invite_link (cabinet_id, role);

ALTER TABLE cabinet_invite_link ENABLE ROW LEVEL SECURITY;
ALTER TABLE cabinet_invite_link FORCE ROW LEVEL SECURITY;

-- nubia_app : accès ouvert, filtrage applicatif (cf. commentaire ci-dessus,
-- même choix que account_access_request / migration 0241).
CREATE POLICY cabinet_invite_link_app_all ON cabinet_invite_link
    FOR ALL TO nubia_app
    USING (true) WITH CHECK (true);
REVOKE DELETE ON cabinet_invite_link FROM nubia_app;
GRANT SELECT, INSERT, UPDATE ON cabinet_invite_link TO nubia_app;

-- nubia_seed : accès complet (données de démo fictives)
CREATE POLICY cabinet_invite_link_seed ON cabinet_invite_link
    FOR ALL TO nubia_seed
    USING (true) WITH CHECK (true);
GRANT SELECT, INSERT, UPDATE, DELETE ON cabinet_invite_link TO nubia_seed;

COMMENT ON TABLE cabinet_invite_link IS
    'Lien d''invitation cabinet par rôle (URL à usage multiple, expirable), distinct de l''invitation nominative par e-mail (app_user, migration 0021). RLS ouverte pour nubia_app : filtrage applicatif (token pour l''invité anonyme, cabinet_id pour l''admin). #7149.';
COMMENT ON COLUMN cabinet_invite_link.token IS
    'Jeton opaque inclus dans l''URL d''invitation, résolu sans contexte cabinet (visiteur non authentifié). #7149.';
COMMENT ON COLUMN cabinet_invite_link.max_uses IS
    'Nombre maximal d''acceptations autorisées pour ce lien (uses <= max_uses, contrainte DB). #7149.';
COMMENT ON COLUMN cabinet_invite_link.revoked_at IS
    'Révocation manuelle avant expiration naturelle (soft, traçable — pas de DELETE). #7149.';

-- Signature / tampon du praticien : image uploadée, stockée comme document
-- (mécanisme existant, cf. document.category), référencée depuis le profil
-- provider pour l'apposer sur les documents générés (ordonnances, courriers).
ALTER TABLE document DROP CONSTRAINT document_category_check;
ALTER TABLE document ADD CONSTRAINT document_category_check
    CHECK (category IN (
        'devis', 'facture', 'ordonnance', 'radio', 'cbct', 'photo', 'cr',
        'consigne', 'attestation', 'carte_mutuelle', 'passeport_implantaire',
        'consentement', 'courrier', 'dmsm', 'signature', 'tampon'
    ));

ALTER TABLE provider
    ADD COLUMN signature_image_id uuid REFERENCES document(id),
    ADD COLUMN stamp_image_id     uuid REFERENCES document(id);

COMMENT ON COLUMN provider.signature_image_id IS
    'Image de la signature manuscrite du praticien (document, category=signature), apposée sur les documents générés. #7149.';
COMMENT ON COLUMN provider.stamp_image_id IS
    'Image du tampon du praticien (document, category=tampon), apposée sur les documents générés. #7149.';
