#!/usr/bin/env bash
# Lance la web-console Nubia en mode développement (install + check API + npm run dev).
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

if [ ! -d node_modules ]; then
  echo "node_modules/ absent — lancement de npm install..."
  npm install --silent
fi

if ! curl -sf http://localhost:3000/v1/health > /dev/null 2>&1; then
  echo "WARN: API Nubia inaccessible sur :3000. Lance d'abord \`cargo run --release\` dans api/"
fi

echo "--> ouvre http://localhost:4321/"
exec npm run dev
