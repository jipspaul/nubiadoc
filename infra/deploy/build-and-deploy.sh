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
#   5. pousse binaire/image, migrations, seed, bundles web
#   6. lance deploy.sh sur le LXC (run de la stack)
#   7. applique (opt-in, cf. CADDY_HOST) le bloc Caddy reservation.doc.nubia-link.com
#      sur l'hôte Caddy hors LXC ; échec dur si le domaine ne sert PAS de TLS
#      après coup, que CADDY_HOST soit provisionné ou non (#6188, #6379)
#   8. health-check TLS best-effort des domaines publics
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# LXC accessible via son IP Tailscale (le LAN 192.168.1.100 n'est plus joignable
# depuis le runner CI — machine deplacee/reconnectee hors du LAN d'origine).
HOST="${DEPLOY_HOST:-100.117.41.116}"
SSH_USER="${DEPLOY_USER:-root}"
export SSHPASS="${DEPLOY_PASSWORD:-jipsjips}"
API_BASE="${API_BASE:-http://${HOST}:3000}"
# #5688 : absente jusqu'ici de toute la chaîne CI -> LXC (secret Forgejo à
# renseigner) -> le conteneur nubia-api démarrait donc TOUJOURS sans
# YOUSIGN_API_KEY, quelle que soit la config secrets Forgejo -> Bearer vide ->
# 502 upstream_unavailable systématique sur POST /v1/quotes/:id/signature.
YOUSIGN_API_KEY="${YOUSIGN_API_KEY:-}"
# #6250 : même bug que #5688 ci-dessus, mais sur le signer de stockage
# (`ScalewayStorageSigner::from_env`, `SCW_ACCESS_KEY`/`SCW_SECRET_KEY`/
# `SCW_BUCKET`) — absentes de toute la chaîne CI -> LXC, `signer.sign()`
# renvoie donc toujours `None` en prod -> 502 upstream_unavailable sur 100%
# de `GET /v1/documents/:id` et `/download`, quel que soit le document.
SCW_ACCESS_KEY="${SCW_ACCESS_KEY:-}"
SCW_SECRET_KEY="${SCW_SECRET_KEY:-}"
SCW_BUCKET="${SCW_BUCKET:-}"
TARGET="x86_64-unknown-linux-musl"
OUT="$ROOT/.deploy-artifacts"

SSH() { sshpass -e ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "${SSH_USER}@${HOST}" "$@"; }
SCP() { sshpass -e scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$@"; }
say() { printf '\n\033[1;36m== %s\033[0m\n' "$*"; }

# Résout flutter (souvent un alias 'puro flutter' en interactif).
if command -v puro >/dev/null 2>&1; then FLUTTER="puro flutter"; else FLUTTER="flutter"; fi

mkdir -p "$OUT/api-ctx"

say "1/8 cross-compile API ($TARGET, statique)"
# `cargo clean -p nubia-api` force la recompilation de NOTRE crate (les deps
# restent en cache → build rapide). Sans ça, le cache CI (restore-keys
# `deploy-rust-`) peut rejouer un `target/` où nubia-api est jugé à jour et
# servir un binaire périmé — cause de fixes backend non déployés.
( cd "$ROOT/api" && cargo clean -p nubia-api --release --target "$TARGET" 2>/dev/null || true )
( cd "$ROOT/api" && SQLX_OFFLINE=true cargo zigbuild --target "$TARGET" --release --bin nubia-api )
cp "$ROOT/api/target/$TARGET/release/nubia-api" "$OUT/api-ctx/nubia-api"

say "2/8 préparation du contexte image API (assemblée sur le LXC, amd64 natif)"
# Binaire déjà copié à l'étape 1 ; on ajoute le Dockerfile COPY-only.
cp "$ROOT/infra/deploy/api.Dockerfile" "$OUT/api-ctx/api.Dockerfile"

say "3/8 flutter build web x3"
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
build_front app_pharmacie   pharmacie
build_front app_infirmiere  infirmiere

say "4/8 provision LXC (idempotent)"
SSH 'sh -s' < "$ROOT/infra/deploy/provision.sh"

say "5/8 envoi des artefacts"
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
# bundles flutter
for d in patient praticien secretary pharmacie infirmiere; do
  SSH "rm -rf /opt/nubia/www/$d && mkdir -p /opt/nubia/www/$d"
  tar czf - -C "$OUT/www-$d" . | SSH "tar xzf - -C /opt/nubia/www/$d"
done

say "6/8 déploiement distant"
SSH "PUBLIC_API_BASE='$API_BASE' YOUSIGN_API_KEY='$YOUSIGN_API_KEY' \
  SCW_ACCESS_KEY='$SCW_ACCESS_KEY' SCW_SECRET_KEY='$SCW_SECRET_KEY' SCW_BUCKET='$SCW_BUCKET' \
  sh /opt/nubia/deploy.sh"

say "7/8 application auto du bloc Caddy reservation.doc.nubia-link.com (hôte Caddy, opt-in)"
# #6116/#6139/#6160/#6162 : ce bloc est un template à coller à la main sur
# l'hôte Caddy (hors LXC, hors périmètre du reste de ce script) — récidive x4
# faute d'un mécanisme d'application automatique. Si CADDY_HOST/CADDY_USER/
# CADDY_PASSWORD sont renseignés (secrets optionnels, cf. README), ce script
# pousse + recharge la config réellement servie ; sinon il no-op (secret non
# provisionné). PAS de `|| true` ici une fois CADDY_HOST configuré : un échec
# doit être visible (badge rouge), pas noyé dans un warning best-effort — cf.
# postmortem #3493 (faux vert pire qu'un rouge honnête).
CADDY_HOST="${CADDY_HOST:-}" CADDY_USER="${CADDY_USER:-}" CADDY_PASSWORD="${CADDY_PASSWORD:-}" \
  bash "$ROOT/infra/deploy/apply-reservation-caddy.sh"

# #6379 (7e récidive #6116/#6139/#6160/#6162/#6188/#6317) : cette vérification
# n'était gardée QUE par `if [ -z "$CADDY_HOST" ]` (#6188), donc elle ne se
# déclenchait que quand le secret n'était PAS provisionné. Dès que CADDY_HOST
# est configuré, apply-reservation-caddy.sh peut sortir 0 (un des `reload`
# a réussi, cf. sa propre correction #6317) sans que le domaine serve
# réellement du TLS (bloc appliqué sur un Caddy sans certificat valide,
# vhost écrasé après coup, etc.) — plus AUCUN contrôle bloquant ne portait
# alors sur reservation.doc.nubia-link.com. On teste donc maintenant le
# RÉSULTAT OBSERVABLE (le domaine sert-il du TLS ?) dans TOUS les cas, que
# CADDY_HOST soit vide ou non : un badge rouge est le seul signal qui a une
# chance d'être agi dessus (cf. postmortem #3493, déjà cité ci-dessus).
RESERVATION_CODE="$(curl -sS --max-time 10 -o /dev/null -w '%{http_code}' https://reservation.doc.nubia-link.com/ 2>/dev/null || true)"
if [ -z "$RESERVATION_CODE" ] || [ "$RESERVATION_CODE" = "000" ]; then
  echo "::error::reservation.doc.nubia-link.com injoignable en TLS après application du bloc Caddy — collage/vérification manuel requis (cf. infra/deploy/Caddyfile.snippet). 7e récidive du même symptôme (#6116, #6139, #6160, #6162, #6188, #6317, #6379) : déploiement bloqué pour forcer l'action humaine."
  exit 1
fi

say "8/8 health-check TLS des domaines publics (Caddy hôte, best-effort)"
# #6116/#6139/#6160 : le bloc Caddy dédié à reservation.doc.nubia-link.com est
# un template collé à la main sur l'hôte Caddy (hors LXC, hors périmètre de ce
# script) et a disparu 3 fois sans que personne ne s'en aperçoive avant un
# sweep QA, parfois >24h plus tard. `|| true` : un souci DNS/réseau côté
# runner ne doit pas faire échouer un déploiement par ailleurs réussi — le but
# ici est la VISIBILITÉ immédiate (log CI), pas de bloquer le déploiement.
bash "$ROOT/infra/deploy/verify-public-tls.sh" || true

cat <<EOF

✅ Déploiement terminé. Accès direct (IP) :
   patient     http://${HOST}:8081
   praticien   http://${HOST}:8082
   secrétariat http://${HOST}:8083
   pharmacie   http://${HOST}:8084
   infirmiere  http://${HOST}:8085
   api         http://${HOST}:3000/v1/health
EOF
