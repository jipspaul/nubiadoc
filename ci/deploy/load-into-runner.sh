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

# Le runner Forgejo tourne dans k3s (Lima) : namespace forgejo-runner, pod runner
# avec un sidecar DinD nommé "daemon" (docker:25-dind). On y charge l'image via
# kubectl exec. Fallback : conteneur DinD local nommé $RUNNER_DIND.
NS="${RUNNER_NS:-forgejo-runner}"
DIND_CONTAINER="${RUNNER_DIND_CONTAINER:-daemon}"
POD="$(kubectl -n "$NS" get pods -o name 2>/dev/null | grep -i runner | head -1 | sed 's#pod/##')"

if [ -n "${POD:-}" ]; then
  echo "→ load $IMAGE dans le DinD k3s ($NS/$POD -c $DIND_CONTAINER)"
  "$BUILD" save "$IMAGE" | kubectl -n "$NS" exec -i "$POD" -c "$DIND_CONTAINER" -- docker load
elif "$BUILD" ps --format '{{.Names}}' | grep -qx "${RUNNER_DIND:-forgejo-runner-dind}"; then
  DIND="${RUNNER_DIND:-forgejo-runner-dind}"
  echo "→ load $IMAGE dans le conteneur DinD local $DIND"
  "$BUILD" save "$IMAGE" | "$BUILD" exec -i "$DIND" docker load
else
  echo "… runner DinD introuvable (ni pod k3s '$NS', ni conteneur local)."
  echo "  Image construite localement seulement ; charge-la à la main dans le DinD du runner."
fi
echo "✓ $IMAGE prêt"
