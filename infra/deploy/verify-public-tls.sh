#!/usr/bin/env bash
# Health-check post-déploiement des domaines publics *.doc.nubia-link.com
# (Caddy hôte, hors LXC — bloc collé à la main depuis Caddyfile.snippet).
#
# Ce script ne peut PAS réparer le Caddy hôte (hors périmètre de ce repo/LXC,
# cf. infra/deploy/Caddyfile.snippet:2-3) : il rend juste une panne de bloc
# Caddy VISIBLE à CHAQUE déploiement (log CI), au lieu de dépendre d'une
# découverte QA manuelle qui peut prendre plusieurs jours. Root cause de la
# récidive répétée (#6116, #6139, #6160) sur reservation.doc.nubia-link.com :
# aucune vérification automatisée n'existait jusqu'ici.
#
# Non bloquant par défaut : appelé depuis build-and-deploy.sh avec `|| true`,
# car un souci DNS/réseau côté runner (déjà observé, cf. qa/ui-controls.md)
# ne doit pas faire échouer un déploiement dont le code est par ailleurs bon.
set -uo pipefail

DOMAINS="${PUBLIC_TLS_DOMAINS:-patient.doc.nubia-link.com praticien.doc.nubia-link.com secretariat.doc.nubia-link.com pharmacie.doc.nubia-link.com infirmiere.doc.nubia-link.com api.doc.nubia-link.com reservation.doc.nubia-link.com}"

failed=0
for domain in $DOMAINS; do
  code="$(curl -sS --max-time 10 -o /dev/null -w '%{http_code}' "https://${domain}/" 2>/dev/null)"
  if [ -n "$code" ] && [ "$code" != "000" ]; then
    echo "✅ https://${domain} -> ${code}"
  else
    echo "::warning::❌ https://${domain} injoignable en TLS — vérifier le bloc Caddy dédié sur l'hôte (infra/deploy/Caddyfile.snippet), récidive connue sur reservation.doc.nubia-link.com (#6116, #6139, #6160)"
    failed=1
  fi
done

exit "$failed"
