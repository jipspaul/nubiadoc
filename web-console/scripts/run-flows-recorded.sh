#!/usr/bin/env bash
# scripts/run-flows-recorded.sh — exécute les 58 flows Playwright en enregistrant
# une VIDÉO + une TRACE de chaque test, puis fusionne le tout en un seul rapport
# HTML navigable (revue visuelle des parcours sans rejouer la suite ni tester à
# la main).
#
# Prérequis : ../scripts/dev-stack.sh actif (API :38030, web :38040).
# Usage : ./scripts/run-flows-recorded.sh [--headed]   (Chrome visible en live)
#         puis : npx playwright show-report   (ouvre le rapport)

set -uo pipefail
cd "$(dirname "$0")/.."

export PW_RECORD=1   # active video:on + trace:on (cf. playwright.config.ts)
EXTRA="$*"           # ex. --headed

BLOBS="blob-flows"
rm -rf "$BLOBS" playwright-report; mkdir -p "$BLOBS"

# Fixtures réelles communes (db/seed/seed.sql + seed_e2e.sql).
BASE_ENV=(
  SEED_PATIENT_EMAIL=marc.dubois@patient.test
  SEED_PATIENT_PASSWORD='Nubia2026!'
  SEED_PRACTITIONER_EMAIL=hugo.marin@cabinet-lyon.test
  SEED_PRACTITIONER_PASSWORD='Nubia2026!'
  SEED_SECRETARY_EMAIL=sonia.accueil@cabinet-lyon.test
  SEED_SECRETARY_PASSWORD='Nubia2026!'
  SEED_MANAGER_EMAIL=admin@cabinet-lyon.test
  SEED_MANAGER_PASSWORD='Nubia2026!'
  SEED_PRACTITIONER_ID=f0000000-0000-0000-0000-0000000000f1
  SEED_PRACTITIONER_TABLE_ID=c0000000-0000-0000-0000-0000000000c1
  SEED_PATIENT_ID=d0000000-0000-0000-0000-0000000000d1
  SEED_CABINET_ID=11111111-1111-1111-1111-111111111111
  SEED_SECRETARIAT_A_ID=19870000-0000-0000-0000-000000000001
  SEED_SECRETARIAT_B_ID=19870000-0000-0000-0000-000000000002
  SEED_PROVIDER_A_ID=f0000000-0000-0000-0000-0000000000f1
  SEED_PROVIDER_B_ID=f0000000-0000-0000-0000-0000000000f2
  SEED_SECRETARY_B_EMAIL=secretaire-b.demo@nubia.test
  SEED_SECRETARY_B_PASSWORD='NubiaDemo1!'
  SEED_MFA_EMAIL=patient.mfa@nubia.test
  SEED_MFA_PASSWORD='NubiaDemo1!'
  SEED_MFA_TOTP_SECRET=JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP
  SEED_RESET_EMAIL=patient.reset@nubia.test
  SEED_RESET_PASSWORD='NubiaDemo1!'
)

# shellcheck disable=SC2086
run_pass() { # $1=label, suivi des args playwright ; le reste de l'env via "${@:2}"
  local label="$1"; shift
  echo "── Enregistrement : $label ──────────────────────────────"
  PLAYWRIGHT_BLOB_OUTPUT_FILE="$BLOBS/$label.zip" \
    env "${BASE_ENV[@]}" "${PASS_ENV[@]}" \
    npx playwright test --project=flows --workers=1 --reporter=blob $EXTRA "$@" || true
}

PASS_ENV=()
run_pass mono --grep-invert 'ED5|ES5|EW52'

PASS_ENV=(SEED_SECRETARY_EMAIL=secretaire-multi.demo@nubia.test SEED_SECRETARY_PASSWORD='NubiaDemo1!')
run_pass multi-secretariat --grep 'ES5|EW52'

PASS_ENV=(
  SEED_PRACTITIONER_EMAIL=praticien-multi.demo@nubia.test SEED_PRACTITIONER_PASSWORD='NubiaDemo1!'
  SEED_CABINET_A_ID=11111111-1111-1111-1111-111111111111 SEED_CABINET_B_ID=22222222-2222-2222-2222-222222222222
  SEED_SECRETARIAT_A_ID=19870000-0000-0000-0000-000000000001 SEED_SECRETARIAT_B_ID=29870000-0000-0000-0000-000000000001
  SEED_SECRETARY_A_EMAIL=secretaire-a.demo@nubia.test SEED_SECRETARY_A_PASSWORD='NubiaDemo1!'
  SEED_SECRETARY_B_EMAIL=secretaire-annecy.demo@nubia.test SEED_SECRETARY_B_PASSWORD='NubiaDemo1!'
)
run_pass multi-etablissement --grep 'ED5'

echo "── Fusion des rapports ──────────────────────────────────"
npx playwright merge-reports --reporter html "$BLOBS"

echo
echo "✅ Rapport prêt. Ouvre-le avec :  npx playwright show-report"
echo "   (chaque test rejouable en vidéo + trace pas-à-pas)"
