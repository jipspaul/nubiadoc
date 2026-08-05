#!/bin/sh
# Applique /opt/nubia/migrations/*.sql dans l'ordre, sous nubia_owner, de façon
# idempotente. Suivi via _sqlx_migrations (version = préfixe numérique du
# fichier) : une migration déjà appliquée est sautée.
set -eu
MIG_DIR="${MIG_DIR:-/opt/nubia/migrations}"
PG() { podman exec -i nubia-pg psql -v ON_ERROR_STOP=1 -U nubia_owner -d nubia "$@"; }

PG -c "CREATE TABLE IF NOT EXISTS _sqlx_migrations (
         version BIGINT PRIMARY KEY,
         description TEXT NOT NULL DEFAULT '',
         installed_on TIMESTAMPTZ NOT NULL DEFAULT now());"

for f in "$MIG_DIR"/*.sql; do
  base="$(basename "$f")"
  v="$(echo "$base" | grep -oE '^[0-9]+' | sed 's/^0*//')"; v="${v:-0}"
  applied="$(PG -tAc "SELECT 1 FROM _sqlx_migrations WHERE version=$v" | tr -d '[:space:]')"
  if [ "$applied" = "1" ]; then
    continue
  fi
  echo "[migrate] applique $base"
  # --single-transaction : la migration entière est atomique (tout ou rien). Sans
  # ça, psql auto-commit chaque instruction → une migration qui plante à mi-course
  # laisse un état PARTIEL non enregistré dans _sqlx_migrations, et chaque deploy
  # suivant la rejoue et meurt sur l'objet déjà créé (incident 0214 : ADD CONSTRAINT
  # …_uniq committé puis ADD FK échoué sur données violantes → deploy bloqué à vie).
  # Avec, un échec rollback tout → prod propre + re-run possible une fois la cause levée.
  podman exec -i nubia-pg psql -v ON_ERROR_STOP=1 --single-transaction -U nubia_owner -d nubia < "$f"
  PG -c "INSERT INTO _sqlx_migrations(version, description) VALUES ($v, '$base');"
done
echo "[migrate] migrations à jour"
