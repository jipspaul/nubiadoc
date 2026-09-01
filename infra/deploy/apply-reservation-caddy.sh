#!/usr/bin/env bash
# Applique automatiquement le bloc Caddy dédié à reservation.doc.nubia-link.com
# sur l'hôte Caddy (hors LXC, cf. infra/deploy/Caddyfile.snippet) à CHAQUE
# déploiement, au lieu de dépendre d'un copier-coller manuel.
#
# #6116/#6139/#6160/#6162 : ce bloc a disparu 4 fois de la config Caddy réelle
# alors que le repo (Caddyfile.snippet, build-and-deploy.sh, verify-public-tls.sh)
# n'avait jusqu'ici AUCUN moyen d'atteindre l'hôte Caddy — seule une action
# humaine hors-CI pouvait recoller le bloc, et rien ne la déclenchait ni ne la
# vérifiait après coup (#6160 a fermé le ticket sur la seule preuve d'un ajout
# de tooling de détection, sans jamais toucher la config live -> récidive
# immédiate, #6162). Ce script comble ce trou.
#
# Si les secrets CADDY_HOST/CADDY_USER/CADDY_PASSWORD sont renseignés, il :
#   1. récupère le Caddyfile distant,
#   2. y insère/remplace (idempotent, via marqueurs) le bloc reservation lu
#      directement dans infra/deploy/Caddyfile.snippet (source unique, pas de
#      duplication qui pourrait diverger),
#   3. valide la config resultante (`caddy validate`) AVANT tout remplacement,
#   4. ne l'applique + recharge Caddy que si la validation passe.
# Si CADDY_HOST est absent (secret non provisionné), no-op propre — comme
# YOUSIGN_API_KEY côté API (cf. README) — le collage manuel documenté dans
# Caddyfile.snippet reste le fallback tant que ce secret n'est pas configuré.
set -uo pipefail

CADDY_HOST="${CADDY_HOST:-}"
if [ -z "$CADDY_HOST" ]; then
  echo "ℹ️  CADDY_HOST non renseigné — application auto du bloc reservation.doc.nubia-link.com sautée (fallback : collage manuel, cf. infra/deploy/Caddyfile.snippet)."
  exit 0
fi

CADDY_USER="${CADDY_USER:-root}"
CADDY_SSH_PORT="${CADDY_SSH_PORT:-22}"
CADDY_CONFIG_PATH="${CADDY_CONFIG_PATH:-/etc/caddy/Caddyfile}"
export SSHPASS="${CADDY_PASSWORD:-}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SNIPPET="$ROOT/infra/deploy/Caddyfile.snippet"

SSH() { sshpass -e ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p "$CADDY_SSH_PORT" "${CADDY_USER}@${CADDY_HOST}" "$@"; }
SCP() { sshpass -e scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -P "$CADDY_SSH_PORT" "$@"; }

BLOCK_FILE="$(mktemp)"
REMOTE_TMP="$(mktemp)"
MERGED_TMP="$(mktemp)"
trap 'rm -f "$BLOCK_FILE" "$REMOTE_TMP" "$MERGED_TMP"' EXIT

# Extrait UNIQUEMENT le bloc reservation.doc.nubia-link.com du snippet (source
# unique de vérité — évite de dupliquer le domaine/port en dur ici).
awk '/^reservation\.doc\.nubia-link\.com \{/{f=1} f{print} f&&/^}/{exit}' "$SNIPPET" > "$BLOCK_FILE"
if [ ! -s "$BLOCK_FILE" ]; then
  echo "::error::bloc reservation.doc.nubia-link.com introuvable dans $SNIPPET — abandon."
  exit 1
fi

echo "→ récupération du Caddyfile distant (${CADDY_HOST}:${CADDY_CONFIG_PATH})"
if ! SCP "${CADDY_USER}@${CADDY_HOST}:${CADDY_CONFIG_PATH}" "$REMOTE_TMP"; then
  echo "::error::impossible de récupérer ${CADDY_CONFIG_PATH} sur ${CADDY_HOST} — abandon (pas de modification à l'aveugle)."
  exit 1
fi

BEGIN_MARK="# BEGIN nubia-reservation-caddy (auto, infra/deploy/apply-reservation-caddy.sh — #6162)"
END_MARK="# END nubia-reservation-caddy"

# Retire un éventuel bloc marqué précédent (peu importe sa position), puis
# rajoute la version courante en fin de fichier -> idempotent.
awk -v begin="$BEGIN_MARK" -v end="$END_MARK" '
  $0 == begin { skip=1; next }
  $0 == end { skip=0; next }
  !skip { print }
' "$REMOTE_TMP" > "$MERGED_TMP"

{
  cat "$MERGED_TMP"
  echo ""
  echo "$BEGIN_MARK"
  cat "$BLOCK_FILE"
  echo "$END_MARK"
} > "$REMOTE_TMP.new"

REMOTE_CANDIDATE_PATH="/tmp/nubia-caddyfile.candidate"
SCP "$REMOTE_TMP.new" "${CADDY_USER}@${CADDY_HOST}:${REMOTE_CANDIDATE_PATH}"
rm -f "$REMOTE_TMP.new"

echo "→ validation de la config candidate sur ${CADDY_HOST}"
if ! SSH "caddy validate --config '$REMOTE_CANDIDATE_PATH' --adapter caddyfile"; then
  echo "::error::validation Caddyfile échouée sur ${CADDY_HOST} — bloc reservation NON appliqué (config live inchangée)."
  SSH "rm -f '$REMOTE_CANDIDATE_PATH'" || true
  exit 1
fi

echo "→ application + rechargement Caddy sur ${CADDY_HOST}"
SSH "cp '$REMOTE_CANDIDATE_PATH' '$CADDY_CONFIG_PATH' && rm -f '$REMOTE_CANDIDATE_PATH' && (caddy reload --config '$CADDY_CONFIG_PATH' --adapter caddyfile || systemctl reload caddy || service caddy reload)"
echo "✅ bloc reservation.doc.nubia-link.com appliqué et Caddy rechargé sur ${CADDY_HOST}"
