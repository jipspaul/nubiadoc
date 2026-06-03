-- 0002_cabinet_identity.sql
-- Cabinet & identité : cabinet, app_user, cabinet_membership, practitioner.
-- Réf. : docs/05 §5.1.
-- RLS posée en 0011 (les tables tenant sont créées ici, sécurisées là-bas).

-- Le tenant racine. Pas de cabinet_id (il EST le tenant) ; isolé en 0011 via id = GUC.
CREATE TABLE cabinet (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  raison_sociale text NOT NULL,
  siret          char(14),
  finess         text,
  specialite     text NOT NULL DEFAULT 'dentaire',
  settings       jsonb NOT NULL DEFAULT '{}',   -- horaires, branding, options, infos pratiques
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now(),
  deleted_at     timestamptz
);

-- Identité globale (un user peut appartenir à plusieurs cabinets). "user" est réservé.
-- Entité plateforme : pas de cabinet_id, pas de RLS cabinet.
CREATE TABLE app_user (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email         citext UNIQUE NOT NULL,
  password_hash text,                 -- null si auth externe (PSC/FranceConnect, post-MVP)
  mfa_enabled   boolean NOT NULL DEFAULT false,
  mfa_secret    text,
  rpps          text,
  adeli         text,
  status        text NOT NULL DEFAULT 'active'
                  CHECK (status IN ('active','suspended','disabled')),
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now(),
  deleted_at    timestamptz
);

-- N-N user <-> cabinet, avec rôle (RBAC applicatif au-dessus de la RLS).
CREATE TABLE cabinet_membership (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cabinet_id  uuid NOT NULL REFERENCES cabinet(id),
  user_id     uuid NOT NULL REFERENCES app_user(id),
  role        text NOT NULL CHECK (role IN ('practitioner','secretary','admin')),
  permissions jsonb NOT NULL DEFAULT '{}',
  created_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (cabinet_id, user_id)
);

CREATE TABLE practitioner (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cabinet_id  uuid NOT NULL REFERENCES cabinet(id),
  user_id     uuid NOT NULL REFERENCES app_user(id),
  rpps        text,
  specialite  text,
  conventions jsonb NOT NULL DEFAULT '{}',
  created_at  timestamptz NOT NULL DEFAULT now()
);
