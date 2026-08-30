# Ledger des contrôles UI audités — flutter-qa-agent

> Une ligne par écran audité en profondeur (inventaire Semantics + activation de
> CHAQUE contrôle + verdict OK/MORT/CASSÉ/DÉSACTIVÉ). Alimenté au fil des rondes ;
> à la ronde suivante, commencer par les écrans jamais audités ou les plus anciens.
> Complète `explored-paths.md` (scénarios API/flux) — ce fichier-ci se concentre
> sur la mécanique bouton-par-bouton d'un écran donné.

| app | écran/route | inventoriés | activés | OK | morts | cassés | last_check |
|---|---|---|---|---|---|---|---|
| patient | / (dashboard) | 19 | 0 | - | - | - | 2026-08-28T22:00:00Z (inventaire seul, pas encore d'activation exhaustive) |
| patient | /profile (Profil) | 18 | 10 | 10 | 0 | 0 | 2026-08-28T22:13:00Z |
| patient | /profile/dependents (Mes proches) | 17+ (par proche) | 2 (Prendre RDV, Documents sur 1er proche) | 2 | 0 | 0 (mais data sous-jacente `pendingAccessRequests` cassée, cf. #6119) | 2026-08-28T22:14:00Z |
| patient | /oubliettes | 13 (docs listés) | 0 | - | - | - | 2026-08-28T22:12:00Z (rendu confirmé sain, dates relatives correctes — ancien bug #5736 fixé, pas re-testé bouton par bouton) |
| praticien | / + nav rail (11 items) | 12 (4 groupes + 8 boutons nav) | 4 (Tableau de bord, Agenda, Salle d'attente, Consultation via nav) | 4 | 0 | 0 | 2026-08-29T00:36:22Z |
| praticien | /lab-work-orders | 3 (Actualiser, Nouveau bon, Réessayer visible seulement en cas d'erreur réseau) | 2 (Actualiser, Nouveau bon) | 2 | 0 | 0 | 2026-08-29T00:36:22Z |
| praticien | /patients | 18 (17 fiches + Actualiser implicite) | 0 (inventaire seul, drill non fait ce run) | - | - | - | 2026-08-29T00:36:22Z |
| praticien | /consultation | 19 (3 filtres statut + 16 fiches) | 0 (inventaire seul) | - | - | - | 2026-08-29T00:36:22Z |
| praticien | /devis | 10 (fiches devis brouillon) | 0 (inventaire seul) | - | - | - | 2026-08-29T00:36:22Z |
| praticien | /stock-inventory | 24 (11 lignes stock + 11 boutons Mouvement + Actualiser) | 0 (inventaire seul) | - | - | - | 2026-08-29T00:36:22Z |
| secretariat | / (dashboard) + 16 routes | ~130 (agrégé sur 16 routes) | 0 (inventaire seul, navigation directe par URL, pas de clic exhaustif) | - | - | - | 2026-08-29T00:36:22Z |
| secretariat | /cabinet-payouts | 5 (2 nav mois, Actualiser, Exporter CSV, Connecter Stripe) | 1 (Exporter CSV — confirmé DÉSACTIVÉ légitimement, liste virements vide) | 1 | 0 | 0 | 2026-08-29T00:36:22Z |
| secretariat | /team-messages | 7 (Joindre/Épingler/Mentionner + input + Épingler liste) | 0 (stubs "à venir" documentés dans le code, pas activés ce run) | - | - | - | 2026-08-29T00:36:22Z |
| pharmacie | / (Commandes) + Stock/Messages/Devis | ~55 (agrégé sur 4 routes) | 0 (inventaire seul, navigation directe par URL) | - | - | - | 2026-08-29T00:36:22Z |

## Détail des activations « Profil » (2026-08-28T22:13:00Z)

Tous les contrôles suivants ont été cliqués individuellement (coordonnées du rect Semantics, viewport 390x844) et jugés **OK** (navigation observée ou changement d'état/requête réseau observé, aucune erreur console, aucune requête ≥400 nouvelle) :
- Notifications (cloche topbar)
- Modifier la photo de profil
- Modifier le téléphone
- Notifications RDV / Toutes les préférences
- Authentification biométrique (toggle)
- Mes devis & paiements
- Couverture santé
- Médecin traitant
- Mes proches
- Consentements

Note méthodologique : le premier passage de détection (basé sur `page.url()` avant/après clic) donnait un faux `navigated:false` pour tous car l'app utilise une navigation interne (Navigator push) qui NE change PAS l'URL affichée dans la barre d'adresse pour certains écrans (`/profile/dependents` › Prendre RDV/Documents ouvrent bien un sous-écran, confirmé par les NOUVELLES requêtes réseau observées et le nouveau texte Semantics, malgré une URL inchangée). Le critère fiable est donc **requête réseau nouvelle + texte Semantics changé**, pas l'URL seule.

## Détail « Mes proches » (2026-08-28T22:14:00Z)

- Bouton **Prendre RDV** (1er dépendant, "QAFlow Dep") : OK — ouvre la recherche de praticiens (17 praticiens listés, créneaux par jour), confirmé par nouvelles requêtes `GET /v1/search/providers` + `GET /v1/providers/:id/availability` (x17) et nouveau texte Semantics "Booker un RDV...".
- Bouton **Documents** (1er dépendant) : OK — ouvre la liste de documents du dépendant (paginée par curseur, 15 documents "Cette semaine"), confirmé par `GET /v1/documents?cursor=...` en cascade et texte Semantics "Mes documents / CETTE SEMAINE / 15 documents".
- **Chargement des invitations en attente (`pendingAccessRequests`) : CASSÉ silencieusement** — `GET /v1/account/access-requests` échoue systématiquement (404 backend, apparaît comme une erreur CORS côté navigateur). Le code Flutter absorbe l'échec (`fold` vers liste vide) donc l'écran ne plante pas visuellement, mais la fonctionnalité entière d'invitation d'un proche ADULTE est inerte. Voir issue **#6119** (P1, streamé cette ronde).

| pharmacie | / (Commandes) + nav Stock/Messages/Devis | 4 (nav) + 6 (filtres switch) | 4 nav + 4 filtres + 1 row action | 9 | 0 | 0 | 2026-08-29T06:15:00Z |
| pharmacie | /orders/:id/pickup | 3 (Retour, scan-related group, action bar) | 1 (Retour) | 1 | 0 | 0 | 2026-08-29T06:15:00Z |
| patient | / (dashboard, home hero + quick access) | 11 (Itinéraire, Préparer, À signer, À régler, 3 cards accès rapide, Mes documents, Ma pharmacie, Mes proches, Notifications bell) | 11 | 9 | 1 (Itinéraire, cf #6130) | 0 | 2026-08-29T06:25:00Z |
| patient | /pharmacy (Ma pharmacie) | 6 (Retour, Itinéraire, Appeler, Envoyer ordonnance, Suivre commandes, Changer pharmacie) | 4 (Envoyer/Suivre/Changer + Retour implicite) | 4 | 0 | 0 | 2026-08-29T06:20:00Z |
| patient | /messaging (Messages + thread) | 3 (liste conv, champ saisie, bouton envoyer) | 3 (ouverture thread + saisie + envoi réel, 201 confirmé) | 3 | 0 | 0 | 2026-08-29T06:30:00Z |
| patient | /notifications | 2 (Retour, Tout marquer lu) | 1 (Tout marquer lu, 200 confirmé unread 20->0) | 1 | 0 | 0 | 2026-08-29T06:33:00Z |
| patient | /profile/dependents (Mes proches) - recheck | 2 (Prendre RDV, Documents 1er proche) | 2 | 2 | 0 | 0 | 2026-08-29T06:22:00Z |

## Détail « Itinéraire » MORT (2026-08-29T06:25:00Z, cf. #6130)

Bouton `Itinéraire` de la carte héros (accueil patient) : `aria-disabled="true"` en PERMANENCE.
Root cause confirmée par lecture de code : `GET /v1/appointments?filter=upcoming` (endpoint consommé par
la home) ne renvoie JAMAIS de champ `cabinet`/`cabinet.address` (struct `AppointmentItem`,
`appointments_read.rs:53-69`), contrairement à `GET /v1/appointments/:id` (détail) qui l'expose bien
(`AppointmentDetail`, `appointments_response.rs`). Vérifié par clic direct (aucun effet, aucune requête
réseau, aucun nouvel onglet) + confirmé par le code `hero_appointment_card.dart:201-203`
(`onPressed: address == null ? null : ...`). Issue #6130 (P1) streamée.

**RE-VÉRIFIÉ 2026-08-29T12:26Z : toujours DÉSACTIVÉ en live malgré le fix #6130 mergé** (deploy-lag
#6128, non refilé — cf. explored-paths.md).

| app | écran/route | contrôles inventoriés | activés | OK | morts | cassés | last_check |
| --- | --- | --- | --- | --- | --- | --- | --- |
| praticien | /consultation?id=... (fauteuil, dent+acte+montant) | 3 (case-test : dent 16, acte "Avulsion", champ montant+Ajouter) | 3 | 3 | 0 | 0 | 2026-08-29T12:15:00Z |
| secretariat | /devis (bouton Envoyer sur brouillon) | 1 | 1 | 1 | 0 | 0 | 2026-08-29T12:20:00Z |
| pharmacie | /orders/:id/pickup (saisie manuelle code + Valider) | 2 | 2 | 2 | 0 | 0 | 2026-08-29T12:23:00Z |
| pharmacie | /devis (filtres Tous/Brouillons/Envoyés/Acceptés/Refusés) | 5 | 0 (comptages vérifiés par lecture, pas cliqués ce run) | - | - | - | 2026-08-29T12:24:00Z |
| patient | /pharmacy/orders/:id (timeline suivi commande) | 2 (Itinéraire, Appeler) | 0 (timeline vérifiée par lecture d'état, pas cliquée) | - | - | - | 2026-08-29T12:24:00Z |

| praticien | / (login page, semantics inventory only) | 4 (champ email implicite, champ password implicite, Afficher le mot de passe, Se connecter, Créer mon compte praticien) | 0 (inventaire semantics confirmé fonctionnel, login réel non complété ce run — budget concentré sur curl API) | - | - | - | 2026-08-29T18:14:00Z |


## Note run 2026-08-30T00h15Z

DNS de l'environnement d'exécution résolvait mal *.nubia-link.com (CoreDNS tailscale
100.100.100.100 renvoyait NXDOMAIN/rcode 2 pour tous les sous-domaines) — contourné via
/etc/hosts (IP 92.141.131.96, la même que celle déjà utilisée par curl --resolve dans les
runs précédents). Run concentré sur API live (curl) + PRIO1/PRIO2/B13/X7 ; aucune UI
Playwright pilotée ce run (budget consommé sur la découverte + preuve du deploy-lag
#6136 P0, jugé plus prioritaire qu'un nouveau passage UI sur des écrans déjà couverts
récemment par le run du 2026-08-29). Prochain run : reprendre l'audit contrôle-par-contrôle
sur les écrans jamais couverts ou les plus anciens du ledger ci-dessus.
