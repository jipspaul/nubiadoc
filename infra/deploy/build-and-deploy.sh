#!/usr/bin/env bash
# Build + déploiement complet vers le LXC Alpine de test.
# Lancé depuis la racine du repo, sur une machine arm64 (Mac runner) disposant de :
#   - rust + cargo-zigbuild + zig + target x86_64-unknown-linux-musl
#   - podman (assemblage de l'image API)
#   - flutter (build web des 3 apps)
#   - sshpass
#
# Pipeline :
#   1. cross-compile l'API -> binaire musl statique amd64
#   2. assemble l'image API (COPY-only, amd64) -> tar
#   3. flutter build web x3 (API_BASE_URL baké au build)
#   4. provisionne le LXC (podman) si besoin
#   5. pousse binaire/image, sources console, migrations, seed, bundles web
#   6. lance deploy.sh sur le LXC (build console amd64 natif + run de la stack)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOST="${DEPLOY_HOST:-192.168.1.100}"
SSH_USER="${DEPLOY_USER:-root}"
export SSHPASS="${DEPLOY_PASSWORD:-jipsjips}"
API_BASE="${API_BASE:-http://${HOST}:3000}"
TARGET="x86_64-unknown-linux-musl"
OUT="$ROOT/.deploy-artifacts"

SSH() { sshpass -e ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "${SSH_USER}@${HOST}" "$@"; }
SCP() { sshpass -e scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$@"; }
say() { printf '\n\033[1;36m== %s\033[0m\n' "$*"; }

# Résout flutter (souvent un alias 'puro flutter' en interactif).
if command -v puro >/dev/null 2>&1; then FLUTTER="puro flutter"; else FLUTTER="flutter"; fi

mkdir -p "$OUT/api-ctx"

say "1/6 cross-compile API ($TARGET, statique)"
# `cargo clean -p nubia-api` force la recompilation de NOTRE crate (les deps
# restent en cache → build rapide). Sans ça, le cache CI (restore-keys
# `deploy-rust-`) peut rejouer un `target/` où nubia-api est jugé à jour et
# servir un binaire périmé — cause de fixes backend non déployés.
( cd "$ROOT/api" && cargo clean -p nubia-api --release --target "$TARGET" 2>/dev/null || true )
( cd "$ROOT/api" && SQLX_OFFLINE=true cargo zigbuild --target "$TARGET" --release --bin nubia-api )
cp "$ROOT/api/target/$TARGET/release/nubia-api" "$OUT/api-ctx/nubia-api"

say "2/6 préparation du contexte image API (assemblée sur le LXC, amd64 natif)"
# Binaire déjà copié à l'étape 1 ; on ajoute le Dockerfile COPY-only.
cp "$ROOT/infra/deploy/api.Dockerfile" "$OUT/api-ctx/api.Dockerfile"

say "3/6 flutter build web x3"
# Asset Drift web : sqlite3 compilé en WASM (cache offline côté web).
SQLITE3_WASM_VER="${SQLITE3_WASM_VER:-3.3.3}"
if [ ! -f "$OUT/sqlite3.wasm" ]; then
  curl -fsSL "https://github.com/simolus3/sqlite3.dart/releases/download/sqlite3-${SQLITE3_WASM_VER}/sqlite3.wasm" \
    -o "$OUT/sqlite3.wasm"
fi
( cd "$ROOT/front" && $FLUTTER pub get >/dev/null )
# Marqueur de déploiement : permet de vérifier QUEL commit est en ligne via
#   curl http://<host>:<port>/deploy.json
# (NE PAS écraser le version.json de Flutter, lu par son service worker.)
GIT_SHA="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"
BUILD_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
# Les apps Flutter mettent le /v1 DANS la base (ApiConstants.baseUrl) et appellent
# '/auth/login' ; la console Astro garde l'hôte nu et préfixe /v1 dans ses chemins.
# D'où deux bases distinctes à partir du même hôte.
FLUTTER_API_BASE="${API_BASE%/}/v1"
build_front() { # app_dir  www_name
  # --pwa-strategy=none : pas de service worker. Sur un site redéployé en continu,
  # le SW Flutter sert un cache périmé après chaque déploiement -> écran blanc.
  # Sans SW, le navigateur récupère les assets frais à chaque chargement.
  # --no-tree-shake-icons : embarque la police MaterialIcons complète. Le
  # tree-shaking d'icônes cassait leur rendu sur web (icônes en carrés « tofu »).
  ( cd "$ROOT/front/apps/$1" && $FLUTTER build web --release --base-href / \
      --pwa-strategy=none --no-tree-shake-icons \
      --dart-define=API_BASE_URL="$FLUTTER_API_BASE" )
  rm -rf "$OUT/www-$2"
  cp -r "$ROOT/front/apps/$1/build/web" "$OUT/www-$2"
  cp "$OUT/sqlite3.wasm" "$OUT/www-$2/sqlite3.wasm"
  printf '{"app":"%s","commit":"%s","built_at":"%s","api_base":"%s"}\n' \
    "$2" "$GIT_SHA" "$BUILD_AT" "$FLUTTER_API_BASE" > "$OUT/www-$2/deploy.json"
  # SW auto-destructeur : évince un éventuel ancien service worker Flutter déjà
  # enregistré dans le navigateur (cache périmé d'un déploiement précédent ->
  # écran blanc). Servi no-cache (cf. nginx.conf), il purge les caches, se
  # désenregistre et recharge l'onglet. Les nouveaux visiteurs n'ont pas de SW.
  cat > "$OUT/www-$2/flutter_service_worker.js" <<'SW'
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (e) => e.waitUntil((async () => {
  try { const ks = await caches.keys(); await Promise.all(ks.map((k) => caches.delete(k))); } catch (_) {}
  try { await self.registration.unregister(); } catch (_) {}
  const cs = await self.clients.matchAll({ type: 'window' });
  cs.forEach((c) => c.navigate(c.url));
})()));
SW
}
build_front app_patient    patient
build_front app_practicien praticien
build_front app_secretariat secretary

say "4/6 provision LXC (idempotent)"
SSH 'sh -s' < "$ROOT/infra/deploy/provision.sh"

say "5/6 envoi des artefacts"
# scripts + nginx.conf
SCP "$ROOT/infra/deploy/deploy.sh" "$ROOT/infra/deploy/bootstrap-db.sh" \
    "$ROOT/infra/deploy/migrate.sh" "$ROOT/infra/deploy/seed.sh" \
    "$ROOT/infra/deploy/nginx.conf" "${SSH_USER}@${HOST}:/opt/nubia/"
# contexte image API (binaire musl statique + Dockerfile) -> build sur le LXC
SSH 'rm -rf /opt/nubia/api-ctx && mkdir -p /opt/nubia/api-ctx'
tar czf - -C "$OUT/api-ctx" . | SSH 'tar xzf - -C /opt/nubia/api-ctx'
# migrations + seed
SSH 'rm -rf /opt/nubia/migrations /opt/nubia/seed && mkdir -p /opt/nubia/migrations /opt/nubia/seed'
tar czf - -C "$ROOT/db/migrations" . | SSH 'tar xzf - -C /opt/nubia/migrations'
tar czf - -C "$ROOT/db/seed" . | SSH 'tar xzf - -C /opt/nubia/seed'
# sources console (sans node_modules/dist)
SSH 'rm -rf /opt/nubia/web-console-src && mkdir -p /opt/nubia/web-console-src'
tar czf - -C "$ROOT/web-console" \
    --exclude=node_modules --exclude=dist --exclude=.astro \
    --exclude=test-results --exclude=playwright-report --exclude=blob-flows . \
  | SSH 'tar xzf - -C /opt/nubia/web-console-src'
# bundles flutter
for d in patient praticien secretary; do
  SSH "rm -rf /opt/nubia/www/$d && mkdir -p /opt/nubia/www/$d"
  tar czf - -C "$OUT/www-$d" . | SSH "tar xzf - -C /opt/nubia/www/$d"
done

say "6/6 déploiement distant"
SSH "PUBLIC_API_BASE='$API_BASE' sh /opt/nubia/deploy.sh"

cat <<EOF

✅ Déploiement terminé. Accès direct (IP) :
   patient     http://${HOST}:8081
   praticien   http://${HOST}:8082
   secrétariat http://${HOST}:8083
   console     http://${HOST}:4321
   api         http://${HOST}:3000/v1/health
EOF
