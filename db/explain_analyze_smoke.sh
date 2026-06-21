#!/usr/bin/env bash
# db/explain_analyze_smoke.sh — DB-T024.b : smoke EXPLAIN ANALYZE CI (5 requêtes critiques)
# Issue : jips/nubiadoc#2319. Réf. : jips/nubiadoc#2238.
#
# Exécute EXPLAIN ANALYZE sur les 5 requêtes critiques et signale tout Seq Scan
# inattendu sur une table tenant (indique un index manquant ou des stats obsolètes).
#
# Usage manuel :
#   cd db
#   cp .env.example .env          # adapter PGHOST/PGPORT/DB_NAME si besoin
#   export $(grep -v '^#' .env | xargs)
#   bash explain_analyze_smoke.sh
#
#   # Avec une base peuplée (plan réaliste) :
#   make reset && make seed && bash explain_analyze_smoke.sh
#
# Variables d'environnement :
#   APP_DATABASE_URL  — URL nubia_app (NOSUPERUSER, NOBYPASSRLS) — RLS active.
#                       Défaut : postgres://nubia_app@${PGHOST:-localhost}:${PGPORT:-5432}/${DB_NAME:-nubia}
#   CABINET_ID        — UUID cabinet pour SET LOCAL app.current_cabinet_id (GUC RLS).
#                       Peut être fictif : le plan est évalué même avec 0 lignes retournées.
#                       Défaut : 00000000-0000-0000-0000-000000000000
#
# Interprétation :
#   [OK]   aucun Seq Scan sur la requête → index utilisé.
#   [FAIL] Seq Scan détecté → index manquant ou table trop petite pour l'optimiseur.
#          Sur une base vide / très peu de données, les Seq Scans sont attendus ;
#          l'alerte prend tout son sens sur une base de staging / prod.
#
# Codes de sortie :
#   0 — aucun Seq Scan détecté (toutes les requêtes OK).
#   1 — au moins un Seq Scan détecté (au moins un FAIL).

set -euo pipefail

APP_DATABASE_URL="${APP_DATABASE_URL:-postgres://nubia_app@${PGHOST:-localhost}:${PGPORT:-5432}/${DB_NAME:-nubia}}"
CABINET_ID="${CABINET_ID:-00000000-0000-0000-0000-000000000000}"

warnings=0
failed_plans=""

# Lance EXPLAIN ANALYZE dans une transaction anonyme (BEGIN…ROLLBACK).
# Affiche une ligne par requête : [OK] ou [FAIL] + libellé.
# Les plans des requêtes en FAIL sont accumulés pour affichage en fin de script.
# $1 : libellé affiché. $2 : corps SQL (SELECT uniquement).
run_explain() {
  local label="$1"
  local sql="$2"
  local plan

  plan=$(printf 'BEGIN;\nSET LOCAL app.current_cabinet_id = '"'"'%s'"'"';\n%s\nROLLBACK;\n' \
    "${CABINET_ID}" "${sql}" \
    | psql -v ON_ERROR_STOP=1 --no-psqlrc --no-align --tuples-only "${APP_DATABASE_URL}" 2>&1)

  if echo "${plan}" | grep -q "Seq Scan"; then
    printf "[FAIL] %s\n" "${label}"
    warnings=$((warnings + 1))
    failed_plans="${failed_plans}--- ${label} ---\n${plan}\n\n"
  else
    printf "[OK]   %s\n" "${label}"
  fi
}

echo "=== EXPLAIN ANALYZE smoke — 5 requêtes critiques ==="
echo "    APP_DATABASE_URL : ${APP_DATABASE_URL}"
echo "    CABINET_ID       : ${CABINET_ID}"
echo ""

# 1. Agenda — RDV sur 7 jours glissants (filtre cabinet_id + starts_at)
run_explain "agenda — appointment (7 jours)" "
EXPLAIN ANALYZE
SELECT id, patient_id, starts_at, ends_at, status
FROM   appointment
WHERE  cabinet_id = '${CABINET_ID}'
  AND  starts_at >= now()
  AND  starts_at <  now() + interval '7 days'
  AND  deleted_at IS NULL
ORDER  BY starts_at;"

# 2. Liste patients du cabinet (filtre cabinet_id, tri nom, pagination)
run_explain "patients list — patient (top 50)" "
EXPLAIN ANALYZE
SELECT id, first_name, last_name, created_at
FROM   patient
WHERE  cabinet_id = '${CABINET_ID}'
  AND  deleted_at IS NULL
ORDER  BY last_name, first_name
LIMIT  50;"

# 3. Conversations ouvertes (filtre cabinet_id + status, tri date)
run_explain "conversations list — conversation (open)" "
EXPLAIN ANALYZE
SELECT id, patient_id, status, created_at
FROM   conversation
WHERE  cabinet_id = '${CABINET_ID}'
  AND  status = 'open'
ORDER  BY created_at DESC
LIMIT  20;"

# 4. File d'attente active (filtre cabinet_id + status, tri score)
run_explain "waiting list — waiting_list_entry (active)" "
EXPLAIN ANALYZE
SELECT id, patient_id, score, created_at
FROM   waiting_list_entry
WHERE  cabinet_id = '${CABINET_ID}'
  AND  status = 'active'
ORDER  BY score DESC, created_at;"

# 5. Devis du cabinet (filtre cabinet_id + soft-delete, tri date)
run_explain "devis — quote (non supprimés)" "
EXPLAIN ANALYZE
SELECT id, patient_id, status, total_amount, created_at
FROM   quote
WHERE  cabinet_id = '${CABINET_ID}'
  AND  deleted_at IS NULL
ORDER  BY created_at DESC
LIMIT  20;"

# Détails des plans en FAIL (utile pour le diagnostic en CI)
if [ -n "${failed_plans}" ]; then
  echo ""
  echo "=== Détails des FAIL ==="
  printf "%b" "${failed_plans}"
fi

echo ""
if [ "${warnings}" -eq 0 ]; then
  echo "[OK] Aucun Seq Scan détecté — 5/5 requêtes OK."
  exit 0
else
  echo "[FAIL] ${warnings}/5 requête(s) avec Seq Scan — voir détails ci-dessus."
  exit 1
fi
