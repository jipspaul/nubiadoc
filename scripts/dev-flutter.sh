#!/usr/bin/env bash
# scripts/dev-flutter.sh — lance une app Flutter Nubia pointée sur l'API locale.
#
# Équivalent mobile/desktop de dev-web.sh : suppose que le backend tourne déjà
# (Postgres + API Rust) via `./scripts/dev-stack.sh` dans un autre terminal.
#
# Usage :
#   ./scripts/dev-flutter.sh [app] [device]
#     app     : patient (défaut) | pro | secretariat
#     device  : macos (défaut) | chrome | <deviceId> (voir `flutter devices`)
#
# Surcharges via env :
#   API_PORT (38030)  ·  API_BASE_URL (http://localhost:$API_PORT/v1)
#
# Exemples :
#   ./scripts/dev-flutter.sh                 # patient sur macOS
#   ./scripts/dev-flutter.sh pro chrome      # praticien dans Chrome
#   API_PORT=39000 ./scripts/dev-flutter.sh secretariat

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

APP_ARG="${1:-patient}"
DEVICE="${2:-macos}"
API_PORT="${API_PORT:-38030}"
# Le défaut prod inclut /v1 (cf. ApiConstants.baseUrl) → on le reproduit en local.
API_BASE_URL="${API_BASE_URL:-http://localhost:$API_PORT/v1}"

# puro gère le SDK Flutter ; fallback sur un flutter du PATH si absent.
if command -v puro >/dev/null 2>&1; then
  FLUTTER=(puro flutter)
else
  FLUTTER=(flutter)
fi

case "$APP_ARG" in
  patient)     APP_DIR="front/apps/app_patient" ;;
  pro|praticien|practicien) APP_DIR="front/apps/app_practicien" ;;
  secretariat|secretary)    APP_DIR="front/apps/app_secretariat" ;;
  *)
    echo "✗ app inconnue : '$APP_ARG' (attendu : patient | pro | secretariat)" >&2
    exit 1
    ;;
esac

# Vérif backend non-bloquante (comme dev-web.sh).
if ! curl -sf "http://localhost:$API_PORT/v1/health" >/dev/null 2>&1; then
  echo "⚠  API Nubia inaccessible sur :$API_PORT — lance d'abord ./scripts/dev-stack.sh"
  echo "   (on démarre quand même ; les appels backend échoueront tant que l'API est down)"
fi

echo "→ app    : $APP_ARG  ($APP_DIR)"
echo "→ device : $DEVICE"
echo "→ API    : $API_BASE_URL"
echo

cd "$ROOT/$APP_DIR"
exec "${FLUTTER[@]}" run -d "$DEVICE" --dart-define=API_BASE_URL="$API_BASE_URL"
