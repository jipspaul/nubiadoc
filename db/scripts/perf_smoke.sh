#!/usr/bin/env bash
# db/scripts/perf_smoke.sh — Smoke test EXPLAIN ANALYZE sur 5 queries critiques.
#
# Usage manuel :
#   cd <racine-du-repo>
#   db/scripts/perf_smoke.sh
#   PGHOST=localhost PGPORT=5432 PGDATABASE=nubia PGUSER=nubia_app db/scripts/perf_smoke.sh
#
# Prérequis : base migrée (`cd db && make migrate`), rôle nubia_app accessible.
# Connexion  : variables PGHOST / PGPORT / PGDATABASE / PGUSER (défauts ci-dessous).
#
# Sortie :
#   OK    <query>  — index utilisé (ou Seq Scan toléré, table < seuil)
#   FAIL  <query>  — Seq Scan sur table estimée > SEQ_THRESHOLD lignes
#   ERROR <query>  — psql a échoué (connexion, table absente…)
# Exit 0 si tout est OK, exit 1 dès le premier FAIL ou ERROR.
#
# Règle de seuil : en dev/CI le planner choisit légitimement un Seq Scan
# quand la table est petite (reltuples ≤ SEQ_THRESHOLD). L'alerte est réservée
# aux environnements où la table est volumineuse et un Seq Scan serait coûteux.

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
PGHOST="${PGHOST:-localhost}"
PGPORT="${PGPORT:-5432}"
PGDATABASE="${PGDATABASE:-nubia}"
PGUSER="${PGUSER:-nubia_app}"
SEQ_THRESHOLD=10000

# UUID factice : aucune donnée réelle ne correspond — le plan s'exécute en 0 ms.
FAKE_CABINET="00000000-0000-0000-0000-000000000001"
FAKE_PRACT="00000000-0000-0000-0000-000000000002"

PSQL="psql --no-psqlrc -h ${PGHOST} -p ${PGPORT} -U ${PGUSER} -d ${PGDATABASE} -tAq"

PASS=0
FAIL=0
ERRORS=0

# ---------------------------------------------------------------------------
# check_query <label> <table> <sql>
# ---------------------------------------------------------------------------
check_query() {
    local label="$1" table="$2" sql="$3"

    # Exécuter EXPLAIN ANALYZE dans une transaction rollbackée (pas d'effet de bord).
    local plan
    if ! plan=$(${PSQL} <<SQL 2>&1
BEGIN;
SET LOCAL app.current_cabinet_id = '${FAKE_CABINET}';
EXPLAIN ANALYZE ${sql};
ROLLBACK;
SQL
    ); then
        printf "ERROR %-28s — psql a échoué\n" "${label}"
        ERRORS=$((ERRORS + 1))
        return
    fi

    # Nombre de lignes estimées pour la table dans les stats du planner.
    local reltuples
    reltuples=$(${PSQL} -c \
        "SELECT greatest(reltuples::bigint, 0) FROM pg_class WHERE relname = '${table}' LIMIT 1" \
        2>/dev/null) || reltuples=0
    reltuples="${reltuples:-0}"

    if echo "${plan}" | grep -q "Seq Scan on ${table}"; then
        if [ "${reltuples}" -gt "${SEQ_THRESHOLD}" ]; then
            printf "FAIL  %-28s — Seq Scan sur %s (reltuples=%s > %s)\n" \
                "${label}" "${table}" "${reltuples}" "${SEQ_THRESHOLD}"
            FAIL=$((FAIL + 1))
        else
            printf "OK    %-28s — Seq Scan toléré (reltuples=%s ≤ %s)\n" \
                "${label}" "${reltuples}" "${SEQ_THRESHOLD}"
            PASS=$((PASS + 1))
        fi
    else
        printf "OK    %-28s — index utilisé\n" "${label}"
        PASS=$((PASS + 1))
    fi
}

# ---------------------------------------------------------------------------
# 5 queries critiques
# ---------------------------------------------------------------------------

# 1. Agenda — rendez-vous du jour pour un praticien
#    Index attendu : appointment_practitioner_time_idx (cabinet_id, practitioner_id, starts_at)
check_query "agenda" "appointment" \
    "SELECT id, patient_id, starts_at, status
       FROM appointment
      WHERE cabinet_id       = '${FAKE_CABINET}'
        AND practitioner_id  = '${FAKE_PRACT}'
        AND starts_at >= now()
        AND starts_at <  now() + interval '1 day'
      ORDER BY starts_at"

# 2. Liste des patients du cabinet
#    Index attendu : patient_cabinet_idx (cabinet_id)
check_query "patients_list" "patient" \
    "SELECT id, first_name, last_name, created_at
       FROM patient
      WHERE cabinet_id = '${FAKE_CABINET}'
        AND deleted_at IS NULL
      ORDER BY last_name, first_name"

# 3. Liste des conversations du cabinet
#    Index attendu : conversation_cabinet_patient_idx (cabinet_id, patient_id)
check_query "conversations_list" "conversation" \
    "SELECT id, patient_id, created_at
       FROM conversation
      WHERE cabinet_id = '${FAKE_CABINET}'
        AND deleted_at IS NULL
      ORDER BY created_at DESC"

# 4. File d'attente active
#    Index attendu : waiting_list_active_idx (cabinet_id, status)
check_query "waiting_list" "waiting_list_entry" \
    "SELECT id, patient_id, status, created_at
       FROM waiting_list_entry
      WHERE cabinet_id = '${FAKE_CABINET}'
        AND status     = 'active'
      ORDER BY created_at"

# 5. Devis ouverts du cabinet
#    Index attendu : quote_cabinet_status_idx (cabinet_id, status)
check_query "devis" "quote" \
    "SELECT id, patient_id, status, created_at
       FROM quote
      WHERE cabinet_id = '${FAKE_CABINET}'
        AND status IN ('draft','sent','accepted')
      ORDER BY created_at DESC"

# ---------------------------------------------------------------------------
# Résumé
# ---------------------------------------------------------------------------
echo ""
printf "Résultat : %d OK — %d FAIL — %d ERREUR(S)\n" "${PASS}" "${FAIL}" "${ERRORS}"

[ "${FAIL}" -eq 0 ] && [ "${ERRORS}" -eq 0 ] && exit 0 || exit 1
