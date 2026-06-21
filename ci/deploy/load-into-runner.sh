#!/usr/bin/env bash
# Construit l'image deploy-ci:stable et la charge dans le DinD du runner Forgejo
# (même principe que ci/db/load-into-runner.sh et ci/flutter : image locale, non
# poussée vers un registre ; le runner a force_pull: false et lit le cache local).
#
# Pré-requis : l'image flutter-ci:stable doit déjà exister (cf. ci/flutter).
set -euo pipefail

IMAGE="deploy-ci:stable"
HERE="$(cd "$(dirname "$0")" && pwd)"

if command -v podman >/dev/null 2>&1; then BUILD=podman; else BUILD=docker; fi

echo "→ build $IMAGE avec $BUILD"
"$BUILD" build -t "$IMAGE" -f "$HERE/Containerfile" "$HERE"

DIND="${RUNNER_DIND:-forgejo-runner-dind}"
if "$BUILD" ps --format '{{.Names}}' | grep -qx "$DIND"; then
  echo "→ load $IMAGE dans $DIND"
  "$BUILD" save "$IMAGE" | "$BUILD" exec -i "$DIND" docker load
else
  echo "… conteneur DinD '$DIND' introuvable : image construite localement seulement."
  echo "  (réglez RUNNER_DIND=<nom> si votre DinD a un autre nom)"
fi
echo "✓ $IMAGE prêt"
