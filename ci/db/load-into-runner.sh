#!/usr/bin/env bash
# Construit l'image db-ci:stable et la charge dans le DinD du runner Forgejo
# (même principe que ci/flutter/load-into-runner.sh : image locale, non poussée
# vers un registre ; le runner a force_pull: false et utilise le cache local).
set -euo pipefail

IMAGE="db-ci:stable"
HERE="$(cd "$(dirname "$0")" && pwd)"

# podman (POC Nubia) ou docker, au choix de la machine.
if command -v podman >/dev/null 2>&1; then BUILD=podman; else BUILD=docker; fi

echo "→ build $IMAGE avec $BUILD"
"$BUILD" build -t "$IMAGE" -f "$HERE/Containerfile" "$HERE"

# Charge l'image dans le conteneur DinD du runner (nom à adapter à votre runner).
DIND="${RUNNER_DIND:-forgejo-runner-dind}"
if "$BUILD" ps --format '{{.Names}}' | grep -qx "$DIND"; then
  echo "→ load $IMAGE dans $DIND"
  "$BUILD" save "$IMAGE" | "$BUILD" exec -i "$DIND" docker load
else
  echo "… conteneur DinD '$DIND' introuvable : image construite localement seulement."
  echo "  (réglez RUNNER_DIND=<nom> si votre DinD a un autre nom)"
fi
echo "✓ $IMAGE prêt"
