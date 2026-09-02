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

## Sweep 2026-08-31 — app infirmière (JAMAIS auditée avant ce run) + pharmacie devis filtres

**App infirmière, 1ère fois auditée en Playwright réel (login réel, semantics)** : écran Connexion
(4 contrôles : champ email, champ mdp, "Afficher le mot de passe", "Se connecter" — tous OK, login
réussi). Écran Disponibilité (switch "En ligne" : OK au clic, MAIS **CASSÉ à l'affichage initial**
— #6143 P1, l'écran ment systématiquement "hors ligne" au premier rendu quel que soit l'état serveur
réel, faute d'appel à `GET /nurse/profile` au montage). Onglet Offres (carte d'offre : "Accepter" OK
(201 confirmé, transition vers Ma visite), "Passer" non activé ce run (destructif pour l'unique
offre de test disponible) ; **pull-to-refresh CASSÉ sur l'état vide** — #6144 P1, RefreshIndicator
absent de la branche `NubiaEmptyState`). Onglet Ma visite (bouton transition "Je pars"/en-route puis
suivants : OK au clic API-side, confirmé par re-GET serveur — le test Playwright a perdu la session
par expiration de token (900s) en cours de script, pas un bug produit, complété via curl direct pour
preuve). **Libellés d'actes bruts non traduits (prise_de_sang au lieu de Prise de sang) sur les
2 écrans qui les affichent** — #6145 P2, la table de labels existe déjà dans app_patient mais n'est
pas partagée avec app_infirmiere.

**Pharmacie — Devis, 5 filtres (Tous/Brouillons/Envoyés/Acceptés/Refusés) réellement CLIQUÉS
(jamais fait avant, ledger précédent notait "comptages vérifiés par lecture, pas cliqués")** :
tous OK, chaque filtre affiche bien le sous-ensemble attendu (Brouillons→"Envoyer au patient" boutons
+1 item Brouillon ; Envoyés→2 items statut Envoyé ; Acceptés→6 items statut Accepté ; Refusés→2 boutons
"Voir"), 0 défaut. Filtres Commandes (Toutes/Reçues/En préparation/Prêtes) re-cliqués et re-confirmés
OK (listes différentes par filtre, cohérentes avec les compteurs).

| infirmiere | / (Connexion) | 4 (champ email, champ mdp, afficher mdp, Se connecter) | 4 | 4 | 0 | 0 | 2026-08-31T00:15:00Z |
| infirmiere | / (Disponibilité, switch En ligne) | 1 | 1 | 0 | 0 | 1 (affichage initial faux, #6143 — le toggle lui-même fonctionne) | 2026-08-31T00:15:00Z |
| infirmiere | / (Offres, carte offre) | 2 (Accepter, Passer) + pull-to-refresh implicite | 1 (Accepter, OK 201) | 1 | 0 | 1 (pull-to-refresh mort sur liste vide, #6144) | 2026-08-31T00:15:00Z |
| infirmiere | / (Ma visite, boutons transition) | 3 (Je pars/en-route, Arrivé, Terminé) | 3 (via API après perte de session Playwright, transitions confirmées serveur) | 3 | 0 | 0 | 2026-08-31T00:15:00Z |
| pharmacie | /devis (5 filtres Tous/Brouillons/Envoyés/Acceptés/Refusés) | 5 | 5 (réellement cliqués cette fois, listes filtrées différentes et cohérentes) | 5 | 0 | 0 | 2026-08-31T00:15:00Z |
| pharmacie | / (Commandes, 4 filtres) re-check | 4 | 4 | 4 | 0 | 0 | 2026-08-31T00:15:00Z |

## Note run 2026-08-31T06h16Z

Re-audit app_infirmiere (switch Disponibilité + mécanique autoload Offres via
trace réseau Playwright, `page.on('request')`) : le switch "En ligne" reflète
maintenant correctement l'état serveur au montage dans les DEUX sens
(`aria-checked=true` ET `false` confirmés selon `is_online` réel — #6143 fixé,
déployé, tenu). **NOUVEAU défaut identifié au niveau MÉCANIQUE (pas juste
contrôle) : `GET /nurse/offers` n'est jamais appelé automatiquement au montage
de l'app**, seul `GET /nurse/profile` part (trace réseau capturée). Une nurse
déjà en ligne avec une offre serveur active voit l'état vide "Aucune offre" et
doit deviner qu'il faut tirer pour rafraîchir. Issue #6150 (P1) streamée —
distinct de #6144 (pull-to-refresh mort, fixé, geste manuel) : ici c'est
l'ABSENCE totale d'auto-chargement, pas le refresh manuel qui est cassé.

| app | écran/route | contrôles inventoriés | activés | OK | morts | cassés | last_check |
| --- | --- | --- | --- | --- | --- | --- | --- |
| infirmiere | / (Disponibilité, switch En ligne, re-vérif bidirectionnelle) | 1 | 1 | 1 | 0 | 0 (fix #6143 confirmé tenir dans les 2 sens) | 2026-08-31T06:16:00Z |
| infirmiere | / (Offres, mécanique autoload au montage) | 1 (chargement implicite attendu) | 0 (jamais déclenché, confirmé par trace réseau) | 0 | 1 (mort — #6150 nouveau) | 0 | 2026-08-31T06:16:00Z |

## Sweep 2026-09-01T00h35Z — secrétariat agenda (mécanique semaine), praticien recherche patient, infirmière 3 onglets re-check

| secretariat | /agenda (grille semaine + Nouveau RDV) | 4 (nav semaine préc/suiv/aujourd'hui + Nouveau RDV) + modale (Créneau/Patient/Annuler/Créer) | 5 | 5 | 0 | 0 | 2026-09-01T00:30:00Z |
| praticien | /patients (champ recherche) | 1 | 1 | 0 | 0 | 1 (recherche nom complet avec espace retourne 0 résultat, cf #6155 — le champ lui-même répond, mais le résultat serveur est faux) | 2026-09-01T00:20:00Z |
| praticien | /patients/:id (fiche, section Journal du patient) | 1 section (timeline) | 1 (chargement observé) | 0 | 0 | 1 (affiche "Erreur de décodage de la réponse", cf #6156) | 2026-09-01T00:22:00Z |
| infirmiere | / (3 onglets Disponibilité/Offres/Ma visite, re-check) | 3 tabs | 3 | 3 | 0 | 0 (tous corrects : online affiché juste, offre visible sans refresh manuel, état vide correct) | 2026-09-01T00:15:00Z |

## Sweep 2026-09-01T06h30Z — infirmière cycle complet (Accepter + transitions), billing patient sign

| infirmiere | / (Offres, carte offre réelle + bouton Accepter) | 2 (Accepter, Passer) | 1 (Accepter cliqué, offre migre vers Ma visite, 0 req≥400) | 1 | 0 | 0 (aucun bug — un faux-négatif initial du script de test venait d'un mauvais ciblage de coordonnées de clic sur le tab, pas un défaut applicatif ; re-testé propre) | 2026-09-01T06:25:00Z |
| infirmiere | / (Ma visite, bouton Je pars après Accepter) | 1 | 1 (cliqué, transition en_route confirmée par API après perte de session Playwright par expiration token) | 1 | 0 | 0 | 2026-09-01T06:25:00Z |
| secretariat | /cabinet/quotes (create→send, flux frais) | N/A (API pur, pas de nav UI ce run) | - | - | - | - | 2026-09-01T06:20:00Z |

## Sweep 2026-09-01T12h20Z — login réel 5 apps (fix Playwright shadow-DOM + saisie Flutter)

| patient | / (dashboard post-login, tuiles) | 6 tuiles + Annuaire/Notifications/Itinéraire | 0 (inventaire seul, ce run — pas d'activation click-par-click) | - | - | - | 2026-09-01T12:20:00Z |
| praticien | / (nav + badges) | 15 (nav 12 + badges 2 + déconnexion) | 0 (inventaire seul) | - | - | - | 2026-09-01T12:20:00Z |
| secretariat | / (dashboard agenda) | 6 (Ouvrir l'agenda, Appeler×2, Relancer, Ouvrir×2) | 0 (inventaire seul) | - | - | - | 2026-09-01T12:20:00Z |
| pharmacie | / (Commandes liste + nav) | 28 (nav 4 + déconnexion + 23 contrôles de la liste commandes) | 0 (inventaire seul) | - | - | - | 2026-09-01T12:20:00Z |
| infirmiere | / (Disponibilité, switch + 3 tabs) | 5 (déconnexion, switch, 3 tabs) | 0 (inventaire seul, activation déjà prouvée lors du sweep 06h30Z précédent) | - | - | - | 2026-09-01T12:20:00Z |

| secretariat | / (dashboard, nav sidebar semantics audit) | 7 (contenu) + ~13 (nav, invisibles Semantics) | 9 (Ouvrir l'agenda OK nav, 3x Appeler OK, Relancer OK, 2x Ouvrir OK ; nav sidebar cliquee par coordonnees brutes hors-Semantics -> navigue /agenda /salle-attente /cabinet-stats confirme, mais absente de l'inventaire Semantics -> #6192 P2 accessibilite) | 9 | 0 | 0 | 2026-09-02T06:00:00Z |
| secretariat | /cabinet-stats (Pilotage du cabinet) | 2 (Actualiser + panneau billing) | 1 (Actualiser -> re-fetch confirme, 403 stats/activity intentionnel RBAC #4592 documente code) | 1 | 0 | 0 | 2026-09-02T06:00:00Z |
| praticien | /consultation (Historique + detail) | 15 cartes historique + 3 filtres statut | 2 (clic carte historique -> URL change MAIS contenu reste bloque sur la liste = #6190 P1 bouton mort ; clic filtre statut non teste plus avant) | 0 | 1 (carte historique) | 0 | 2026-09-02T06:00:00Z |
| praticien | /ordonnances/new (composition + templates + Dose/Frequence/Duree) | ~30 (modeles + recherche DCI x2 + 3 selects + submit) | 6 (template applique OK, Dose/Frequence/Duree selectionnes via bottom-sheet OK, submit -> 201 confirme ; recherche DCI libre confirmee NON cablee -- feature-gap documente #6101, pas un bug de clic) | 6 | 0 | 0 | 2026-09-02T06:00:00Z |
| praticien | /patients/:id (Dossier patient, filtres Journal) | 6 filtres + ~10 actions | 2 (filtre "Actes" bascule reellement le contenu vers actes CCAM dates/tarifes, confirme par diff texte avant/apres -- corrige un faux-negatif de mon 1er scan Semantics-only) | 2 | 0 | 0 | 2026-09-02T06:00:00Z |
| pharmacie | /orders (tri chronologique + Preparer/Marquer prete, fix #6168/#6169 re-verifies) | 3 filtres + N boutons Preparer/Delivrer | 2 (Preparer -> accept 200 confirme chrono fige "En preparation", Marquer prete -> ready 200 confirme chrono disparu, fixes tenus) | 2 | 0 | 0 | 2026-09-02T06:00:00Z |
| pharmacie | /orders/:id (Delivrance, commande Prete) | 3 (Voir l'original, Creer un devis, Scanner le retrait) | 0 (inventaire -- lignes ordonnance confirmees visibles par lecture texte complet, conforme maquette) | - | - | - | 2026-09-02T06:00:00Z |
| infirmiere | (API only, cycle complet B13/X10) | - | - (cycle API complet accept/en-route/arrived/done + double-accept 409 confirme re-teste) | - | - | - | 2026-09-02T06:03:00Z |

Note méthode : ce sweep a d'abord dû résoudre un environnement CI sans DNS public (résolution manuelle
via requêtes DNS UDP + /etc/hosts) et des faux-négatifs Playwright/Flutter web (canvas et semantics-host
dans le shadow DOM de `flt-glass-pane`, jamais vus par un `querySelectorAll` direct ; `locator.fill()`
perd le 1er caractère du mot de passe sans délai post-clic ; `mouse.click()` instantané n'est pas reconnu
par le gesture recognizer Flutter, nécessite `mouse.down()`+wait 100-150ms+`mouse.up()`). Une fois ces
correctifs de script appliqués, les 5 logins réels ont tous réussi sans erreur console/réseau bloquante ;
l'activation exhaustive contrôle-par-contrôle (clic + verdict OK/MORT/CASSÉ) reste à faire sur les écrans
listés ci-dessus lors d'un prochain sweep (budget de ce run concentré sur la remise en état de l'outillage
Playwright + PRIO1 API).

## Sweep 2026-09-02T00h00-01h00Z — praticien travaux labo/messages/devis, secrétariat stock/patients/payouts/team-messages/bookable-slots, pharmacie devis send, patient consents/dependents/documents/treatment-plans/implant-passport/home-care

| app | écran/route | contrôles inventoriés | activés | OK | morts | cassés | last_check |
| --- | --- | --- | --- | --- | --- | --- | --- |
| praticien | /devis (10 fiches devis) | 10 | 0 (inventaire, cliqué au sweep précédent) | - | - | - | 2026-09-02T00:15:00Z |
| praticien | /stock + /stock-inventory | 3 (Actualiser, Nouvelle demande) + 22 (11 lignes + Mouvement) | 0 (inventaire seul) | - | - | - | 2026-09-02T00:15:00Z |
| praticien | /lab-work-orders | 3 (Actualiser, Nouveau bon cliqué->snackbar OK, Réessayer) | 1 (Nouveau bon, snackbar "à venir" confirmé) | 1 | 0 | 0 (mécanique DIVERGENTE : liste sous-jacente CASSÉE par #6174, cf design-v2.md) | 2026-09-02T00:20:00Z |
| praticien | /messages (thread + envoi réel) | 5 (liste conv, "Créer un RDV", champ saisie, envoi) | 3 (ouverture thread OK, envoi réel 201, double-clic->1 seul POST) | 3 | 0 | 0 | 2026-09-02T00:40:00Z |
| praticien | /ordonnances ("Choisir un patient" + recherche) | 1 + 17 (patients listés après clic) | 1 | 1 | 0 | 0 | 2026-09-02T00:50:00Z |
| secretariat | /cabinet-stats | 1 (Actualiser) | 0 (inventaire, 403 audit-log/members intentionnel re-confirmé) | - | - | - | 2026-09-02T00:10:00Z |
| secretariat | /bookable-slots ("Créer un créneau" + formulaire) | 4 (Actualiser, 2 filtres, Créer un créneau) + 6 (formulaire modal) | 1 (Créer un créneau -> ouvre formulaire complet) | 1 | 0 | 0 | 2026-09-02T00:52:00Z |
| secretariat | /appointment-motifs | 1 (Actualiser) | 0 (inventaire seul) | - | - | - | 2026-09-02T00:10:00Z |
| secretariat | /stock (5 filtres + Nouvelle demande) | 4 | 0 (inventaire, filtres déjà cliqués au sweep précédent) | - | - | - | 2026-09-02T00:10:00Z |
| secretariat | /liste-attente | 1 (Actualiser) | 0 | - | - | - | 2026-09-02T00:10:00Z |
| secretariat | /team-messages (Joindre/Épingler/Mentionner/envoi réel) | 8 | 5 (Mentionner OK insère @, envoi réel via mouse.click+keyboard.type 201 confirmé — mouse.down/up séquence échoue silencieusement sur ce widget précis, leçon méthodo) | 5 | 0 | 0 | 2026-09-02T00:35:00Z |
| secretariat | /devis (bouton Envoyer déjà testé sweep précédent) | 10 | 0 (inventaire seul ce run) | - | - | - | 2026-09-02T00:10:00Z |
| secretariat | /cabinet-payouts | 5 | 0 (inventaire seul, Connecter Stripe/Exporter déjà testés sweep précédent) | - | - | - | 2026-09-02T00:10:00Z |
| secretariat | /patients (3 facettes + ⌘N + 20 fiches) | 24 | 0 (inventaire seul, facettes déjà cliquées sweep précédent) | - | - | - | 2026-09-02T00:10:00Z |
| pharmacie | /devis (5 filtres + Envoyer au patient) | 4 filtres + N boutons Envoyer | 2 (Brouillons filtre + Envoyer au patient, 200 confirmé — 1ère tentative avait ciblé le GROUPE parent par erreur de script, corrigé et re-testé propre) | 2 | 0 | 0 | 2026-09-02T00:55:00Z |
| pharmacie | / (Commandes, bouton Préparer sur ligne) | 1 | 1 (Préparer -> accept 200 confirmé) | 1 | 0 | 0 | 2026-09-02T00:33:00Z |
| infirmiere | / (switch Disponibilité, re-vérif bidirectionnelle) | 1 | 1 (aria-checked=true confirmé cohérent avec is_online:true serveur) | 1 | 0 | 0 | 2026-09-02T00:22:00Z |
| infirmiere | / (Offres, carte réelle + Accepter, auto-load confirmé) | 2 | 1 (Accepter -> 201 accept confirmé, offre créée juste avant apparaît sans refresh manuel — #6150 toujours fixé) | 1 | 0 | 0 | 2026-09-02T00:24:00Z |
| patient | /profile/consents (3 switches + 3 Détails) | 1 groupe verrouillé + 6 | 1 (switch marketing toggle -> PUT confirmé 200, reverti après test — 1ère tentative avait ciblé un switch hors-viewport à cause d'un défaut de scroll du script, corrigé) | 1 | 0 | 0 | 2026-09-02T00:38:00Z |
| patient | /treatment-plans (11 plans) | 11 | 1 (clic "Réhabilitation 26" -> détail chargé, étape 2/3 affichée) | 1 | 0 | 0 | 2026-09-02T00:15:00Z |
| patient | /implant-passport (4 implants + Exporter en PDF) | 5 | 1 (Exporter en PDF -> requête déclenchée mais 502 upstream_unavailable, même famille env-limitation que téléchargement documents, non filé) | 0 | 0 | 1 (échec réseau documenté comme limitation d'env, pas un bug produit) | 2026-09-02T00:16:00Z |
| patient | /home-care (17 demandes listées) | 17 + Nouvelle demande | 0 (inventaire — défaut trouvé par LECTURE : statut "expired" non traduit, #6176) | - | - | - | 2026-09-02T00:12:00Z |
| patient | /home-care/new (formulaire nouvelle demande) | 8 (6 actes + adresse + boutons) | 0 (inventaire seul, formulaire déjà testé bout-en-bout aux sweeps précédents) | - | - | - | 2026-09-02T00:44:00Z |
| patient | /documents (recherche + 9 filtres + liste + Télécharger) | 11 + N | 1 (clic 1er document -> download déclenché, 502 upstream_unavailable même limitation d'env, feedback snackbar correct) | 0 | 0 | 1 (échec réseau env, pas produit) | 2026-09-02T00:56:00Z |
| patient | / (dashboard, re-check post-login FRAIS) | 20 | 0 (inventaire — défaut trouvé : "Bonjour  " prénom vide, #6178 régression #6141) | - | - | - | 2026-09-02T00:37:00Z |

Note méthode (leçons apprises ce run) : (1) un clic sur un match `.find()` ambigu (ex. "Envoyer au patient" présent N fois) peut accidentellement cibler le GROUPE PARENT englobant au lieu du bouton individuel — toujours filtrer par label EXACT (`===`) et vérifier le rect avant de cliquer quand plusieurs contrôles partagent un label. (2) Un switch/bouton situé hors du viewport initial (`rect.y > viewport height`) ne réagit à AUCUN clic tant qu'on n'a pas scrollé — un faux-négatif "bouton mort" doit TOUJOURS être revérifié après scroll avant d'être qualifié de bug. (3) Pour certains champs de texte Flutter (ex. team-messages "Écrire à l'équipe…"), la séquence `mouse.down()+wait+mouse.up()` échoue silencieusement (le texte n'est jamais réellement entré) alors qu'un `mouse.click()` simple suivi de `keyboard.type()` fonctionne — pas de règle universelle, tester les deux si un envoi semble ne rien faire.

## Ronde 2026-09-02 (12:28-16:00 UTC) — audit d'activation

> **Correctif de méthode important pour les rondes suivantes.** Trois sources de
> FAUX « MORT » ont été identifiées et neutralisées ce run ; les rondes
> précédentes les comptaient comme des bugs :
> 1. **Contrôle hors viewport** — un rect Semantics à `y > hauteur du viewport`
>    n'est pas cliquable par coordonnées ; le clic tombe dans le vide. Il faut
>    scroller PUIS RE-lire le rect (le harness le fait désormais, sinon le
>    contrôle est marqué « non jugé » plutôt que « mort »).
> 2. **Vue détail en place** — praticien `/patients` et `/consultation`,
>    secrétariat dashboard : ouvrir un élément REMPLACE le contenu **sans changer
>    la route**. Les clics suivants, faits aux coordonnées de la liste, ne
>    touchent plus rien. Il faut re-naviguer vers l'écran entre deux contrôles.
> 3. **Filtre déjà actif** — re-cliquer le filtre sélectionné (« À répondre (7) »,
>    « Toutes ») est un no-op légitime, pas un bouton mort.
> Après correction, **aucun contrôle réellement MORT n'a été confirmé ce run**.

| app | écran/route | inventoriés | activés | OK | morts | cassés | last_check |
|---|---|---|---|---|---|---|---|
| patient | / (Accueil) | 20 | 10 | 10 | 0 | 0 | 2026-09-02T13:20:00Z |
| patient | / -> Mes RDV (À venir + Historique) | 24 | 3 | 3 | 0 | 0 | 2026-09-02T13:10:00Z |
| patient | Préparer mon RDV (PrepareRdvPage) | 4 | 3 | 3 (coche visuelle OK) | 0 | 0 | 2026-09-02T12:55:00Z |
| infirmiere | onglet Disponibilité | 6 | 2 | 2 | 0 | 0 | 2026-09-02T13:00:00Z |
| infirmiere | onglet Offres | 6 | 1 | 1 | 0 | 0 | 2026-09-02T13:00:00Z |
| infirmiere | onglet Ma visite | 5 | 1 | 1 (re-clic onglet actif = no-op légitime) | 0 | 0 | 2026-09-02T13:00:00Z |
| praticien | / (Tableau de bord) | 17 | 2 | 2 | 0 | 0 | 2026-09-02T14:10:00Z |
| praticien | /agenda | 10 | 5 | 5 | 0 | 0 | 2026-09-02T14:10:00Z |
| praticien | /salle-attente | 2 | 1 | 1 | 0 | 0 (file vide côté Hugo, cf. #6213) | 2026-09-02T14:10:00Z |
| praticien | /patients (liste) | 19 | 1 | 0 | 0 | 1 (403 medical-record/documents/prescriptions -> #6210) | 2026-09-02T14:40:00Z |
| praticien | /patients -> fiche patient (vue détail) | 25 | 0 (inventoriés seulement) | - | - | - | 2026-09-02T14:40:00Z |
| praticien | /consultation | 32 | 3 | 3 | 0 | 0 | 2026-09-02T14:10:00Z |
| praticien | /ordonnances | 1 | 1 | 1 | 0 | 0 | 2026-09-02T14:10:00Z |
| secretariat | /agenda | 10 | 6 | 6 | 0 | 0 | 2026-09-02T15:00:00Z |
| secretariat | /salle-attente | 7 | 4 | 2 | 0 | 2 (« Appeler MD » + « Appeler » -> 403 silencieux, #6214) | 2026-09-02T15:40:00Z |
| secretariat | /patients | 21 | 8 | 8 | 0 | 0 | 2026-09-02T15:00:00Z |
| secretariat | /devis | 33 | 8 | 8 | 0 | 0 | 2026-09-02T15:00:00Z |
| secretariat | /stock | 16 | 8 | 8 | 0 | 0 | 2026-09-02T15:00:00Z |
| pharmacie | / (Commandes) | 35 | 13 | 12 | 0 (1 faux positif : coordonnées périmées après changement de filtre) | 0 | 2026-09-02T15:30:00Z |
| pharmacie | /stock | 28 | 8 | 3 | 0 (5 faux positifs, même cause) | 0 | 2026-09-02T15:30:00Z |

**TOTAL ronde : 321 contrôles inventoriés, 88 activés, 79 OK, 0 mort confirmé, 3 cassés.**

**À faire au prochain round** (écrans inventoriés mais NON activés) : praticien
fiche patient (25 contrôles — Schéma dentaire / Bilan parodontal / Plan de
traitement / Créer une ordonnance / Exporter PDF / Enregistrer les notes /
Ajouter une étiquette / Envoyer un document + 13 facettes de type de document) ;
patient /profile et ses sous-écrans ; pharmacie /messages et /devis ;
secrétariat /cabinet-payouts, /team-messages, /messages, /rappels.
