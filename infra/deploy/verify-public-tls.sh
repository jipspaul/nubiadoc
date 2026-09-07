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
# Exit codes (#6685, 10e récidive) : le caller (build-and-deploy.sh) doit
# pouvoir distinguer deux situations bien différentes plutôt que de tout
# noyer sous un `|| true` inconditionnel comme avant :
#   0 : tous les domaines répondent.
#   1 : échec généralisé (aucun domaine, ou reservation ET au moins un autre
#       domaine de la MÊME IP/hôte) -> ressemble à un souci DNS/réseau côté
#       runner, pas à une régression de config -> reste non bloquant.
#   2 : reservation.doc.nubia-link.com SEUL est en échec alors que d'autres
#       domaines de la même IP répondent -> ça exclut un souci DNS/réseau
#       générique (cf. repro #6685 : "les 5 autres vhosts de la même IP
#       répondent normalement") -> c'est bien le bloc Caddy dédié qui manque
#       à nouveau sur l'hôte -> le caller doit échouer FORT (pas de `|| true`)
#       pour que ça reste visible au lieu de sauter en silence indéfiniment.
set -uo pipefail

DOMAINS="${PUBLIC_TLS_DOMAINS:-patient.doc.nubia-link.com praticien.doc.nubia-link.com secretariat.doc.nubia-link.com pharmacie.doc.nubia-link.com infirmiere.doc.nubia-link.com api.doc.nubia-link.com reservation.doc.nubia-link.com}"

ok=0
reservation_failed=0
other_failed=0
for domain in $DOMAINS; do
  code="$(curl -sS --max-time 10 -o /dev/null -w '%{http_code}' "https://${domain}/" 2>/dev/null)"
  if [ -n "$code" ] && [ "$code" != "000" ]; then
    echo "✅ https://${domain} -> ${code}"
    ok=$((ok + 1))
  else
    echo "::warning::❌ https://${domain} injoignable en TLS — vérifier le bloc Caddy dédié sur l'hôte (infra/deploy/Caddyfile.snippet), récidive connue sur reservation.doc.nubia-link.com (#6116, #6139, #6160, #6685)"
    if [ "$domain" = "reservation.doc.nubia-link.com" ]; then
      reservation_failed=1
    else
      other_failed=1
    fi
  fi
done

if [ "$reservation_failed" = "1" ] && [ "$other_failed" = "0" ] && [ "$ok" -gt 0 ]; then
  echo "::error::reservation.doc.nubia-link.com injoignable en TLS alors que les autres domaines de la même IP répondent — ce n'est pas un incident réseau du runner, le bloc Caddy dédié manque à nouveau sur l'hôte (#6116..#6553, 10e récidive #6685)."
  exit 2
fi

if [ "$reservation_failed" = "1" ] || [ "$other_failed" = "1" ]; then
  exit 1
fi
exit 0
