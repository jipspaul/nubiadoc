#!/bin/sh
# Orchestration SUR le LXC Alpine (idempotent, ré-exécutable à chaque déploiement).
# - charge l'image API (binaire musl cross-compilé, poussée en tar)
# - (re)construit l'image console Astro depuis les sources (node amd64 natif sur le LXC)
# - démarre/maj postgres, applique migrations + seed
# - démarre/maj api, console, web (nginx statique)
# Tous les conteneurs sont en réseau host -> joignables sur l'IP du LXC.
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
  podman run -d --name nubia-pg --network host --restart unless-stopped \
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
podman run -d --name nubia-api --network host --restart unless-stopped \
  -e APP_DATABASE_URL=postgres://nubia_app@127.0.0.1:5432/nubia \
  -e APP_PORT=3000 -e JWT_SECRET=dev-only-not-for-prod -e LOGIN_RATE_MAX_ATTEMPTS=10000 \
  localhost/nubia-api:latest >/dev/null

echo "[deploy] console"
podman rm -f nubia-console >/dev/null 2>&1 || true
podman run -d --name nubia-console --network host --restart unless-stopped \
  -e HOST=0.0.0.0 -e PORT=4321 -e PUBLIC_API_BASE="$PUBLIC_API_BASE" \
  localhost/nubia-console:latest >/dev/null

echo "[deploy] web (nginx statique 8081/8082/8083)"
podman rm -f nubia-web >/dev/null 2>&1 || true
podman run -d --name nubia-web --network host --restart unless-stopped \
  -v /opt/nubia/nginx.conf:/etc/nginx/conf.d/default.conf:ro \
  -v /opt/nubia/www:/www:ro \
  docker.io/library/nginx:alpine >/dev/null

echo "[deploy] OK — état des conteneurs :"
podman ps --format '  {{.Names}}  {{.Status}}'
