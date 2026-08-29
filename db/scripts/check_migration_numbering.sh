#!/usr/bin/env bash
# db/scripts/check_migration_numbering.sh — garde-fou anti-collision de numérotation.
#
# Contexte (#6128, récidive #4854/#5485) : deux PRs indépendantes (#6119, #6117)
# ont chacune ajouté une migration `0239_*.sql`. Chaque PR, testée isolément
# contre l'état de `main` au moment de son ouverture, ne voyait qu'UN seul
# fichier 0239 -> CI verte des deux côtés. Le doublon n'est apparu qu'APRÈS les
# deux merges séquentiels sur `main`, où `deploy.yml` l'a découvert en prod
# (ordre d'application non déterministe, cf. db/AGENTS.md règle 4 "numérotation
# continue") au lieu d'échouer loud et tôt.
#
# Ce script est un check statique (pas de DB requise) : il détecte tout numéro
# de migration dupliqué dans db/migrations/ et échoue immédiatement avec un
# message explicite. Appelé depuis db.yml (PR) ET deploy.yml (push main) pour
# couvrir aussi bien le cas mono-PR que le cas de collision post-merge entre
# deux PRs qui se sont chacune crues seules.
set -euo pipefail

MIG_DIR="${1:-db/migrations}"

dups="$(
  find "$MIG_DIR" -maxdepth 1 -name '*.sql' -printf '%f\n' \
    | grep -oE '^[0-9]+' \
    | sort \
    | uniq -d
)"

if [ -n "$dups" ]; then
  echo "::error::Collision de numérotation de migration détectée dans $MIG_DIR"
  while IFS= read -r n; do
    files="$(find "$MIG_DIR" -maxdepth 1 -name "${n}_*.sql" -printf '%f, ' | sed 's/, $//')"
    echo "::error::  numéro ${n} partagé par : ${files}"
  done <<< "$dups"
  echo "::error::Migrations forward-only à numérotation continue (db/AGENTS.md règle 4) : renumérote l'une des deux (dernier numéro existant + 1) et repush."
  exit 1
fi

echo "✓ numérotation des migrations continue, aucune collision ($MIG_DIR)"
