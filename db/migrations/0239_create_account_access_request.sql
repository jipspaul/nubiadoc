-- 0239_create_account_access_request.sql
-- Invitation d'un proche ADULTE (#6119) — distinct de account_guardianship (0010/0025)
-- qui gère les dépendants MINEURS via un compte géré sans mot de passe. Ici les deux
-- comptes existent déjà séparément : le titulaire invite un proche à consulter ses
-- propres données (scope de droits explicite), le proche accepte/refuse/révoque.
--
-- `id` sert de jeton de capability pour l'invité tant qu'il n'est pas lié
-- (invitee_account_id) : même logique que les jetons d'invitation cabinet/reset
-- mot de passe déjà utilisés ailleurs dans l'API (§07), le filtrage par compte
-- reste applicatif (RLS ouverte pour nubia_app, cf. policy plus bas) plutôt que
-- basé sur un GUC — un GET sur `app.current_account_id` ne suffirait pas à
-- l'invité tant que le lien n'est pas établi.
-- Issue : #6119

CREATE TABLE account_access_request (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  requester_account_id  uuid NOT NULL REFERENCES patient_account(id),
  invitee_account_id    uuid REFERENCES patient_account(id),
  first_name            text NOT NULL,
  last_name             text NOT NULL,
  relationship          text NOT NULL CHECK (relationship IN ('enfant', 'conjoint', 'autre')),
  channel               text NOT NULL CHECK (channel IN ('email', 'sms')),
  email                 text,
  phone                 text,
  scope                 text[] NOT NULL DEFAULT '{}',
  status                text NOT NULL DEFAULT 'envoyee'
                           CHECK (status IN ('envoyee', 'acceptee', 'refusee', 'expiree')),
  sent_at               timestamptz NOT NULL DEFAULT now(),
  decided_at            timestamptz,
  revoked_at            timestamptz,
  cancelled_at          timestamptz,
  created_at            timestamptz NOT NULL DEFAULT now(),
  updated_at            timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT access_request_not_self CHECK (invitee_account_id IS NULL OR invitee_account_id <> requester_account_id),
  CONSTRAINT access_request_channel_target CHECK (
    (channel = 'email' AND email IS NOT NULL) OR (channel = 'sms' AND phone IS NOT NULL)
  )
);

-- Liste des demandes envoyées par un titulaire (GET /v1/account/access-requests).
CREATE INDEX idx_access_request_requester ON account_access_request (requester_account_id);
-- Résolution du lien invité une fois établi (accept/refuse/revoke).
CREATE INDEX idx_access_request_invitee ON account_access_request (invitee_account_id)
  WHERE invitee_account_id IS NOT NULL;

GRANT SELECT, INSERT, UPDATE ON account_access_request TO nubia_app;
-- Pas de DELETE pour nubia_app : append-only comme account_guardianship (§07 §10),
-- l'annulation passe par cancelled_at (soft-delete), jamais un DELETE SQL.
REVOKE DELETE ON account_access_request FROM nubia_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON account_access_request TO nubia_seed;

ALTER TABLE account_access_request ENABLE ROW LEVEL SECURITY;
ALTER TABLE account_access_request FORCE ROW LEVEL SECURITY;

-- nubia_app : accès applicatif complet, contrôle fin fait par les handlers
-- (WHERE requester_account_id / invitee_account_id explicite dans chaque requête)
-- — même choix que account_guardianship pour l'écriture (migration 0025) ; élargi
-- ici au SELECT aussi car l'invité doit pouvoir résoudre une demande par `id`
-- (jeton reçu hors-bande) avant même d'être lié via invitee_account_id.
CREATE POLICY access_request_app_all ON account_access_request
  FOR ALL TO nubia_app
  USING (true) WITH CHECK (true);

-- nubia_seed : accès complet (données de démo fictives)
CREATE POLICY access_request_seed ON account_access_request
  FOR ALL TO nubia_seed
  USING (true) WITH CHECK (true);
