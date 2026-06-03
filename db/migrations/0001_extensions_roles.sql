-- 0001_extensions_roles.sql
-- Extensions, rôles PostgreSQL et grants de base.
-- Réf. : docs/05 §1-§2, §9 ; db/README.md §3, §9 ; db/migrations/README.md.
--
-- Exécuté par nubia_owner (propriétaire du schéma). nubia_owner doit avoir
-- l'attribut CREATEROLE (posé au bootstrap, hors migration : cf. Makefile `reset`).
-- Forward-only : aucune section `down`.

-- ---------------------------------------------------------------------------
-- Extensions
-- ---------------------------------------------------------------------------
-- gen_random_uuid(), digest(), etc.
CREATE EXTENSION IF NOT EXISTS pgcrypto;
-- emails insensibles à la casse
CREATE EXTENSION IF NOT EXISTS citext;
-- recherche floue (noms patients, annuaire) : GIN trigram
CREATE EXTENSION IF NOT EXISTS pg_trgm;
-- géo marketplace (geography Point 4326, ST_DWithin…)
CREATE EXTENSION IF NOT EXISTS postgis;
-- requis par la contrainte d'exclusion d'appointment (opérateur `=` sur uuid
-- dans un index GiST, combiné au && sur tstzrange) — cf. 0005.
CREATE EXTENSION IF NOT EXISTS btree_gist;

-- ---------------------------------------------------------------------------
-- Rôles
--   nubia_owner : propriétaire du schéma, exécute le DDL (déjà créé au bootstrap).
--   nubia_app   : rôle applicatif runtime — NOSUPERUSER + NOBYPASSRLS (RLS effective).
--   nubia_seed  : chargement du seed démo (données fictives), isolé.
-- Création idempotente : les mots de passe ne sont JAMAIS dans les migrations
-- (trust en local/CI, secrets injectés hors-bande en staging/prod — db/README §3, §12).
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'nubia_app') THEN
    CREATE ROLE nubia_app LOGIN NOSUPERUSER NOBYPASSRLS NOCREATEDB NOCREATEROLE;
  ELSE
    ALTER ROLE nubia_app NOSUPERUSER NOBYPASSRLS NOCREATEDB NOCREATEROLE;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'nubia_seed') THEN
    CREATE ROLE nubia_seed LOGIN NOSUPERUSER NOBYPASSRLS NOCREATEDB NOCREATEROLE;
  ELSE
    ALTER ROLE nubia_seed NOSUPERUSER NOBYPASSRLS NOCREATEDB NOCREATEROLE;
  END IF;
END
$$;

-- ---------------------------------------------------------------------------
-- Grants de base : accès au schéma public, droits par défaut sur les futurs objets.
-- Les objets créés par nubia_owner accorderont automatiquement les droits ci-dessous
-- à nubia_app / nubia_seed (ALTER DEFAULT PRIVILEGES s'applique aux objets FUTURS,
-- donc avant toute table — créées en 0002+).
-- ---------------------------------------------------------------------------
GRANT USAGE ON SCHEMA public TO nubia_app, nubia_seed;

-- nubia_app : CRUD métier (la RLS borne ensuite les lignes ; audit_log sera
-- restreint à INSERT en 0008). Les exceptions (append-only) sont posées plus tard.
ALTER DEFAULT PRIVILEGES FOR ROLE nubia_owner IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO nubia_app;
ALTER DEFAULT PRIVILEGES FOR ROLE nubia_owner IN SCHEMA public
  GRANT USAGE, SELECT ON SEQUENCES TO nubia_app;

-- nubia_seed : écriture pour charger la démo (jamais en prod sur données réelles).
ALTER DEFAULT PRIVILEGES FOR ROLE nubia_owner IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO nubia_seed;
ALTER DEFAULT PRIVILEGES FOR ROLE nubia_owner IN SCHEMA public
  GRANT USAGE, SELECT ON SEQUENCES TO nubia_seed;
