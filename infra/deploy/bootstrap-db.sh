#!/bin/sh
# Étapes super-user de la base (idempotent) : rôle propriétaire, base nubia,
# extension postgis (untrusted -> créée par le super-user avant les migrations).
# Les rôles nubia_app / nubia_seed sont créés par la migration 0001.
# Exécuté SUR le LXC, parle au conteneur nubia-pg via psql.
set -eu
PG() { podman exec -i nubia-pg psql -v ON_ERROR_STOP=1 -U postgres "$@"; }

PG -tAc "SELECT 1 FROM pg_roles WHERE rolname='nubia_owner'" | grep -qx 1 \
  || PG -c "CREATE ROLE nubia_owner LOGIN CREATEROLE BYPASSRLS;"

PG -tAc "SELECT 1 FROM pg_database WHERE datname='nubia'" | grep -qx 1 \
  || PG -c "CREATE DATABASE nubia OWNER nubia_owner;"

PG -d nubia -c "CREATE EXTENSION IF NOT EXISTS postgis;"
echo "[bootstrap-db] owner + base nubia + postgis OK"
