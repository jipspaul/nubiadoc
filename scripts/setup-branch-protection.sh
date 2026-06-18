#!/usr/bin/env bash
# scripts/setup-branch-protection.sh — ajoute "/ front-test (pull_request)"
# comme required status check sur la branch protection `main`.
#
# Nécessite un token Forgejo avec les droits admin sur le dépôt (owner ou
# collaborateur avec "admin write"). Le token des agents CI (write:push) ne
# suffit pas — utiliser le token d'un propriétaire du dépôt.
#
# Pré-requis : curl, jq
#
# Usage :
#   FORGEJO_TOKEN=xxxxx ./scripts/setup-branch-protection.sh
#   FORGEJO_TOKEN=xxxxx FORGEJO_URL=http://127.0.0.1:3000 ./scripts/setup-branch-protection.sh
#   FORGEJO_TOKEN=xxxxx ./scripts/setup-branch-protection.sh --dry-run
set -euo pipefail

URL="${FORGEJO_URL:-http://forgejo.forgejo.svc.cluster.local:3000}"
REPO="${FORGEJO_REPO:-jips/nubiadoc}"
BRANCH="main"
NEW_CHECK="/ front-test (pull_request)"
DRY=0
[[ "${1:-}" == "--dry-run" ]] && DRY=1

if [[ -z "${FORGEJO_TOKEN:-}" ]]; then
  echo "ERREUR : FORGEJO_TOKEN non défini." >&2
  exit 1
fi

AUTH=(-H "Authorization: token $FORGEJO_TOKEN")
BASE="$URL/api/v1/repos/$REPO"

echo "=== Branch protection — $REPO / $BRANCH ==="

# 1. Récupérer la protection existante (si elle existe)
echo "→ GET $BASE/branch_protections/$BRANCH"
CURRENT=$(curl -s "${AUTH[@]}" "$BASE/branch_protections/$BRANCH")

if echo "$CURRENT" | jq -e '.message' >/dev/null 2>&1; then
  MSG=$(echo "$CURRENT" | jq -r '.message')
  if echo "$MSG" | grep -q "404\|Not Found\|does not exist"; then
    echo "  Aucune protection existante — création via POST."
    METHOD="POST"
    ENDPOINT="$BASE/branch_protections"
    EXISTING_CONTEXTS="[]"
  else
    echo "ERREUR API : $MSG" >&2
    echo "Vérifier que le token a les droits admin sur le dépôt." >&2
    exit 1
  fi
else
  METHOD="PATCH"
  ENDPOINT="$BASE/branch_protections/$BRANCH"
  EXISTING_CONTEXTS=$(echo "$CURRENT" | jq '[.required_status_check_contexts // [] | .[]]')
  echo "  Protection existante trouvée."
  echo "  Contexts actuels : $EXISTING_CONTEXTS"
fi

# 2. Fusionner le nouveau context dans la liste (idempotent)
MERGED=$(echo "$EXISTING_CONTEXTS" | jq --arg c "$NEW_CHECK" \
  'if any(. == $c) then . else . + [$c] end')

echo "  Contexts après merge : $MERGED"

if [[ "$DRY" -eq 1 ]]; then
  echo "  [dry-run] Pas d'envoi."
  echo ""
  echo "Commande qui serait exécutée :"
  echo "  curl -X $METHOD \"$ENDPOINT\" \\"
  echo "    -H 'Authorization: token \$FORGEJO_TOKEN' \\"
  echo "    -H 'Content-Type: application/json' \\"
  if [[ "$METHOD" == "POST" ]]; then
    echo "    -d '{\"branch_name\": \"$BRANCH\", \"required_status_check_contexts\": $MERGED}'"
  else
    echo "    -d '{\"required_status_check_contexts\": $MERGED}'"
  fi
  exit 0
fi

# 3. Appliquer
if [[ "$METHOD" == "POST" ]]; then
  PAYLOAD=$(jq -n \
    --arg b "$BRANCH" \
    --argjson c "$MERGED" \
    '{"branch_name": $b, "required_status_check_contexts": $c, "enable_status_check": true}')
else
  PAYLOAD=$(jq -n \
    --argjson c "$MERGED" \
    '{"required_status_check_contexts": $c, "enable_status_check": true}')
fi

echo "→ $METHOD $ENDPOINT"
RESULT=$(curl -s -X "$METHOD" "${AUTH[@]}" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" \
  "$ENDPOINT")

if echo "$RESULT" | jq -e '.message' >/dev/null 2>&1; then
  echo "ERREUR : $(echo "$RESULT" | jq -r '.message')" >&2
  exit 1
fi

echo "✓ Branch protection mise à jour."
echo "  Contexts requis :"
echo "$RESULT" | jq '.required_status_check_contexts'
