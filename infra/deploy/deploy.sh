#!/bin/sh
# Orchestration SUR le LXC Alpine (idempotent, ré-exécutable à chaque déploiement).
# - charge l'image API (binaire musl cross-compilé, poussée en tar)
# - (re)construit l'image console Astro depuis les sources (node amd64 natif sur le LXC)
# - démarre/maj postgres, applique migrations + seed
# - démarre/maj api, console, web (nginx statique)
# Tous les conteneurs sont en réseau host -> joignables sur l'IP du LXC.
#
# Postmortem 2026-06-24 : tous les containers DOWN simultanément (502 sur les 4
# upstreams Caddy) → soit OOM cascade (un container explose la RAM, OOM-killer
# tape tous les autres), soit podman service crash. Mitigation appliquée ici :
#   - `--memory` + `--memory-swap` hard limits par container → OOM-killer cible
#     UN coupable au lieu d'un kill cascade
#   - `--health-cmd` par container → `podman ps` montre healthy/unhealthy, plus
#     facile à diagnostiquer + couplable à un alerting externe
#   - check final : si un container n'est pas Up après 30s, exit 1 (le job CI
#     Forgejo échouera → tu vois tout de suite que le deploy est cassé en prod)
set -eu
cd /opt/nubia
PUBLIC_API_BASE="${PUBLIC_API_BASE:-http://192.168.1.100:3000}"

echo "[deploy] build image api (COPY-only, binaire musl pré-compilé)"
podman build -t localhost/nubia-api:latest -f api-ctx/api.Dockerfile api-ctx

echo "[deploy] build image console (node amd64 natif)"
podman build --build-arg PUBLIC_API_BASE="$PUBLIC_API_BASE" \
  -t localhost/nubia-console:latest \
  -f web-console-src/Dockerfile web-console-src

echo "[deploy] postgres"
podman volume inspect nubia_pg >/dev/null 2>&1 || podman volume create nubia_pg >/dev/null
if podman container exists nubia-pg; then
  podman start nubia-pg >/dev/null
else
  # Postgres + PostGIS : 2g hard limit (postgres + connections + shared buffers).
  # Healthcheck via pg_isready interne sur 127.0.0.1:5432.
  podman run -d --name nubia-pg --network host --restart unless-stopped \
    --memory=2g --memory-swap=2g \
    --health-cmd='pg_isready -h 127.0.0.1 -p 5432 -U postgres -q' \
    --health-interval=30s --health-timeout=5s --health-retries=3 --health-start-period=20s \
    -e POSTGRES_HOST_AUTH_METHOD=trust -e POSTGRES_USER=postgres -e POSTGRES_DB=postgres \
    -v nubia_pg:/var/lib/postgresql/data \
    docker.io/postgis/postgis:16-3.4 postgres -c listen_addresses=127.0.0.1 >/dev/null
fi

echo "[deploy] attente postgres (TCP — évite le serveur d'init temporaire socket-only)"
# L'entrypoint postgis lance d'abord un serveur temporaire (socket UNIX seulement)
# pour l'init, puis redémarre le vrai serveur. On attend donc la dispo TCP sur
# 127.0.0.1 (que le serveur temporaire n'écoute PAS) pour ne pas migrer dans le vide.
i=0
while [ "$i" -lt 90 ]; do
  if podman exec nubia-pg pg_isready -h 127.0.0.1 -p 5432 -U postgres -q 2>/dev/null; then break; fi
  i=$((i + 1)); sleep 1
done
sleep 2

sh bootstrap-db.sh
sh migrate.sh
sh seed.sh || echo "[deploy] seed non bloquant"

echo "[deploy] api"
podman rm -f nubia-api >/dev/null 2>&1 || true
# Rust musl statique + tokio + sqlx pool + argon2 (JWT) : 1.5Gi pour absorber
# le burst au boot (init pool DB + warmup tokio workers). Postmortem 2026-06-24
# soir : 768Mi a fait crash le boot.
# Healthcheck : pas de /v1/health garanti, on check juste qu'une route renvoie
# du HTTP (peu importe 200/401/404 — on veut savoir si tokio est UP). wget
# --spider exit 0 si HTTP répond, exit 1 si pas de réponse → exactement ce qu'on veut.
podman run -d --name nubia-api --network host --restart unless-stopped \
  --memory=1500m --memory-swap=1500m \
  --health-cmd='wget -q --spider --timeout=3 http://127.0.0.1:3000/ 2>&1 | grep -qE "200|301|302|401|404" || exit 1' \
  --health-interval=30s --health-timeout=5s --health-retries=3 --health-start-period=20s \
  -e APP_DATABASE_URL=postgres://nubia_app@127.0.0.1:5432/nubia \
  -e APP_PORT=3000 -e JWT_SECRET=dev-only-not-for-prod -e LOGIN_RATE_MAX_ATTEMPTS=10000 \
  localhost/nubia-api:latest >/dev/null

echo "[deploy] console"
podman rm -f nubia-console >/dev/null 2>&1 || true
# Astro SSR + node : 768Mi (node base ~150Mi + SSR working set).
podman run -d --name nubia-console --network host --restart unless-stopped \
  --memory=768m --memory-swap=768m \
  --health-cmd='wget -q --spider --timeout=3 http://127.0.0.1:4321/ || exit 1' \
  --health-interval=30s --health-timeout=5s --health-retries=3 --health-start-period=10s \
  -e HOST=0.0.0.0 -e PORT=4321 -e PUBLIC_API_BASE="$PUBLIC_API_BASE" \
  localhost/nubia-console:latest >/dev/null

echo "[deploy] web (nginx statique 8081/8082/8083)"
podman rm -f nubia-web >/dev/null 2>&1 || true
# nginx statique : 256Mi largement suffisant (juste sert des fichiers).
podman run -d --name nubia-web --network host --restart unless-stopped \
  --memory=256m --memory-swap=256m \
  --health-cmd='wget -q --spider --timeout=3 http://127.0.0.1:8081/ || exit 1' \
  --health-interval=30s --health-timeout=5s --health-retries=3 --health-start-period=5s \
  -v /opt/nubia/nginx.conf:/etc/nginx/conf.d/default.conf:ro \
  -v /opt/nubia/www:/www:ro \
  docker.io/library/nginx:alpine >/dev/null

echo "[deploy] attente 30s puis vérif que tous les 4 containers sont Up..."
sleep 30
FAILED=""
for c in nubia-pg nubia-api nubia-console nubia-web; do
  STATUS=$(podman inspect -f '{{.State.Status}}' "$c" 2>/dev/null || echo "missing")
  HEALTH=$(podman inspect -f '{{.State.Health.Status}}' "$c" 2>/dev/null || echo "n/a")
  printf "  %-18s status=%-10s health=%s\n" "$c" "$STATUS" "$HEALTH"
  if [ "$STATUS" != "running" ]; then FAILED="$FAILED $c"; fi
done
if [ -n "$FAILED" ]; then
  echo "[deploy] ❌ containers down :$FAILED"
  echo "[deploy] logs des coupables :"
  for c in $FAILED; do
    echo "  --- $c (last 30 lines) ---"
    podman logs --tail 30 "$c" 2>&1 | sed 's/^/    /'
  done
  exit 1
fi

echo "[deploy] OK — état final des conteneurs :"
podman ps --format '  {{.Names}}  {{.Status}}'
