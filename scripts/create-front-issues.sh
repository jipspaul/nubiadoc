#!/usr/bin/env bash
# scripts/create-front-issues.sh — crée les issues Forgejo du plan front (FR#).
#
# Source des issues : scripts/front-issues.json (cf. web-console/PLAN-ATOMIC.md §I).
# Idempotent : une issue dont le titre existe déjà (ouverte ou fermée) est ignorée.
# Crée au besoin les labels manquants (area:flutter-front, type:*, prio:*).
#
# Pré-requis : un token Forgejo avec scope `write:issue`.
#
# Usage :
#   FORGEJO_TOKEN=xxxxx ./scripts/create-front-issues.sh            # crée tout
#   FORGEJO_TOKEN=xxxxx ./scripts/create-front-issues.sh --dry-run  # n'envoie rien
#   FORGEJO_TOKEN=xxxxx MAX=15 ./scripts/create-front-issues.sh     # limite (cap planner)
#   FORGEJO_TOKEN=xxxxx FILTER='FR0|FR1' ./scripts/create-front-issues.sh
#
# Surcharges env :
#   FORGEJO_URL  (http://127.0.0.1:3000)
#   FORGEJO_REPO (jips/nubiadoc)
#   MAX          (0 = pas de limite)
#   FILTER       (regex egrep sur l'id FR, ex. 'FR0|FR1')
set -euo pipefail

URL="${FORGEJO_URL:-http://127.0.0.1:3000}"
REPO="${FORGEJO_REPO:-jips/nubiadoc}"
MAX="${MAX:-0}"
FILTER="${FILTER:-}"
DRY=0
[[ "${1:-}" == "--dry-run" ]] && DRY=1

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ISSUES_JSON="$HERE/front-issues.json"

if [[ -z "${FORGEJO_TOKEN:-}" ]]; then
  echo "✖ FORGEJO_TOKEN manquant. Crée un token (Settings → Applications) avec scope write:issue." >&2
  exit 1
fi
command -v jq >/dev/null  || { echo "✖ jq requis" >&2; exit 1; }
[[ -f "$ISSUES_JSON" ]]   || { echo "✖ introuvable: $ISSUES_JSON" >&2; exit 1; }

API="$URL/api/v1"
AUTH=(-H "Authorization: token $FORGEJO_TOKEN" -H "Content-Type: application/json")

api() { # method path [data]
  local m="$1" p="$2" d="${3:-}"
  if [[ -n "$d" ]]; then curl -fsS "${AUTH[@]}" -X "$m" "$API$p" -d "$d"
  else curl -fsS "${AUTH[@]}" -X "$m" "$API$p"; fi
}

echo "▸ Forgejo $URL · repo $REPO · dry-run=$DRY"

# --- 1. labels : récupère existants, crée manquants, construit la map name->id ---
declare -A LABEL_ID
while IFS=$'\t' read -r id name; do LABEL_ID["$name"]="$id"; done < <(
  api GET "/repos/$REPO/labels?limit=200" | jq -r '.[] | "\(.id)\t\(.name)"'
)
ensure_label() {
  local name="$1"
  [[ -n "${LABEL_ID[$name]:-}" ]] && return 0
  if [[ "$DRY" == "1" ]]; then echo "  (dry) label à créer: $name"; LABEL_ID["$name"]=0; return 0; fi
  local color="#7e57c2"
  case "$name" in
    prio:P0) color="#d73a4a";; prio:P1) color="#fbca04";; prio:P2) color="#0e8a16";;
    type:feature) color="#1d76db";; type:test) color="#5319e7";; type:chore) color="#cccccc";;
    area:flutter-front) color="#02569B";;
  esac
  local lid
  lid="$(api POST "/repos/$REPO/labels" "$(jq -nc --arg n "$name" --arg c "$color" '{name:$n,color:$c}')" | jq -r '.id')"
  LABEL_ID["$name"]="$lid"
  echo "  + label créé: $name ($lid)"
}

# --- 2. titres existants (évite doublons) ---
declare -A SEEN
while IFS= read -r t; do SEEN["$t"]=1; done < <(
  api GET "/repos/$REPO/issues?state=all&type=issues&limit=1000" | jq -r '.[].title'
)

# --- 3. boucle de création ---
created=0; skipped=0; n=0
count="$(jq 'length' "$ISSUES_JSON")"
for ((i=0; i<count; i++)); do
  id="$(jq -r ".[$i].id" "$ISSUES_JSON")"
  [[ -n "$FILTER" ]] && ! echo "$id" | grep -qE "$FILTER" && continue
  title="$(jq -r ".[$i].title" "$ISSUES_JSON")"
  body="$(jq -r ".[$i].body" "$ISSUES_JSON")"

  if [[ -n "${SEEN[$title]:-}" ]]; then
    echo "= existe déjà, skip: $id"; ((skipped++)); continue
  fi
  if [[ "$MAX" != "0" && "$n" -ge "$MAX" ]]; then
    echo "▸ MAX=$MAX atteint — arrêt (relance pour la suite)."; break
  fi

  # résout les labels en ids
  mapfile -t lnames < <(jq -r ".[$i].labels[]" "$ISSUES_JSON")
  for ln in "${lnames[@]}"; do ensure_label "$ln"; done
  lids="["; sep=""
  for ln in "${lnames[@]}"; do lids+="$sep${LABEL_ID[$ln]}"; sep=","; done
  lids+="]"

  payload="$(jq -nc --arg t "$title" --arg b "$body" --argjson l "$lids" '{title:$t, body:$b, labels:$l}')"
  if [[ "$DRY" == "1" ]]; then
    echo "  (dry) créerait: $id — $title  [labels ${lnames[*]}]"
  else
    num="$(api POST "/repos/$REPO/issues" "$payload" | jq -r '.number')"
    echo "  + #$num  $id — $title"
  fi
  ((created++)); ((n++))
done

echo "▸ Terminé : $created créées, $skipped déjà présentes."
