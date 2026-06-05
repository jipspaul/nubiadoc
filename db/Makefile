# db/Makefile — gestion de la base Nubia (PostgreSQL 16).
# NE LANCE AUCUN CONTENEUR : opère sur le Postgres déjà fourni par l'environnement
# (cf. db/README §10, SCHEMA.md). Une seule commande, identique en local et en CI : `make test`.
#
# Connexions (surchageables) :
#   ADMIN_*        superuser : (ré)initialise base + rôle owner + extension postgis (untrusted)
#   DATABASE_URL   nubia_owner : exécute les migrations (DDL)
#   APP_DATABASE_URL  nubia_app : RUNTIME + tests RLS (NOSUPERUSER, NOBYPASSRLS)
#   SEED_DATABASE_URL nubia_seed : chargement du seed démo
#
# Auth : en local/CI on s'appuie sur `trust` (pas de mot de passe en clair, jamais en git).
# En staging/prod, les secrets sont injectés hors-bande (db/README §3, §12).

PGHOST     ?= localhost
PGPORT     ?= 5432
DB_NAME    ?= nubia
ADMIN_USER ?= postgres

ADMIN_PSQL = psql -v ON_ERROR_STOP=1 --no-psqlrc -h $(PGHOST) -p $(PGPORT) -U $(ADMIN_USER)

DATABASE_URL      ?= postgres://nubia_owner@$(PGHOST):$(PGPORT)/$(DB_NAME)
APP_DATABASE_URL  ?= postgres://nubia_app@$(PGHOST):$(PGPORT)/$(DB_NAME)
SEED_DATABASE_URL ?= postgres://nubia_seed@$(PGHOST):$(PGPORT)/$(DB_NAME)

MIGRATIONS_DIR = migrations
TESTS_DIR      = tests

.DEFAULT_GOAL := help
.PHONY: help reset migrate seed test verify-rls lint pgtap-install psql-app

help: ## Affiche cette aide
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
	  | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

## ---------------------------------------------------------------------------
## reset — (re)crée une base/schéma propre + rôle owner + postgis (étape admin).
##   postgis est une extension UNTRUSTED : seule l'étape admin peut l'installer.
##   Les rôles nubia_app/nubia_seed sont créés ENSUITE par la migration 0001.
## ---------------------------------------------------------------------------
reset: ## Détruit et recrée une base propre (admin)
	$(ADMIN_PSQL) -d postgres -c "DROP DATABASE IF EXISTS $(DB_NAME) WITH (FORCE);"
	$(ADMIN_PSQL) -d postgres -c "DROP ROLE IF EXISTS nubia_app;"
	$(ADMIN_PSQL) -d postgres -c "DROP ROLE IF EXISTS nubia_seed;"
	$(ADMIN_PSQL) -d postgres -c "DROP ROLE IF EXISTS nubia_owner;"
	$(ADMIN_PSQL) -d postgres -c "CREATE ROLE nubia_owner LOGIN CREATEROLE BYPASSRLS;"
	$(ADMIN_PSQL) -d postgres -c "CREATE DATABASE $(DB_NAME) OWNER nubia_owner;"
	$(ADMIN_PSQL) -d $(DB_NAME) -c "CREATE EXTENSION IF NOT EXISTS postgis;"
	@echo "✓ base $(DB_NAME) recréée (owner=nubia_owner, postgis provisionné)"

## ---------------------------------------------------------------------------
## migrate — applique toutes les migrations en tant que nubia_owner.
## ---------------------------------------------------------------------------
migrate: ## Applique les migrations (sqlx, rôle owner)
	sqlx migrate run --source $(MIGRATIONS_DIR) --database-url "$(DATABASE_URL)"
	@echo "✓ migrations appliquées (source unique : $(MIGRATIONS_DIR))"

## ---------------------------------------------------------------------------
## seed — charge le jeu démo déterministe (rôle seed).
## ---------------------------------------------------------------------------
seed: ## Charge le seed démo fictif (rôle seed)
	psql -v ON_ERROR_STOP=1 --no-psqlrc -h $(PGHOST) -p $(PGPORT) -U nubia_seed -d $(DB_NAME) -f seed/seed.sql
	@echo "✓ seed chargé"

## ---------------------------------------------------------------------------
## pgtap-install — installe l'extension pgTAP (étape admin : pgtap est untrusted).
## ---------------------------------------------------------------------------
pgtap-install:
	$(ADMIN_PSQL) -d $(DB_NAME) -c "CREATE EXTENSION IF NOT EXISTS pgtap;"

## ---------------------------------------------------------------------------
## test — LE contrat : reset → migrate → pgTAP → pg_prove SOUS nubia_app.
##   Tourne tel quel en local et en CI.
## ---------------------------------------------------------------------------
test: reset migrate pgtap-install ## reset+migrate+pgTAP puis lance les tests sous nubia_app
	pg_prove --ext .sql -h $(PGHOST) -p $(PGPORT) -U nubia_app -d $(DB_NAME) $(TESTS_DIR)/*.sql
	@echo "✓ tests pgTAP OK (sous nubia_app)"

## ---------------------------------------------------------------------------
## verify-rls — vérifie l'effectivité de la RLS (rôle + non-fuite).
## ---------------------------------------------------------------------------
verify-rls: ## Vérifie nubia_app non-superuser/non-bypass + non-fuite
	@echo "→ attributs du rôle nubia_app (attendu : f | f) :"
	@$(ADMIN_PSQL) -d $(DB_NAME) -tAc \
	  "SELECT rolsuper, rolbypassrls FROM pg_roles WHERE rolname='nubia_app';" \
	  | grep -qx 'f|f' && echo "  ✓ nubia_app NOSUPERUSER + NOBYPASSRLS" \
	  || (echo "  ✗ nubia_app bypasserait la RLS !" && exit 1)
	pg_prove --ext .sql -h $(PGHOST) -p $(PGPORT) -U nubia_app -d $(DB_NAME) \
	  $(TESTS_DIR)/03_rls.sql $(TESTS_DIR)/04_rls_coverage.sql

## ---------------------------------------------------------------------------
## lint — SQL (sqlfluff si présent) + garde-fou « table tenant sans policy ».
##   Le garde-fou suppose une base migrée (lance `make migrate` avant si besoin).
## ---------------------------------------------------------------------------
lint: ## Lint SQL + check tables tenant sans policy
	@command -v sqlfluff >/dev/null 2>&1 \
	  && sqlfluff lint $(MIGRATIONS_DIR) --dialect postgres \
	  || echo "… sqlfluff absent : lint SQL ignoré (installez sqlfluff pour l'activer)"
	@echo "→ garde-fou : tables avec cabinet_id sans RLS+policy (attendu : aucune) :"
	@$(ADMIN_PSQL) -d $(DB_NAME) -tAc "\
	  SELECT coalesce(string_agg(c.relname, ', '), 'AUCUNE') \
	  FROM pg_class c \
	  JOIN pg_namespace n ON n.oid=c.relnamespace AND n.nspname='public' \
	  JOIN pg_attribute a ON a.attrelid=c.oid AND a.attname='cabinet_id' AND NOT a.attisdropped \
	  WHERE c.relkind IN ('r','p') AND NOT c.relispartition \
	    AND (c.relrowsecurity=false \
	         OR NOT EXISTS (SELECT 1 FROM pg_policies p WHERE p.schemaname='public' AND p.tablename=c.relname));" \
	  | grep -qx 'AUCUNE' && echo "  ✓ couverture RLS complète" \
	  || (echo "  ✗ table(s) tenant sans policy ci-dessus" && exit 1)

psql-app: ## Ouvre un psql sous nubia_app (debug RLS)
	psql "$(APP_DATABASE_URL)"
