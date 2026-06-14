#!/usr/bin/env bash
# scripts/run-flows.sh — exécute les flows Playwright contre la dev-stack.
#
# Prérequis : ../scripts/dev-stack.sh actif (API :38030, web :38040,
#             seed.sql + seed_e2e.sql chargés — fait automatiquement par dev-stack).
#
# Trois passes (les comptes seed multi-contexte changent le comportement du
# login : un compte multi-contexte reçoit un token « nu » + context_required,
# incompatible avec les flows mono-contexte — d'où la séparation) :
#   1. mono-contexte  : tous les flows sauf ED5 / ES5 / EW52
#   2. multi-secrétariat (Lyon A+B)      : ES5 + EW52
#   3. multi-établissement (Lyon+Annecy) : ED5
#
# Usage : ./scripts/run-flows.sh [args playwright supplémentaires]

set -uo pipefail
cd "$(dirname "$0")/.."

# ── Fixtures réelles (db/seed/seed.sql + seed_e2e.sql) ──────────────────────
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

FAIL=0

echo "── Pass 1/3 : flows mono-contexte ─────────────────────────────────"
# --workers=1 : les flows mutent un état backend partagé (cabinet, créneaux,
# assignations) ; les exécuter en série évite les courses inter-tests.
env "${BASE_ENV[@]}" npx playwright test --project=flows --workers=1 \
  --grep-invert 'ED5|ES5|EW52' "$@" || FAIL=1

echo "── Pass 2/3 : multi-secrétariat (ES5 + EW52) ──────────────────────"
env "${BASE_ENV[@]}" \
  SEED_SECRETARY_EMAIL=secretaire-multi.demo@nubia.test \
  SEED_SECRETARY_PASSWORD='NubiaDemo1!' \
  npx playwright test --project=flows --workers=1 --grep 'ES5|EW52' "$@" || FAIL=1

echo "── Pass 3/3 : multi-établissement (ED5) ───────────────────────────"
env "${BASE_ENV[@]}" \
  SEED_PRACTITIONER_EMAIL=praticien-multi.demo@nubia.test \
  SEED_PRACTITIONER_PASSWORD='NubiaDemo1!' \
  SEED_CABINET_A_ID=11111111-1111-1111-1111-111111111111 \
  SEED_CABINET_B_ID=22222222-2222-2222-2222-222222222222 \
  SEED_SECRETARIAT_A_ID=19870000-0000-0000-0000-000000000001 \
  SEED_SECRETARIAT_B_ID=29870000-0000-0000-0000-000000000001 \
  SEED_SECRETARY_A_EMAIL=secretaire-a.demo@nubia.test \
  SEED_SECRETARY_A_PASSWORD='NubiaDemo1!' \
  SEED_SECRETARY_B_EMAIL=secretaire-annecy.demo@nubia.test \
  SEED_SECRETARY_B_PASSWORD='NubiaDemo1!' \
  npx playwright test --project=flows --workers=1 --grep 'ED5' "$@" || FAIL=1

exit $FAIL
