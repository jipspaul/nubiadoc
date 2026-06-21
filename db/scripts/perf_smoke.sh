#!/usr/bin/env bash
# db/scripts/perf_smoke.sh — DB-T024.a : smoke perf EXPLAIN ANALYZE (5 requêtes critiques)
# Issue : jips/nubiadoc#2318. Réf. : jips/nubiadoc#2238.
#
# Exécute EXPLAIN ANALYZE sur les 5 requêtes critiques et signale les Seq Scan
# uniquement sur les tables dépassant ROW_THRESHOLD lignes (défaut : 10 000).
# Sur une base vide ou de petite taille, les Seq Scans sont normaux et acceptés.
#
# Usage manuel :
#   cd db
#   cp .env.example .env          # adapter PGHOST/PGPORT/DB_NAME si besoin
#   export $(grep -v '^#' .env | xargs)
#   bash scripts/perf_smoke.sh
#
#   # Avec une base peuplée (plan réaliste) :
#   make reset && make seed && bash scripts/perf_smoke.sh
#
# Variables d'environnement :
#   APP_DATABASE_URL  — URL nubia_app (NOSUPERUSER, NOBYPASSRLS) — RLS active.
#                       Défaut : postgres://nubia_app@${PGHOST:-localhost}:${PGPORT:-5432}/${DB_NAME:-nubia}
#   CABINET_ID        — UUID cabinet pour SET LOCAL app.current_cabinet_id (GUC RLS).
#                       Peut être fictif : le plan est évalué même avec 0 lignes retournées.
#                       Défaut : 00000000-0000-0000-0000-000000000000
#   ROW_THRESHOLD     — Seuil en nombre de lignes (estimé pg_class.reltuples) au-dessus
#                       duquel un Seq Scan est considéré problématique.
#                       Défaut : 10000
#
# Interprétation :
#   [OK]   aucun Seq Scan, ou Seq Scan sur table petite (< ROW_THRESHOLD) → acceptable.
#   [FAIL] Seq Scan sur table avec > ROW_THRESHOLD lignes → index manquant ou stats obsolètes.
#
# Codes de sortie :
#   0 — aucun Seq Scan problématique détecté.
#   1 — au moins un Seq Scan sur table > ROW_THRESHOLD lignes.

set -euo pipefail

APP_DATABASE_URL="${APP_DATABASE_URL:-postgres://nubia_app@${PGHOST:-localhost}:${PGPORT:-5432}/${DB_NAME:-nubia}}"
CABINET_ID="${CABINET_ID:-00000000-0000-0000-0000-000000000000}"
ROW_THRESHOLD="${ROW_THRESHOLD:-10000}"

fails=0
failed_details=""

# Retourne l'estimation du nombre de lignes d'une table (pg_class.reltuples).
# Renvoie 0 si la table est introuvable ou si la requête échoue.
table_row_estimate() {
  local table="$1"
  psql --no-psqlrc --no-align --tuples-only "${APP_DATABASE_URL}" \
    -c "SELECT GREATEST(reltuples::bigint, 0) FROM pg_class WHERE relname = '${table}';" \
    2>/dev/null | head -1 | tr -d '[:space:]' || echo 0
}

# Lance EXPLAIN ANALYZE dans une transaction anonyme (BEGIN…ROLLBACK).
# Signale [FAIL] uniquement si Seq Scan ET table > ROW_THRESHOLD lignes.
# $1 : libellé affiché. $2 : nom de la table principale (pour vérification du seuil). $3 : corps SQL.
run_explain() {
  local label="$1"
  local main_table="$2"
  local sql="$3"
  local plan

  plan=$(printf 'BEGIN;\nSET LOCAL app.current_cabinet_id = '"'"'%s'"'"';\n%s\nROLLBACK;\n' \
    "${CABINET_ID}" "${sql}" \
    | psql -v ON_ERROR_STOP=1 --no-psqlrc --no-align --tuples-only "${APP_DATABASE_URL}" 2>&1)

  if echo "${plan}" | grep -q "Seq Scan"; then
    local rows
    rows=$(table_row_estimate "${main_table}")
    rows="${rows:-0}"

    if [ "${rows}" -gt "${ROW_THRESHOLD}" ]; then
      printf "[FAIL] %s  (Seq Scan, ~%s lignes > seuil %s)\n" "${label}" "${rows}" "${ROW_THRESHOLD}"
      fails=$((fails + 1))
      failed_details="${failed_details}--- ${label} (~${rows} lignes) ---\n${plan}\n\n"
    else
      printf "[OK]   %s  (Seq Scan accepté : ~%s lignes ≤ seuil %s)\n" "${label}" "${rows}" "${ROW_THRESHOLD}"
    fi
  else
    printf "[OK]   %s\n" "${label}"
  fi
}

echo "=== perf_smoke — EXPLAIN ANALYZE sur 5 requêtes critiques ==="
echo "    APP_DATABASE_URL : ${APP_DATABASE_URL}"
echo "    CABINET_ID       : ${CABINET_ID}"
echo "    ROW_THRESHOLD    : ${ROW_THRESHOLD}"
echo ""

# 1. Agenda — RDV sur 7 jours glissants (filtre cabinet_id + starts_at)
run_explain \
  "agenda — appointment (7 jours)" \
  "appointment" \
  "EXPLAIN ANALYZE
SELECT id, patient_id, starts_at, ends_at, status
FROM   appointment
WHERE  cabinet_id = '${CABINET_ID}'
  AND  starts_at >= now()
  AND  starts_at <  now() + interval '7 days'
  AND  deleted_at IS NULL
ORDER  BY starts_at;"

# 2. Liste patients du cabinet (filtre cabinet_id, tri nom, pagination)
run_explain \
  "patients list — patient (top 50)" \
  "patient" \
  "EXPLAIN ANALYZE
SELECT id, first_name, last_name, created_at
FROM   patient
WHERE  cabinet_id = '${CABINET_ID}'
  AND  deleted_at IS NULL
ORDER  BY last_name, first_name
LIMIT  50;"

# 3. Conversations ouvertes (filtre cabinet_id + status, tri date)
run_explain \
  "conversations list — conversation (open)" \
  "conversation" \
  "EXPLAIN ANALYZE
SELECT id, patient_id, status, created_at
FROM   conversation
WHERE  cabinet_id = '${CABINET_ID}'
  AND  status = 'open'
ORDER  BY created_at DESC
LIMIT  20;"

# 4. File d'attente active (filtre cabinet_id + status, tri score)
run_explain \
  "waiting list — waiting_list_entry (active)" \
  "waiting_list_entry" \
  "EXPLAIN ANALYZE
SELECT id, patient_id, score, created_at
FROM   waiting_list_entry
WHERE  cabinet_id = '${CABINET_ID}'
  AND  status = 'active'
ORDER  BY score DESC, created_at;"

# 5. Devis du cabinet (filtre cabinet_id + soft-delete, tri date)
run_explain \
  "devis — quote (non supprimés)" \
  "quote" \
  "EXPLAIN ANALYZE
SELECT id, patient_id, status, total_amount, created_at
FROM   quote
WHERE  cabinet_id = '${CABINET_ID}'
  AND  deleted_at IS NULL
ORDER  BY created_at DESC
LIMIT  20;"

# Détail des plans FAIL (diagnostic en CI)
if [ -n "${failed_details}" ]; then
  echo ""
  echo "=== Détails des FAIL ==="
  printf "%b" "${failed_details}"
fi

echo ""
if [ "${fails}" -eq 0 ]; then
  echo "[OK] Aucun Seq Scan problématique — 5/5 requêtes OK."
  exit 0
else
  echo "[FAIL] ${fails}/5 requête(s) avec Seq Scan sur table > ${ROW_THRESHOLD} lignes."
  exit 1
fi
