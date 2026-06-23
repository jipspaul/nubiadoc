#!/bin/sh
# Charge le seed démo (données fictives, idempotent ON CONFLICT DO NOTHING).
# seed.sql + seed_e2e.sql sous nubia_seed ; seed_slots.sql sous nubia_owner
# (traverse la RLS). Best-effort : un échec n'interrompt pas le déploiement.
set -u
SEED_DIR="${SEED_DIR:-/opt/nubia/seed}"
run() { # role, file
  [ -f "$SEED_DIR/$2" ] || return 0
  echo "[seed] $2 (role $1)"
  podman exec -i nubia-pg psql -v ON_ERROR_STOP=1 -U "$1" -d nubia < "$SEED_DIR/$2" \
    || echo "[seed] $2 a échoué (non bloquant)"
}
run nubia_seed  seed.sql
run nubia_seed  seed_e2e.sql
run nubia_owner seed_slots.sql
echo "[seed] terminé"
