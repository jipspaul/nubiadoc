# Ledger de conformité design-v2 — flutter-qa-agent

> Une ligne par écran comparé à SA maquette v2 (INDEX.md fait foi pour la correspondance).
> Rotation : écrans JAMAIS comparés d'abord, puis les plus anciens. Quota dur : ≥5 écrans/ronde.

| app | écran/route | maquette | verdict | divergences | last_check |
|---|---|---|---|---|---|
| secretariat | /stock (Demandes de stock) | Secretariat Stock v2.html | conforme | Aucune — 4 compteurs (en attente/à recevoir/honorées ce mois/pharmacies partenaires), libellés FR, recherche + facettes de statut, pill "Acceptée" en progress (pas warning, contrairement à une note de maquette antérieure déjà corrigée) | 2026-09-02T00:00:00Z |
| secretariat | /patients (Fiches patients) | Secretariat Fiches patients v2.html | conforme | Aucune — 3 facettes (Impayés/Alertes/Sans RDV à venir) avec compteurs, raccourci ⌘N sur "Nouveau patient", colonnes Patient/Contact/Dernière visite/Solde/Alertes conformes | 2026-09-02T00:00:00Z |
| secretariat | /cabinet-payouts (Encaissements) | Secretariat Encaissements v2.html | conforme | Aucune — bandeau "Connecter Stripe" + "Exporter (CSV)" présents dans la barre d'outils comme prescrit, garde `payouts.isEmpty` légitime sur l'export | 2026-09-02T00:00:00Z |
| secretariat | /team-messages (Messagerie interne) | Secretariat Messagerie interne v2.html | conforme (rendu) — mécanique partiellement stub | "Mentionner" fonctionne réellement (insère @, confirmé), "Joindre un patient, un devis…" et "Épingler" sont des stubs volontairement documentés "à venir" dans le code (pas un bug caché, transparence assumée) — non re-signalé (déjà connu, pas de nouvelle régression) | 2026-09-02T00:00:00Z |
| praticien | /lab-work-orders (Travaux de laboratoire) | Praticien Travaux labo v2.html | DIVERGENT (mécanique cassée) | Rendu correct (4 KPIs bons en cours/en retard/attendus cette semaine/engagé, boutons Actualiser/Nouveau bon) MAIS écran INUTILISABLE : "Erreur de décodage de la réponse." s'affiche systématiquement dès qu'un bon n'a pas de quote_item_id (100% des bons en prod) — #6174 (P1) streamé ce run, cast Dart non-nullable sur tooth_fdi/work_nature que le backend documente comme optionnels | 2026-09-02T00:00:00Z |
| pharmacie | / (File des commandes) | Pharmacie File des commandes v2.html | conforme | Aucune — 4 KPIs (à préparer d'urgence/en préparation/prêtes à retirer/délivrées aujourd'hui), 4 filtres AVEC compteurs (déjà fixé vs note de maquette antérieure), timestamp "Mise à jour il y a Xs" auto-refresh présent, colonne latérale présente | 2026-09-02T00:00:00Z |
