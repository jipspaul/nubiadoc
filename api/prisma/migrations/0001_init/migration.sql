-- Nubia — migration initiale (Bloc A) : schéma multi-tenant + Row-Level Security.
-- ⚠️ Issue critique NUB-T1.2. Voir docs/05 §2 et docs/09.

-- Extensions
CREATE EXTENSION IF NOT EXISTS "pgcrypto";   -- gen_random_uuid()
CREATE EXTENSION IF NOT EXISTS "pg_trgm";    -- recherche floue (sans Meilisearch au MVP)

-- ============================================================
-- Tables
-- ============================================================
CREATE TABLE "cabinet" (
  "id"             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "raison_sociale" text NOT NULL,
  "siret"          char(14),
  "finess"         text,
  "specialite"     text NOT NULL DEFAULT 'dentaire',
  "settings"       jsonb NOT NULL DEFAULT '{}',
  "created_at"     timestamptz NOT NULL DEFAULT now(),
  "updated_at"     timestamptz NOT NULL DEFAULT now(),
  "deleted_at"     timestamptz
);

CREATE TABLE "app_user" (
  "id"            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "email"         text NOT NULL UNIQUE,
  "password_hash" text,
  "mfa_enabled"   boolean NOT NULL DEFAULT false,
  "rpps"          text,
  "adeli"         text,
  "status"        text NOT NULL DEFAULT 'active',
  "created_at"    timestamptz NOT NULL DEFAULT now(),
  "updated_at"    timestamptz NOT NULL DEFAULT now(),
  "deleted_at"    timestamptz
);

CREATE TABLE "cabinet_membership" (
  "id"         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "cabinet_id" uuid NOT NULL REFERENCES "cabinet"("id"),
  "user_id"    uuid NOT NULL REFERENCES "app_user"("id"),
  "role"       text NOT NULL CHECK ("role" IN ('practitioner','secretary','admin')),
  "created_at" timestamptz NOT NULL DEFAULT now(),
  UNIQUE ("cabinet_id", "user_id")
);

CREATE TABLE "patient" (
  "id"         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "cabinet_id" uuid NOT NULL REFERENCES "cabinet"("id"),
  "first_name" text NOT NULL,
  "last_name"  text NOT NULL,
  "birth_date" date,
  "contact"    jsonb NOT NULL DEFAULT '{}',
  "mutuelle"   jsonb NOT NULL DEFAULT '{}',
  "created_at" timestamptz NOT NULL DEFAULT now(),
  "updated_at" timestamptz NOT NULL DEFAULT now(),
  "deleted_at" timestamptz
);
CREATE INDEX "patient_cabinet_id_idx" ON "patient" ("cabinet_id");

-- ============================================================
-- Row-Level Security (isolation par cabinet)
-- Le contexte est posé par TenancyService.withTenant() :
--   SELECT set_config('app.current_cabinet_id', $cabinetId, true)
-- current_setting(..., true) => missing_ok : si non défini -> NULL -> 0 ligne (fail-closed).
-- ============================================================
ALTER TABLE "cabinet_membership" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "cabinet_membership" FORCE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON "cabinet_membership"
  USING ("cabinet_id" = current_setting('app.current_cabinet_id', true)::uuid)
  WITH CHECK ("cabinet_id" = current_setting('app.current_cabinet_id', true)::uuid);

ALTER TABLE "patient" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "patient" FORCE ROW LEVEL SECURITY;
CREATE POLICY "tenant_isolation" ON "patient"
  USING ("cabinet_id" = current_setting('app.current_cabinet_id', true)::uuid)
  WITH CHECK ("cabinet_id" = current_setting('app.current_cabinet_id', true)::uuid);

-- NB : "cabinet" et "app_user" ne portent pas de cabinet_id (cabinet = la racine du tenant,
-- app_user = identité potentiellement multi-cabinets). Leur accès est cadré par le RBAC applicatif
-- et les jointures via cabinet_membership (lui sous RLS).

-- ============================================================
-- Rôle applicatif NON-superuser (ne bypasse PAS la RLS).
-- À créer hors migration en prod (secret), ici pour le POC/CI :
--   CREATE ROLE nubia_app LOGIN PASSWORD '...';
--   GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO nubia_app;
-- IMPORTANT : ne JAMAIS donner BYPASSRLS ni SUPERUSER à ce rôle.
-- ============================================================
