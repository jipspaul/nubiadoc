#!/bin/sh
# Orchestration SUR le LXC Alpine (idempotent, ré-exécutable à chaque déploiement).
# - charge l'image API (binaire musl cross-compilé, poussée en tar)
# - (re)construit l'image console Astro depuis les sources (node amd64 natif sur le LXC)
# - démarre/maj postgres, applique migrations + seed
# - démarre/maj api, console, web (nginx statique)
# Tous les conteneurs sont en réseau host -> joignables sur l'IP du LXC.
#
# Postmortem 2026-06-24 : tous les containers DOWN simultanément (502 sur les 4
# upstreams Caddy) → soit OOM cascade, soit podman service crash.
# Tentative de mitigation via `--memory=Xg` → BLOQUÉE : crun OCI refuse de
# créer le container (`open memory.max: No such file or directory`). Le LXC
# parent ne delegate pas le cgroup v2 `memory` controller à l'unprivileged
# user namespace. Pour réintroduire les hard limits, faudrait reconfigurer la
# LXC parent (`lxc.mount.auto = cgroup:rw:force` + delegate au boot) — out of
# scope ici.
#
# Mitigations qui marchent dans CETTE LXC :
#   - `--health-cmd` par container → `podman ps` montre healthy/unhealthy
#   - `--restart unless-stopped` (déjà là) → relance auto si UN container die
#   - check final post-deploy : si un container pas Up après 30s, exit 1 (job
#     CI Forgejo fail → notif immédiate au lieu de découvrir 1h après)
#
# TODO : si la LXC parent peut être reconfigurée (cgroup v2 delegation), ré-
# introduire `--memory=Xg --memory-swap=Xg` par container. Mapping testé :
# pg=2g, api=1.5g, console=768m, web=256m.
set -eu
cd /opt/nubia
PUBLIC_API_BASE="${PUBLIC_API_BASE:-http://192.168.1.100:3000}"

# --- Garde-fou disque (incident 2026-07-30 -> 2026-08-02) --------------------
# Le LXC fait 7,8 Go. Chaque déploiement empile de nouvelles couches podman :
# le `--no-cache` de l'API et le rebuild de la console laissent à chaque fois
# des images intermédiaires que RIEN ne nettoyait. Le disque est monté à 90 %
# et le `npm ci` de la console est mort sur :
#   storing blob to file "/var/tmp/container_images_storage.../1":
#   no space left on device        (exitcode 125)
# Résultat : 3 JOURS sans déploiement (dernier succès 29/07 11h01) — le backend
# live servait du code périmé pendant que la CI passait au vert sur les PR.
# Personne ne l'a vu : l'échec était noyé au milieu d'un log de 6 minutes.
#
# Deux mesures, dans cet ordre :
#   1. purge des couches orphelines AVANT le build. `image prune` (sans -a) ne
#      touche QUE les couches sans tag et jamais une image utilisée par un
#      conteneur en cours — la stack qui tourne n'est pas menacée ;
#   2. si l'espace reste sous le seuil malgré ça, on échoue TÔT et FORT plutôt
#      que 6 minutes plus tard sur une erreur cryptique — même logique que le
#      pré-vol de joignabilité SSH (#3493).
MIN_FREE_MB=3000
echo "[deploy] purge des couches podman orphelines (avant build)"
podman image prune -f >/dev/null 2>&1 || true
podman container prune -f >/dev/null 2>&1 || true
rm -rf /var/tmp/container_images_storage* 2>/dev/null || true

FREE_MB=$(df -Pm / | awk 'NR==2{print $4}')
echo "[deploy] espace libre: ${FREE_MB} Mo (seuil ${MIN_FREE_MB} Mo)"
if [ "$FREE_MB" -lt "$MIN_FREE_MB" ]; then
  echo "::error::DISQUE PLEIN sur le LXC : ${FREE_MB} Mo libres < ${MIN_FREE_MB} Mo requis."
  echo "  Le build podman de la console échouerait sur 'no space left on device'."
  echo "  Sur le LXC : podman system prune -af && rm -rf /var/tmp/container_images_storage*"
  echo "  Puis : df -h /"
  exit 1
fi

echo "[deploy] build image api (COPY-only, binaire musl pré-compilé)"
# --no-cache : le layer COPY du binaire peut être servi depuis le cache podman
# (même tag :latest) et faire tourner un binaire périmé. On force un rebuild
# d'image à chaque déploiement (COPY-only, donc quasi instantané).
podman build --no-cache -t localhost/nubia-api:latest -f api-ctx/api.Dockerfile api-ctx

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
# du HTTP (peu importe 200/401/404 — on veut savoir si tokio est UP).
# Postmortem 2026-06-27 : `wget -q --spider` est silencieux donc `grep` ne
# voyait rien → healthcheck éternellement "starting". Fix : `-S` pour faire
# émettre les headers du serveur, puis grep sur la ligne `HTTP/x.x <code>`.
podman run -d --name nubia-api --network host --restart unless-stopped \
  --health-cmd='wget -q -S --spider --timeout=3 http://127.0.0.1:3000/ 2>&1 | grep -qE "HTTP/.* (200|301|302|401|404)" || exit 1' \
  --health-interval=30s --health-timeout=5s --health-retries=3 --health-start-period=20s \
  -e APP_DATABASE_URL=postgres://nubia_app@127.0.0.1:5432/nubia \
  -e APP_PORT=3000 -e JWT_SECRET=dev-only-not-for-prod -e LOGIN_RATE_MAX_ATTEMPTS=10000 \
  -e MLLP_PORT=2575 \
  localhost/nubia-api:latest >/dev/null
# Lot B10 (interop HL7v2) : le listener MLLP reste désactivé tant que
# MLLP_TLS_CERT_PATH/MLLP_TLS_KEY_PATH/MLLP_TLS_CLIENT_CA_PATH ne sont pas
# fournis (pas de certs partenaires provisionnés pour l'instant — process
# d'onboarding à définir). `--network host` : pas de `-p` à ajouter, mais le
# port 2575 contourne Caddy — le filtrer au niveau hôte/LXC aux IP des
# partenaires EAI attendus avant toute mise en service réelle.

echo "[deploy] console"
podman rm -f nubia-console >/dev/null 2>&1 || true
# Astro SSR + node : 768Mi (node base ~150Mi + SSR working set).
# Healthcheck via `node` (et non wget) car l'image node:alpine n'a PAS wget —
# le healthcheck wget restait "starting" silencieusement (postmortem 2026-06-27).
podman run -d --name nubia-console --network host --restart unless-stopped \
  --health-cmd='node -e "require(\"http\").get(\"http://127.0.0.1:4321/\",r=>process.exit(r.statusCode<500?0:1)).on(\"error\",()=>process.exit(1))"' \
  --health-interval=30s --health-timeout=5s --health-retries=3 --health-start-period=10s \
  -e HOST=0.0.0.0 -e PORT=4321 -e PUBLIC_API_BASE="$PUBLIC_API_BASE" \
  localhost/nubia-console:latest >/dev/null

echo "[deploy] web (nginx statique 8081/8082/8083/8084)"
podman rm -f nubia-web >/dev/null 2>&1 || true
# nginx statique : 256Mi largement suffisant (juste sert des fichiers).
podman run -d --name nubia-web --network host --restart unless-stopped \
  --health-cmd='wget -q -S --spider --timeout=3 http://127.0.0.1:8081/ 2>&1 | grep -q "HTTP/" || exit 1' \
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

# re-deploy 2026-06-27 — validate LXC recovery + new healthchecks
# trigger-test (forgejo restart 2026-06-27 — verify concurrency lock cleared)
# trigger-test post fix cancel-in-progress (2026-06-27 ~02:15)
# trigger post runner-restart
# trigger after stabilization
# validation post fix DinD startup race
