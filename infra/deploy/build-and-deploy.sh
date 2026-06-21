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
build_front() { # app_dir  www_name
  ( cd "$ROOT/front/apps/$1" && $FLUTTER build web --release --base-href / \
      --dart-define=API_BASE_URL="$API_BASE" )
  rm -rf "$OUT/www-$2"
  cp -r "$ROOT/front/apps/$1/build/web" "$OUT/www-$2"
  cp "$OUT/sqlite3.wasm" "$OUT/www-$2/sqlite3.wasm"
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
