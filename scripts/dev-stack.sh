#!/usr/bin/env bash
# scripts/dev-stack.sh — lance toute la stack Nubia en local pour tester l'API.
#
# Démarre / réutilise :
#   - PostgreSQL 16 + PostGIS dans un conteneur Podman (nubia-dev-pg, port 5432)
#   - rôles nubia_owner / nubia_app / nubia_seed (idempotent)
#   - migrations sqlx (db/migrations) sous nubia_owner
#   - API Rust (cargo run --release, port 38030) avec APP_DATABASE_URL=nubia_app
#   - web-console Astro (port 38040) avec PUBLIC_API_BASE=http://localhost:38030
#
# Surcharges via env :
#   API_PORT (38030) · WEB_PORT (38040) · PG_PORT (5432)
#   PG_CONTAINER (nubia-dev-pg) · PG_IMAGE (docker.io/postgis/postgis:16-3.4)
#   JWT_SECRET (dev-only-not-for-prod) · CARGO_PROFILE (release)
#
# Ctrl+C : arrête API + web-console. Le conteneur Postgres reste up
# (relancer ce script le réutilise instantanément).

set -euo pipefail

API_PORT="${API_PORT:-38030}"
WEB_PORT="${WEB_PORT:-38040}"
PG_PORT="${PG_PORT:-5432}"
PG_CONTAINER="${PG_CONTAINER:-nubia-dev-pg}"
PG_IMAGE="${PG_IMAGE:-docker.io/postgis/postgis:16-3.4}"
JWT_SECRET="${JWT_SECRET:-dev-only-not-for-prod}"
CARGO_PROFILE="${CARGO_PROFILE:-release}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$ROOT/.dev-stack-logs"
mkdir -p "$LOG_DIR"

c_red()  { printf '\033[31m%s\033[0m' "$*"; }
c_grn()  { printf '\033[32m%s\033[0m' "$*"; }
c_ylw()  { printf '\033[33m%s\033[0m' "$*"; }
step()   { printf '\n%s %s\n' "$(c_ylw '→')" "$*"; }
ok()     { printf '  %s %s\n' "$(c_grn '✓')" "$*"; }
fail()   { printf '  %s %s\n' "$(c_red '✗')" "$*"; exit 1; }

CHILD_PIDS=()
stop_children() {
  [ ${#CHILD_PIDS[@]} -eq 0 ] && return 0
  printf '\n→ arrêt des processus enfants (%s)…\n' "${CHILD_PIDS[*]}"
  for pid in "${CHILD_PIDS[@]}"; do
    kill -TERM "$pid" 2>/dev/null || true
  done
  sleep 1
  for pid in "${CHILD_PIDS[@]}"; do
    kill -KILL "$pid" 2>/dev/null || true
  done
}
trap stop_children INT TERM EXIT

# ---------------------------------------------------------------------------
# 0. Pré-requis CLI
# ---------------------------------------------------------------------------
for bin in podman psql cargo npm curl lsof; do
  command -v "$bin" >/dev/null 2>&1 || fail "binaire requis introuvable : $bin"
done

# ---------------------------------------------------------------------------
# 1. Vérifie que les ports API et web sont libres (ou occupés par nous-mêmes)
# ---------------------------------------------------------------------------
check_port() {
  local port="$1" hint_var="$2"
  local raw who pid cmd
  # lsof retourne 1 si rien n'écoute → pipefail tuerait le script, d'où `|| true`
  raw=$(lsof -nP -iTCP:"$port" -sTCP:LISTEN 2>/dev/null || true)
  who=$(printf '%s\n' "$raw" | awk -v p="$port" 'NR>1 && $9 ~ ":"p"$" {print $1" PID="$2; exit}')
  if [ -n "$who" ]; then
    pid="${who##*PID=}"
    cmd=$(ps -p "$pid" -o command= 2>/dev/null || true)
    case "$cmd" in
      *nubia-api*|*web-console*astro*)
        printf '  %s port %s déjà tenu par notre propre process (PID %s) — il sera réutilisé\n' \
          "$(c_ylw '!')" "$port" "$pid"
        return 0
        ;;
    esac
    printf '  %s port %s déjà utilisé par : %s\n' "$(c_red '✗')" "$port" "$who"
    printf '         commande complète : %s\n' "$cmd"
    cat <<EOF
  Pour libérer ce port :
    kill $pid
  Ou utilise un autre port :
    $hint_var=<autre> ./scripts/dev-stack.sh
EOF
    exit 1
  fi
  ok "port $port disponible"
}

step "vérification des ports $API_PORT (API) et $WEB_PORT (web)"
check_port "$API_PORT" "API_PORT"
check_port "$WEB_PORT" "WEB_PORT"

# ---------------------------------------------------------------------------
# 2. Postgres (Podman) — réutilise / démarre / crée
# ---------------------------------------------------------------------------
step "Postgres (conteneur '$PG_CONTAINER')"
if podman ps --format '{{.Names}}' | grep -qx "$PG_CONTAINER"; then
  ok "conteneur déjà up"
elif podman ps -a --format '{{.Names}}' | grep -qx "$PG_CONTAINER"; then
  podman start "$PG_CONTAINER" >/dev/null
  ok "conteneur existant redémarré"
else
  podman run -d --name "$PG_CONTAINER" \
    -e POSTGRES_HOST_AUTH_METHOD=trust \
    -e POSTGRES_DB=postgres \
    -e POSTGRES_USER=postgres \
    -p "$PG_PORT:5432" \
    "$PG_IMAGE" >/dev/null
  ok "conteneur créé ($PG_IMAGE)"
fi

# Attendre que Postgres réponde
for i in $(seq 1 30); do
  podman exec "$PG_CONTAINER" pg_isready -U postgres -d postgres >/dev/null 2>&1 && break
  sleep 1
done
podman exec "$PG_CONTAINER" pg_isready -U postgres >/dev/null 2>&1 \
  || fail "Postgres ne répond pas après 30s"
ok "Postgres répond sur localhost:$PG_PORT"

# ---------------------------------------------------------------------------
# 3. Rôle owner + base + extension postgis (étape super-user — idempotent)
# ---------------------------------------------------------------------------
step "rôle nubia_owner + base 'nubia' + postgis"
podman exec "$PG_CONTAINER" psql -U postgres -tAc \
  "SELECT 1 FROM pg_roles WHERE rolname='nubia_owner';" | grep -qx 1 \
  || podman exec "$PG_CONTAINER" psql -U postgres -c \
       "CREATE ROLE nubia_owner LOGIN CREATEROLE BYPASSRLS;" >/dev/null

podman exec "$PG_CONTAINER" psql -U postgres -tAc \
  "SELECT 1 FROM pg_database WHERE datname='nubia';" | grep -qx 1 \
  || podman exec "$PG_CONTAINER" psql -U postgres -c \
       "CREATE DATABASE nubia OWNER nubia_owner;" >/dev/null

# postgis est untrusted : doit être installée par le super-user
podman exec "$PG_CONTAINER" psql -U postgres -d nubia -c \
  "CREATE EXTENSION IF NOT EXISTS postgis;" >/dev/null
ok "owner + base + postgis OK"

# ---------------------------------------------------------------------------
# 4. Migrations sqlx (sous nubia_owner) — les rôles app/seed sont créés par 0001
# ---------------------------------------------------------------------------
step "migrations sqlx (source : db/migrations)"
APPLIED=$(podman exec "$PG_CONTAINER" psql -U postgres -d nubia -tAc \
  "SELECT count(*) FROM _sqlx_migrations;" 2>/dev/null | tr -d ' ' || echo 0)
ON_DISK=$(find "$ROOT"/db/migrations -maxdepth 1 -name '*.sql' | wc -l | tr -d ' ')
echo "  appliquées : $APPLIED / disque : $ON_DISK"
if [ "$APPLIED" -lt "$ON_DISK" ]; then
  command -v sqlx >/dev/null \
    || fail "sqlx-cli absent — installer : cargo install sqlx-cli --no-default-features --features postgres"
  ( cd "$ROOT/db" && sqlx migrate run --source migrations \
      --database-url "postgres://nubia_owner@localhost:$PG_PORT/nubia" )
  ok "migrations à jour"
else
  ok "déjà à jour"
fi

# ---------------------------------------------------------------------------
# 5. API Rust
# ---------------------------------------------------------------------------
step "API Nubia — cargo build ($CARGO_PROFILE)"
BUILD_FLAG=""
[ "$CARGO_PROFILE" = "release" ] && BUILD_FLAG="--release"
( cd "$ROOT/api" && cargo build $BUILD_FLAG --bin nubia-api ) \
  || fail "build API a échoué — voir la sortie ci-dessus"
ok "build OK"

step "API Nubia — démarrage (log : .dev-stack-logs/api.log)"
: > "$LOG_DIR/api.log"
(
  cd "$ROOT/api"
  APP_DATABASE_URL="postgres://nubia_app@localhost:$PG_PORT/nubia" \
  APP_PORT="$API_PORT" \
  JWT_SECRET="$JWT_SECRET" \
  exec cargo run $BUILD_FLAG --bin nubia-api
) >>"$LOG_DIR/api.log" 2>&1 &
API_PID=$!
CHILD_PIDS+=("$API_PID")

for i in $(seq 1 60); do
  if ! kill -0 "$API_PID" 2>/dev/null; then
    echo
    tail -n 40 "$LOG_DIR/api.log"
    fail "API morte au démarrage — voir log ci-dessus"
  fi
  curl -sf "http://localhost:$API_PORT/v1/health" >/dev/null 2>&1 && { ok "/v1/health répond"; break; }
  sleep 1
  if [ "$i" -eq 60 ]; then
    tail -n 40 "$LOG_DIR/api.log"
    fail "API ne répond pas après 60s — voir $LOG_DIR/api.log"
  fi
done

# ---------------------------------------------------------------------------
# 6. Web-console (Astro)
# ---------------------------------------------------------------------------
step "web-console — install deps si besoin"
if [ ! -d "$ROOT/web-console/node_modules" ]; then
  ( cd "$ROOT/web-console" && npm install --silent )
  ok "npm install terminé"
else
  ok "node_modules présent"
fi

step "web-console — démarrage (log : .dev-stack-logs/web.log)"
: > "$LOG_DIR/web.log"
(
  cd "$ROOT/web-console"
  PUBLIC_API_BASE="http://localhost:$API_PORT" \
  exec npm run dev -- --host 127.0.0.1 --port "$WEB_PORT"
) >>"$LOG_DIR/web.log" 2>&1 &
WEB_PID=$!
CHILD_PIDS+=("$WEB_PID")

for i in $(seq 1 30); do
  curl -sf "http://localhost:$WEB_PORT/" >/dev/null 2>&1 && { ok "web-console répond"; break; }
  sleep 1
done

# ---------------------------------------------------------------------------
# 7. Récap + attente
# ---------------------------------------------------------------------------
cat <<EOF

$(c_grn '✅ Stack Nubia prête :')
   - Postgres : localhost:$PG_PORT             (conteneur $PG_CONTAINER, reste up après Ctrl+C)
   - API      : http://localhost:$API_PORT/v1/health
   - Web      : http://localhost:$WEB_PORT/

Logs : .dev-stack-logs/api.log  .dev-stack-logs/web.log
Tail : tail -f .dev-stack-logs/{api,web}.log

Ctrl+C pour arrêter API + web-console.
EOF

wait
