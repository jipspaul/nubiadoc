# Ledger des contrôles UI audités — flutter-qa-agent

> Une ligne par écran audité en profondeur (inventaire Semantics + activation de
> CHAQUE contrôle + verdict OK/MORT/CASSÉ/DÉSACTIVÉ). Alimenté au fil des rondes ;
> à la ronde suivante, commencer par les écrans jamais audités ou les plus anciens.
> Complète `explored-paths.md` (scénarios API/flux) — ce fichier-ci se concentre
> sur la mécanique bouton-par-bouton d'un écran donné.

## ⚠️ Leçon de méthode (ronde 2026-09-03 soir) — à lire avant d'exploiter la colonne « morts »

Le détecteur automatique « MORT » (pas de navigation + pas de repeinture + pas de requête)
produit **beaucoup de faux positifs**. Sur cette ronde, **100 % des contrôles signalés MORT
puis re-vérifiés à la main se sont révélés fonctionnels**. Les cinq pièges rencontrés :

1. **Auto-navigation** : cliquer l'entrée de nav de l'écran COURANT ne fait rien — normal.
2. **Hors viewport** : un contrôle à `y=929` sur une fenêtre de 800 px n'est jamais atteint par le clic.
3. **Curseur d'interrupteur** : un `Switch` Flutter ne réagit qu'au curseur, pas à toute la ligne
   (ex. « En ligne » infirmière : mort au centre, fonctionnel à droite → PATCH émis).
4. **Libellé de même longueur** : « Plus récent d'abord » → « Plus ancien d'abord » ne change ni le
   nombre de nœuds ni la longueur du texte → repeinture non détectée alors que le tri s'applique.
5. **Artefact de lot** : après une première navigation, les coordonnées du reste du lot sont périmées
   → tout l'écran ressort « MORT » (cf. pharmacie `/` ci-dessous).

**Règle** : ne jamais ouvrir d'issue « bouton mort » sans re-clic ciblé isolé + preuve
(navigation, requête réseau, ou capture avant/après).

| app | écran/route | contrôles inventoriés | activés | OK | morts (vérifiés) | cassés | last_check |
|---|---|---|---|---|---|---|---|
| praticien | / (Tableau de bord) | 16 | 15 | 15 | 0 | 0 | 2026-09-03T21:45:49+00:00 |
| praticien | /agenda | 21 | 20 | 19 | 0 (1 auto-nav) | 0 | 2026-09-03T21:45:49+00:00 |
| praticien | /waiting-room | 16 | 14 | 13 | 0 (1 auto-nav) | 0 (1 désactivé légitime : « Appeler suivant », file vide) | 2026-09-03T21:45:49+00:00 |
| praticien | /consultation?id= (détail séance) | 34 | 6 ciblés | 6 | 0 | 0 | 2026-09-03T21:45:49+00:00 |
| secretariat | / (Tableau de bord) | 21 | 20 | 18 | 0 (1 auto-nav) | 2 (403 /cabinet/stats/activity — #6369 connu) | 2026-09-03T21:45:49+00:00 |
| secretariat | /devis | 35 | 34 | 26 | 0 vérifié (7 non re-vérifiés) | 1 (idem #6369) | 2026-09-03T21:45:49+00:00 |
| secretariat | /salle-attente | 19 | 17 | 14 | 0 vérifié (1 non re-vérifié) | 2 (idem #6369) | 2026-09-03T21:45:49+00:00 |
| secretariat | /patients | 35 | 34 | 15 | 0 vérifié (18 = avatars non interactifs + lignes hors viewport) | 1 | 2026-09-03T21:45:49+00:00 |
| secretariat | /agenda | 12 | 8 | 8 | 0 | 0 | 2026-09-03T21:45:49+00:00 |
| pharmacie | / (File des commandes) | 19 | 18 | 5 mesurés | **non fiable — artefact de lot** ; « Délivrer » re-vérifié isolément → navigue vers /orders/:id/pickup | 0 | 2026-09-03T21:45:49+00:00 |
| pharmacie | /orders/:id (Délivrance) | 5 | 4 | 4 | 0 | 0 | 2026-09-03T21:45:49+00:00 |
| pharmacie | /orders/:id/pickup (scan de retrait) | 7 | 5 | 5 | 0 | 0 (1 désactivé légitime : « Valider le retrait » tant que le QR ne correspond pas) | 2026-09-03T21:45:49+00:00 |
| pharmacie | /devis, /stock, /messages | 61 | inventoriés seulement | — | — | — | 2026-09-03T21:45:49+00:00 |
| infirmiere | / (Disponibilité / Offres / Ma visite) | 7 | 5 | 5 | 0 | 0 | 2026-09-03T21:45:49+00:00 |
| patient | /profile/dependents + dialogue « Ajouter un proche » | 24 + 11 | 8 ciblés | 8 | 0 | 0 (1 désactivé légitime : « Envoyer la demande » tant que l'e-mail est vide) | 2026-09-03T21:45:49+00:00 |
| patient | /documents | 40 | inventoriés seulement | — | — | — | 2026-09-03T21:45:49+00:00 |

| pharmacie | / (File des commandes) | 21 | 16 | 16 | 0 | 0 | 2026-09-04T09:05:00+00:00 |
| secretariat | /agenda (grille semaine, refonte #6390/#6406/#6407) | 30 (+36 blocs RDV) | 14 ciblés | 14 | 0 | 0 (2 désactivés : « Marquer arrivé » et « Appeler » — NON légitimes, cf. #6411) | 2026-09-04T06:35:00+00:00 |
| patient | / (Accueil) | 15 | 5 (lot interrompu par le budget temps) | 4 | 0 | 0 (1 désactivé légitime : « Itinéraire », `cabinet.address:null` sur le prochain RDV — prouvé par l'API) | 2026-09-04T09:30:00+00:00 |
| patient | /mes-rdv (onglets) | 9 | 1 ciblé | 1 | 0 | 0 | 2026-09-04T08:55:00+00:00 |
| infirmiere | / (3 onglets) | 6 | via API (PATCH /nurse/availability) | — | — | — | 2026-09-04T06:42:00+00:00 |

### Leçon de méthode confirmée cette ronde (2026-09-04)

La règle « ne jamais ouvrir d'issue *bouton mort* sans re-clic ciblé isolé » a de nouveau payé, deux fois :

1. **`pharmacie /` — le lot « non fiable » de la ronde précédente est LEVÉ.** Refait avec une
   re-navigation complète entre chaque clic : **16/16 OK, 0 mort, 0 cassé**. Les 5 « Délivrer »
   naviguent chacun vers un `/orders/<id>/pickup` distinct, les 4 facettes filtrent réellement.
   C'était bien un artefact de coordonnées périmées, pas un défaut produit.
2. **`patient /` — « Itinéraire » sort MORT du détecteur, et c'est un faux positif légitime.**
   Le bouton est `aria-disabled=true` parce que le prochain RDV se tient au « Cabinet Dubois »,
   dont l'API renvoie `cabinet.address: null` (`GET /v1/appointments?filter=upcoming`). Pas de
   destination → pas d'itinéraire. **Désactivation prouvée légitime, non filée.**

Nouveau piège à ajouter à la liste : **un champ texte Flutter web n'existe pas dans le DOM avant
le focus.** Sur `pharmacie /`, l'inventaire Semantics initial trouvait 0 `<input>` alors que le
champ « Patient, n° commande… » est bien peint et fonctionnel (2 `<input>` après clic, la saisie
« CMD-0090 » filtre réellement la liste). Ne pas conclure « champ absent / inaccessible » sur un
inventaire pris avant interaction.

| praticien | /stock | 3 | 3 | 3 | 0 | 0 | 2026-09-04T09:05:00+00:00 |
| praticien | /messages | 9 | 9 | 9 | 0 | 0 | 2026-09-04T09:10:00+00:00 |
| praticien | /patients | 12 (contenu) | 12 | 2 mesurés | 0 | 0 réel — **10 « CASSÉ » invalidés : jeton expiré en cours de lot** (voir ci-dessous) | 2026-09-04T09:15:00+00:00 |
| praticien | /consultation | 15 (contenu) | 12 | 11 | 1 non re-vérifié (« Terminée », facette de même longueur — piège nº 4) | 0 | 2026-09-04T09:20:00+00:00 |
| infirmiere | / (3 onglets, audit complet + adversarial) | 8 uniques | 7 | 7 | 0 | 0 | 2026-09-04T08:40:00+00:00 |
| patient | /home-care/new | 8 | 0 activés (2 jugés) | — | 0 | 0 (2 désactivés **légitimes** : « Obtenir un devis » et « Confirmer la demande » tant qu'aucun acte n'est coché) | 2026-09-04T09:07:00+00:00 |
| patient | /notifications | 19 | 1 ciblé | 1 | 0 | 0 | 2026-09-04T09:07:00+00:00 |

| praticien | /patients (fiche ouverte) | 12 | 6 | 6 (la fiche s'ouvre) | 0 | 0 — les 403 sont la garde relation-de-soin, mal rendue (#6426) | 2026-09-04T07:56:00+00:00 |
| praticien | /consultation (facettes, re-clic isolé) | 3 facettes | 3 | 2 + 1 déjà active | 0 | 0 | 2026-09-04T08:03:00+00:00 |
| secretariat | /salle-attente (« Appeler » + échec réseau) | 4 | 2 ciblés | 2 | 0 | 0 | 2026-09-04T08:48:00+00:00 |

| pharmacie | /devis | 7 | 7 | 7 | 0 (2 faux positifs levés, cf. ci-dessous) | 0 | 2026-09-04T09:15:00+00:00 |
| pharmacie | /stock | 11 | 8 | 8 | 0 (1 faux positif) | 0 (2 « Refuser » non activés : destructifs) | 2026-09-04T09:12:00+00:00 |
| pharmacie | /messages | 8 | 8 | 8 | 0 (1 faux positif) | 0 | 2026-09-04T09:12:00+00:00 |

| secretariat | /patients (facettes `role=switch`) | 6 | 4 | 4 | 0 | 0 | 2026-09-04T08:35:00+00:00 |
| patient | /book (puces de filtre) | 5 | 4 | 1 | 0 | **3 CASSÉS confirmés : « Téléconsult », « Secteur 1 », « Généraliste » vident la liste (#6431)** | 2026-09-04T08:45:00+00:00 |

| patient | /profile | 13 | 8 | 7 | 0 (1 faux positif : sélecteur de fichier natif) | 0 | 2026-09-04T08:55:00+00:00 |

**Cumul de la ronde : 143 contrôles activés et jugés, 120 OK, 0 mort confirmé, 3 CASSÉS confirmés (#6431).**

Les 4 verdicts MORT du lot pharmacie ont été re-testés **isolément avec un signal réel** (nombre de lignes
« Total : » + contenu des premières lignes) : `Brouillons (17)` 6 → **1** ligne et le contenu bascule sur
« Envoyer au patient » ; `Envoyés (3)` 6 → **0** et le contenu bascule sur « Relancer ». Les facettes
filtrent donc bien. `Tous (71)` et `Acceptés (49)` ne changent rien **parce que les 6 lignes visibles en
haut de liste sont déjà toutes « Accepté »** — contenu identique attendu, pas un contrôle mort. Idem pour
`À répondre` et `Toutes`, facettes actives par défaut.

### Deux faux positifs de plus, invalidés cette ronde (2026-09-04)

6. **Un 4xx capté au niveau réseau n'est pas forcément « le » bouton qui casse.** L'audit de
   `praticien /patients` a sorti 10 contrôles « CASSÉ (403 …/cabinet/patients/<id>) ». Deux hypothèses
   ont été testées puis départagées : *(a)* jeton expiré — **écartée** (42/42 → 200 au curl sur la route
   principale, et le re-login à mi-parcours n'a rien changé) ; *(b)* le clic ouvre bien la fiche, mais
   **six sous-routes cliniques** (`medical-record`, `prescriptions`, `documents`, `dental-chart`,
   `treatment-plans`, `notes`) renvoient un 403 **légitime** (garde relation de soin) — **confirmée**,
   contre-épreuve à 200 sur un patient réellement suivi. Le vrai défaut n'est pas le bouton mais le
   **rendu** de ce 403 (#6426). **Règle** : quand `bag.net` remonte des 4xx, identifier la ROUTE exacte
   avant de qualifier le contrôle — un écran peut s'ouvrir correctement et n'échouer que sur ses panneaux.
7. **Un sélecteur de fichier NATIF ne laisse aucune trace détectable.** « Modifier la photo de profil »
   (`/profile`) est sorti MORT du lot : aucune navigation, aucune repeinture, aucune requête, et même
   **aucun `<input type=file>` dans le DOM**. Le contrôle fonctionne pourtant : en écoutant l'événement
   Playwright `filechooser`, on mesure **filechooser=1**. Le code est sain — `_pickAndUpload`
   (`profile_page.dart:653`) atteint bien `FilePicker.platform.pickFiles`, et `FilePickerService` comme
   `UpdateAvatarUseCase` sont enregistrés (`nubia_core/injection.dart:26`, `nubia_data/data_registration.dart:417`).
   **Règle** : brancher `page.on('filechooser')` avant tout audit d'un écran qui peut téléverser, et ne
   jamais conclure MORT sur un bouton d'import/export sans ce témoin.

8. **SnackBar absent de l'arbre Semantics** — un test qui ne lit que `semText` conclut à un « échec
   silencieux » là où l'app affiche bien « Erreur réseau (hors ligne). ». Recouper par une **capture
   précoce** (< 4 s, durée de vie par défaut d'un SnackBar). Détail dans `explored-paths.md`,
   scénario `adversarial-infirmiere`.

## ⚠️ Leçons de méthode ajoutées à la ronde 2026-09-04 (13h)

Trois **nouvelles** sources de faux « MORT »/« CASSÉ » identifiées et corrigées dans le harnais
cette ronde. Les chiffres du tableau ci-dessous sont ceux d'APRÈS correction.

9. **Hors viewport EN LARGEUR** (rangées à défilement horizontal). Sur `/documents` (390 px), les
   facettes `Radio 7` @x=407, `CBCT 2` @x=499 … `Carte mutuelle 20` @x=1116 sont toutes hors de
   l'écran : le clic n'atteint rien et **8 facettes sont sorties MORTES**. Re-testées après un
   `mouse.wheel(400, 0)` sur la rangée, elles fonctionnent toutes (`aria-checked` bascule + repeinture).
   **Règle** : filtrer sur `x + w <= viewport.width` (pas seulement `x >= 0`), et faire défiler
   la rangée avant de conclure. Le filtre du harnais a été corrigé en conséquence.

10. **État persistant entre deux contrôles du même lot.** Sur `/` pharmacie, cliquer « Préférences de
    notifications » ouvre un sous-écran **sans changer l'URL** ; tout le reste du lot était alors cliqué
    sur le mauvais écran, quasi-blanc, d'où **39 faux « CASSÉ »** (13 + 7 + 11 + 8) sur les 4 routes
    pharmacie. Après correction (re-navigation **systématique** avant chaque contrôle, plus seulement
    quand l'URL a changé), la même ronde donne **0 CASSÉ** sur ces 4 routes.
    **Règle** : re-naviguer avant chaque activation, sans se fier au changement d'URL.

11. **Le ratio near-white seul ne prouve pas un canvas vide.** « Préférences de notifications »
    (pharmacie) mesure **0,974 de pixels quasi-blancs** et est pourtant un écran de réglages parfaitement
    rendu, avec 10 contrôles (Retour + 3 sections + 5 interrupteurs). Idem l'accueil infirmière (0,974)
    et `/financial` patient (0,919). **Règle** : ne conclure « canvas vide » que si le ratio > 0,92
    **ET** l'inventaire Semantics est vide (≤ 1 contrôle) — critère désormais appliqué par le harnais.

12. **Rappel confirmé du piège nº 8 (SnackBar invisible dans Semantics).** « Joindre un patient, un
    devis… » et « Épingler » (`/team-messages` secrétariat) sortent MORTS : 0 requête, 0 navigation,
    0 repeinture, nombre de contrôles inchangé (29 → 29). La capture montre pourtant le SnackBar
    « Joindre un objet du produit au message : à venir » — ce sont des **jalons assumés** (`onPressed`
    affichant explicitement « : à venir », `cabinet_team_messages_page.dart:1008-1036`), pas des bugs.
    Non rapportés.

13. **Une liste DÉFILANTE ne se juge jamais sur le seul arbre Semantics.** Flutter n'y expose que les
    éléments **construits/visibles** ; l'inventaire tronque en plus chaque libellé à 90 caractères.
    Sur un fil de messagerie de 32 messages, le message du jour n'apparaissait dans aucune de mes
    lectures Semantics — j'en ai conclu « jamais rendu » et **filé un P1 (#6469) que j'ai dû refermer
    moi-même comme faux positif** : après 40 crans de molette, tout est bien à l'écran (capture
    `qa/screenshots/patient/rev-fil-pharma-bas.png`). Le contre-exemple qui aurait dû m'alerter plus
    tôt : un fil **court** (4 messages) affichait bien son dernier message, ce qui rendait l'hypothèse
    « troncature » incohérente.
    **Règle** : sur toute liste défilante, exiger une **capture après défilement jusqu'en bas** avant
    de conclure « non rendu » — et se méfier d'une conclusion qui ne tient que sur les fils longs.

### Ronde 2026-09-04 (12:00–14:00 UTC) — audit bouton par bouton, 5 apps

| app | écran/route | contrôles inventoriés | activés | OK | morts (vérifiés) | cassés | last_check |
|---|---|---|---|---|---|---|---|
| praticien | / (Tableau de bord) | 21 | 15 | 15 | 0 | 0 | 2026-09-04T13:30:00+00:00 |
| praticien | /waiting-room | 23 | 17 | 16 | 0 (1 auto-nav) | 0 — mais **1 DÉSACTIVÉ ILLÉGITIME** : « Appeler » de la ligne, grisé sur le patient du praticien lui-même → #6446 | 2026-09-04T13:30:00+00:00 |
| praticien | /patients | 34 | 25 | 13 | 0 (1 auto-nav) | 0 vérifié — les 11 « CASSÉ » sont des **403 « relation de soin » légitimes**, correctement rendus en bandeau info sans « Réessayer » (#6426 confirmé corrigé) | 2026-09-04T13:30:00+00:00 |
| praticien | /ordonnances | 17 | 14 | 12 | 0 (1 auto-nav) | 0 vérifié (1 transitoire non reproduit) | 2026-09-04T13:30:00+00:00 |
| praticien | /lab-work-orders | 36 | 20 | 18 | 0 (2 auto-nav) | 0 | 2026-09-04T13:30:00+00:00 |
| patient | / (Accueil) | 20 | — (inventorié + parcours métier) | — | 0 | 0 | 2026-09-04T13:30:00+00:00 |
| patient | /mes-rdv | 12 | 7 | 3 + 4 re-vérifiés OK | 0 vérifié (« Plus d'actions » ouvre bien un menu contextuel « Ajouter au calendrier » / « Annuler ») | **1 : « Je suis là » → 409 `invalid_status` + SnackBar générique → #6447** | 2026-09-04T13:30:00+00:00 |
| patient | /appointments (Réservation) | 25 | 17 | 7 + 6 re-vérifiés OK | 0 vérifié — les pastilles de créneau (« 15:00 », « 15:30 ») sont **fonctionnelles** (`POST /v1/slots/:id/hold` → 200, ouverture de l'écran de réservation) | **2 : puces « Disponible » et « Généraliste » → 0 résultat sur 17 → #6449** | 2026-09-04T13:30:00+00:00 |
| patient | /documents (Coffre-fort) | 40 | 19 | 6 + 8 facettes re-vérifiées OK après défilement horizontal | 0 vérifié (cf. leçon nº 9) | 0 en UI — mais **le fichier téléchargé est en 404 pour 12 documents sur 12 → #6453 (P0)** | 2026-09-04T13:30:00+00:00 |
| patient | /financial (Mes devis) | 11 | 8 | 7 | **1 : « Retour » inerte en accès par URL directe, écran sans barre d'onglets → #6455** | 0 | 2026-09-04T13:30:00+00:00 |
| patient | /notifications | 22 | 16 | 15 | 0 (1 facette déjà sélectionnée) | 0 | 2026-09-04T13:30:00+00:00 |
| patient | /messaging | 9 | 8 | 8 | 0 | 0 | 2026-09-04T13:30:00+00:00 |
| patient | /profile | 17 | 8 | 6 | 0 vérifié (« Modifier la photo » = sélecteur natif, cf. piège nº 7 ; « Authentification biométrique » indisponible sur Chromium bureau) | 0 | 2026-09-04T13:30:00+00:00 |
| secretariat | /agenda | 30 | 12 ciblés (clavier + volet) | 12 | 0 | 0 | 2026-09-04T13:30:00+00:00 |
| secretariat | /stock | 39 | 30 | 27 | 0 vérifié (2 en-têtes de section du rail) | 0 vérifié (1 = 403 `/cabinet/stats/activity`, #6369 connu) | 2026-09-04T13:30:00+00:00 |
| secretariat | /liste-attente | 20 | 17 | 15 | 0 vérifié (2 auto-nav) | 0 | 2026-09-04T13:30:00+00:00 |
| secretariat | /team-messages | 31 | 21 | 15 | 0 vérifié — les 6 « morts » sont 2 auto-nav, 2 en-têtes de rail et 2 jalons « : à venir » assumés (cf. leçon nº 12) | 0 | 2026-09-04T13:30:00+00:00 |
| secretariat | /encaissements | 1 | 1 | 1 | 0 | 0 — **route inexistante** : `/encaissements` rend la page « Page introuvable » (la vraie route est `/cabinet-payouts`). 404 applicatif **propre**, avec « Retour à l'accueil » fonctionnel : pas un bug | 2026-09-04T13:30:00+00:00 |
| pharmacie | / (File des commandes) | 34 | 17 | 15 | 0 vérifié (1 auto-nav, 1 facette déjà active) | 0 | 2026-09-04T13:30:00+00:00 |
| pharmacie | /devis | 18 | 12 | 9 | 0 vérifié (1 auto-nav, 2 facettes re-vérifiées OK isolément) | 0 | 2026-09-04T13:30:00+00:00 |
| pharmacie | /stock | 30 | 16 | 14 | 0 vérifié (1 auto-nav, 1 facette déjà active) | 0 | 2026-09-04T13:30:00+00:00 |
| pharmacie | /messages | 17 | 13 | 11 | 0 vérifié (1 auto-nav, 1 facette déjà active) | 0 | 2026-09-04T13:30:00+00:00 |
| infirmiere | / (Disponibilité / Offres / Ma visite) | 7 | 5 | 4 | 0 (1 = onglet courant) | 0 | 2026-09-04T13:30:00+00:00 |
| secretariat | /bookable-slots | 28 | 24 | 21 | 0 vérifié (2 en-têtes de rail) | 0 vérifié (1 = « Statistiques » → 403 `/cabinet/stats/activity`, #6369) | 2026-09-04T13:50:00+00:00 |
| secretariat | /appointment-motifs | 25 | 21 | 18 | 0 vérifié (2 en-têtes de rail) | 0 vérifié (idem #6369) | 2026-09-04T13:50:00+00:00 |
| secretariat | /cabinet-payouts (Encaissements) | 24 | 20 | 17 | 0 vérifié (3 en-têtes de rail / auto-nav) | 0 | 2026-09-04T13:50:00+00:00 |
| secretariat | /admin-membres | 23 | 18 | 16 | 0 vérifié (2 auto-nav) | 0 | 2026-09-04T13:50:00+00:00 |
| praticien | /consultation | 34 | ~20 | ~18 | 0 vérifié — **question ouverte de la ronde précédente tranchée** : la facette « Terminée » est la facette PAR DÉFAUT (34 contrôles avant comme après), « En cours » et « Annulée » filtrent réellement (34 → 18). Faux positif confirmé | 0 | 2026-09-04T13:50:00+00:00 |
| praticien | /devis | — | — | — | 0 vérifié (auto-nav) | 0 | 2026-09-04T13:50:00+00:00 |
| praticien | /stock, /team-messages | — | — | — | 0 | 0 | 2026-09-04T13:50:00+00:00 |
| patient | /profile/dependents | 24 | 17 | 17 | 0 | 0 | 2026-09-04T13:45:00+00:00 |
| patient | /profile/consents | 10 | 4 | 2 | 0 vérifié — les 3 « Détails » affichent un SnackBar « Détails du consentement bientôt disponibles. » (jalon assumé, `consents_page.dart:719`) | 0 — mais **3 interrupteurs sur 4 ont un nom accessible VIDE → #6458** | 2026-09-04T13:45:00+00:00 |
| patient | /treatment-plans | 11 | 7 | 7 | 0 | 0 | 2026-09-04T13:45:00+00:00 |
| patient | /reviews | **0** | 0 | 0 | — | — **écran SANS AUCUNE commande → #6457** | 2026-09-04T13:45:00+00:00 |
| patient | /oubliettes | 1 | 0 | 0 | — | — **1 nœud non interactif, aucune sortie → #6457** | 2026-09-04T13:45:00+00:00 |
| patient | /pharmacy (Ma pharmacie) | 6 | 5 | 3 | 0 vérifié (« Itinéraire » / « Appeler » ouvrent des URI externes `maps:`/`tel:`, invisibles au harnais) | 0 | 2026-09-04T13:45:00+00:00 |
| patient | /pharmacy/orders | 17 | 13 | 13 | 0 | 0 | 2026-09-04T13:45:00+00:00 |
| patient | /implant-passport | 6 | 5 | 2 | 0 vérifié (2 cartes d'implant non navigables — à confirmer) | **1 : « Exporter en PDF » → 302 puis 404 sur l'URL signée → #6461** | 2026-09-04T13:45:00+00:00 |
| patient | /home-care (Soins à domicile) | 18 | 14 | 14 | 0 | 0 | 2026-09-04T13:45:00+00:00 |
| praticien | /ordonnances + /ordonnances/new | 17 (+31 sur la composition) | 14 | 12 | 0 vérifié (1 auto-nav) | 0 en UI — mais **le bandeau d'allergies affiche des Map Dart bruts → #6460** | 2026-09-04T13:45:00+00:00 |
| praticien | /consultation | 34 | 27 | 25 | 0 vérifié (facette « Terminée » = facette par défaut, prouvé) | 0 | 2026-09-04T13:45:00+00:00 |
| praticien | /devis | 25 | 19 | 18 | 0 vérifié (auto-nav) | 0 | 2026-09-04T13:45:00+00:00 |
| praticien | /stock | 19 | 15 | 13 | 0 vérifié (auto-nav) | 0 vérifié | 2026-09-04T13:45:00+00:00 |
| praticien | /team-messages | 19 | 14 | 12 | 0 vérifié (auto-nav + en-têtes) | 0 | 2026-09-04T13:45:00+00:00 |
| secretariat | /patients (Fiches patients) | 40 | 30 | 27 | 0 vérifié (3 en-têtes de rail / facette déjà active) | 0 — mais **colonne « Contact » vide sur 28 lignes sur 28 → #6463** ; compteurs de facettes vérifiés **exacts** contre l'API (Impayés 2 / Alertes 24 / Sans RDV 22 sur 28) | 2026-09-04T14:10:00+00:00 |
| secretariat | /devis | 52 | 30 | 28 | 0 vérifié (2 en-têtes de rail) | 0 | 2026-09-04T14:10:00+00:00 |
| secretariat | /appointments | 25 | 21 | 18 | 0 vérifié (3 auto-nav) | 0 | 2026-09-04T14:10:00+00:00 |
| secretariat | /audit-log | 24 | 20 | 19 | 0 vérifié (1 auto-nav) | 0 (403 owner/admin only, cohérent avec `/cabinet/members`) | 2026-09-04T14:10:00+00:00 |
| praticien | /agenda | 25 | 19 | 18 | 0 vérifié (auto-nav) | 0 | 2026-09-04T14:10:00+00:00 |
| praticien | /stock-inventory | 40 | 22 | 20 | 0 vérifié (auto-nav) | 0 vérifié — « Mouvement » ouvre bien la modale « Mouvement de stock — <article> » (Type / Quantité reçue / Annuler / Valider) ; le PAGEERROR du lot n'est pas reproductible et le ratio blanc 0,097 était le **scrim** de la modale, pas un écran vide | 2026-09-04T14:10:00+00:00 |
| praticien | /messages | 25 | 21 | 19 | 0 vérifié (auto-nav) | 0 vérifié (PAGEERROR transitoire non reproduit) | 2026-09-04T14:10:00+00:00 |
| patient | /book (Booker un RDV) | 25 | 16 | 16 | 0 | 0 | 2026-09-04T14:25:00+00:00 |
| patient | /profile/notifications | 17 | 6 | 6 | 0 | 0 | 2026-09-04T14:25:00+00:00 |
| patient | /coverage-setup | 9 | 5 | 2 | 0 vérifié — les 3 radios (« Régime général » / « AME » / « CSS ») **fonctionnent** en re-clic isolé (`aria-checked` false → true + repeinture sur les 3) ; le lot les sortait MORTES parce que « Régime général » est **coché par défaut** et que la re-navigation entre contrôles remet ce défaut | 0 | 2026-09-04T14:25:00+00:00 |
| **TOTAL ronde** | **48 écrans distincts, 5 apps** | **1036** | **719** | **608** | **5 confirmés** (dont 1 désactivé illégitime) | **4 confirmés** | 2026-09-04T14:10:00+00:00 |

> Les colonnes « morts »/« cassés » ne comptent que ce qui a été **re-cliqué isolément et prouvé**.
> Les verdicts bruts du lot étaient de **84 MORT / 24 CASSÉ** ; après application des leçons nº 9 à 12
> et re-clic isolé de chaque cas, il en reste **5 morts/désactivés et 4 cassés réels**, tous filés —
> #6446 (« Appeler » désactivé à tort), #6447 (« Je suis là » → 409), #6449 (2 puces qui vident la liste),
> #6455 (« Retour » inerte), #6461 (« Exporter en PDF » → 404) — ou couverts par une issue API (#6453).
> **Un 20ᵉ finding a été filé puis refermé par moi-même** (#6469) : voir la leçon nº 13. Bilan retenu :
> **19 findings — 1 P0, 9 P1, 9 P2.**
> Les 11 « cassés » de praticien `/patients` sont des **403 « relation de soin » légitimes**, correctement
> rendus depuis #6426, et les 6 de secrétariat `/team-messages` des jalons « à venir » assumés.

### Adversariaux joués cette ronde (dialogue « Nouvelle demande de stock », secrétariat)
| cas | résultat |
|---|---|
| **Double-clic / double-submit** sur « Marquer arrivé » (agenda) | 1 seule requête, le bouton disparaît après succès — **OK** |
| **Double-clic** sur « Je suis là » (patient) | 2 requêtes, 2 × 409 — pas de doublon créé côté serveur, mais l'affordance n'aurait pas dû être offerte (#6447) |
| **Champ requis vide** → « Envoyer » | **0 requête réseau**, SnackBar « Choisissez une pharmacie. » — refus propre, **OK** |
| **Texte très long** (254 caractères) dans « Article » | aucun débordement : 0 contrôle hors viewport après saisie — **OK** |
| **Quantité** | champ à pas (« − 1 + ») avec « Diminuer » **désactivé à 1** : la borne minimale de la maquette est appliquée — **OK** |
| **Coupure réseau** (`route.abort()` sur `**/v1/**`) puis « Actualiser » | la liste **reste rendue** (39 → 27 contrôles, ratio blanc 0,744), ni écran blanc ni spinner infini — **OK** |
| **Back navigateur** au milieu du flux Accueil → « Devis à signer » | retour à l'Accueil, état cohérent (20 contrôles, « Bonjour Marc Dubois ») — **OK** |
| **URL directe** sur `/financial` puis « Retour » | **cul-de-sac** → #6455 |

### À traiter en priorité à la prochaine ronde
- **patient `/` et `/profile`** : lot d'activation partiel (15 + 13 inventoriés, 12 activés sur `/`).
- **praticien `/patients`** : à ré-auditer avec re-login à mi-parcours — le lot de cette ronde est
  inexploitable au-delà des 2 premiers contrôles (jeton expiré, cf. piège nº 6).
- **praticien `/consultation`** : la facette « Terminée » sort MORT sans re-clic isolé — piège nº 4
  probable (facettes « En cours »/« Terminée »/« Annulée » de longueur voisine), à prouver ou infirmer.
- **patient `/documents`** : inventorié, jamais activé. Note : les 13 « Télécharger » échoueront tous tant
  que #6425 (signer de stockage) n'est pas corrigé — inutile de les auditer avant.
- **patient `/book`** : re-tester les 5 puces après correction de #6431, et vérifier au passage que la carte
  se recentre sur les praticiens (elle retombe sur Paris, `_defaultCenter`, alors que le jeu de données est lyonnais).

### Parcours métier complets joués EN UI (exigence « au moins un par app »)
| app | parcours | résultat |
|---|---|---|
| secretariat | agenda → sélection d'un RDV `Confirmé` du jour → « Marquer arrivé » | `POST /cabinet/appointments/:id/checkin` → 200, le RDV quitte le volet — **OK** |
| praticien | salle d'attente → « Appeler MD » → `start` → `complete` | file vidée dans les 3 vues, RDV `done` — **OK** |
| patient | accueil → « Devis à signer » → « Mes devis » → back navigateur | navigation et état cohérents — **OK** (mais cul-de-sac en accès direct, #6455) |
| patient | /appointments → pastille de créneau « 15:00 » → écran de réservation | `POST /v1/slots/:id/hold` → 200, « Vendredi 4 septembre à 15:00 · Continuer » — **OK** |
| pharmacie | file → facette « Reçues » → « Préparer » → détail | `POST /pharmacy/orders/:id/accept` → 200, compteurs d'en-tête mis à jour en direct (12→11 reçues, 1→2 en préparation) — **OK** |
| infirmiere | Offres → « Accepter » → « Je pars » → « Je suis arrivé·e » → « Visite terminée » | 4 × 200 (`accept`, `en-route`, `arrived`, `done`), libellés FR, « Statut : Acceptée » affiché entre-temps — **OK** |
| patient | /profile/consents (390) | 9 | 5 | 4 | 0 | 0 | 2026-09-04T21:45:00+00:00 |
| pharmacie | / (File des commandes, 1280) | 33 | 19 | 18 | 0 | 0 | 2026-09-04T21:45:00+00:00 |
| secretariat | /salle-attente (1280) | 20 | 18 | 17 | 0 | 0 | 2026-09-04T21:45:00+00:00 |
| praticien | /waiting-room (1280) | 17 | 15 | 14 | 0 | 0 | 2026-09-04T21:45:00+00:00 |
| infirmiere | / (390) | 6 | 5 | 5 | 0 | 0 | 2026-09-04T21:45:00+00:00 |
| patient | /profile/consents (390) | 11 (+3 « Détails » peints hors arbre) | 9 | 9 (les 4 bascules émettent bien `PUT /account/consents/:purpose` ; les 2 « Détails » exposés ouvrent la feuille #6478) | 0 | 0 — mais **3 « Détails » sur 5 sans nœud Semantics propre (tap absorbé par la section, dont un nœud de 6 px) → #6502** ; **3 bascules sur 4 révoquent sans feuille de conséquences → #6501** | 2026-09-05T00:15:00+00:00 |
| patient | /treatment-plans + /treatment-plans/:id (390) | 13 | 3 | 3 (les cartes de plan naviguent, « Consulter et signer le devis » présent au détail) | 0 | 0 en UI — mais **la section « À VOTRE DÉCISION » ne peut jamais se construire (champ API absent) → #6503** ; détail sans flèche « Retour » | 2026-09-05T00:25:00+00:00 |
| praticien | /waiting-room (1280, file NON vide) | 23 | 5 ciblés (héros + ligne + Actualiser) | 4 | 0 | 0 cassé — **1 DÉSACTIVÉ ILLÉGITIME confirmé** : « Appeler » de la ligne du propre patient du praticien, `aria-disabled=true` (#6504) | 2026-09-05T00:35:00+00:00 |
| praticien | / (Tableau de bord, 1280) | 19 | 2 | 2 | 0 | 0 — « Ma journée » affiche « Aucun rendez-vous aujourd'hui / 0 RDV » alors que le cabinet en a 1 (#6239 connu, toujours ouvert) | 2026-09-05T00:12:00+00:00 |
| secretariat | / (Tableau de bord, 1280) | 24 | 5 (hors rail de navigation) | 5 | 0 | 0 vérifié — les 403 `/cabinet/members` + `/cabinet/audit-log` sont émis au CHARGEMENT de toute page secrétariat, pas par les clics (faux positif levé) | 2026-09-05T00:38:00+00:00 |
| secretariat | /salle-attente (1280, file vide) | 22 | 2 | 1 | 0 | 0 — « Appeler suivant » légitimement désactivé (0 patient présent), état vide « Salle d'attente vide / Aucun patient en salle d'attente. » propre | 2026-09-05T00:40:00+00:00 |
| pharmacie | /devis (1280) | 21 | 21 | 21 | 0 | 0 | 2026-09-05T00:45:00+00:00 |
| pharmacie | /stock (1280) | 13 | 10 | 10 | 0 | 0 (3 « Refuser — motif obligatoire » non activés : destructifs) | 2026-09-05T00:47:00+00:00 |
| infirmiere | / (Disponibilité / Offres / Ma visite, 390) | 6 | 5 | 5 (la bascule « En ligne » émet bien `PATCH /nurse/availability` — effet prouvé côté patient : `GET /search/nurses?online_only=true` passe de 1 à 0 résultat puis revient à 1) | 0 | 0 (« Se déconnecter » non activé) | 2026-09-05T00:42:00+00:00 |
| **TOTAL ronde 38** | **9 écrans, 5 apps** | **152** | **62** | **60** | **0** | **1 désactivé illégitime (#6504) + 3 contrôles hors arbre Semantics (#6502)** | 2026-09-05T00:50:00+00:00 |
## Ronde 2026-09-05 (12:00–15:00 UTC) — audit de commandes, ciblage diff-driven des 23 merges de la nuit

Méthode : inventaire depuis l'**arbre Semantics** (jamais de mémoire), activation de chaque contrôle,
verdict OK / MORT / CASSÉ / DÉSACTIVÉ / HORS-ÉCRAN. **Ré-atterrissage sur la route entre deux
activations** dès que l'écran a bougé — sans quoi on juge un écran empilé (voir piège nº 14 ci-dessous).

| app | écran/route (viewport) | inventoriés | activés | OK | morts confirmés | cassés confirmés | levées / notes | last_check ISO |
|---|---|---|---|---|---|---|---|---|
| praticien | /notification-preferences (1280x800) | 13 | 13 | 13 | **0** | **0** | 13 interrupteurs, chacun émet un PATCH et bascule | 2026-09-05T12:14:00Z |
| infirmiere | / (390x844) | 7 | 7 | 5 | **0** | **0** | 1 MORT levé(s) | 2026-09-05T13:50:00Z |
| patient | / (1280x800) | 15 | 15 | 10 | **0** | **0** | 2 MORT levé(s) ; 3 hors écran | 2026-09-05T13:51:00Z |
| patient | /documents (1280x800) | 24 | 24 | 19 | **0** | **0** | 1 MORT levé(s) ; 4 hors écran | 2026-09-05T13:52:00Z |
| patient | /home-care (390x844) | 17 | 17 | 14 | **0** | **0** | 3 hors écran | 2026-09-05T13:53:00Z |
| patient | /implant-passport (390x844) | 5 | 5 | 4 | **0** | **0** | 1 MORT levé(s) | 2026-09-05T13:54:00Z |
| patient | /messaging (390x844) | 8 | 8 | 8 | **0** | **0** | — | 2026-09-05T13:55:00Z |
| patient | /pharmacy/orders (390x844) | 16 | 16 | 13 | **0** | **0** | 3 hors écran | 2026-09-05T13:56:00Z |
| patient | /treatment-plans (390x844) | 8 | 8 | 6 | **0** | **0** | 2 hors écran | 2026-09-05T13:57:00Z |
| pharmacie | / (1280x800) | 23 | 23 | 18 | **0** | **0** | 4 hors écran | 2026-09-05T13:58:00Z |
| pharmacie | /messages (1280x800) | 15 | 15 | 12 | **0** | **0** | 2 MORT levé(s) | 2026-09-05T13:59:00Z |
| pharmacie | /orders/c64be6aa-e126-4e6f-b8cf-bcb7fbe94433 (1280x800) | 3 | 3 | 3 | **0** | **0** | — | 2026-09-05T13:50:00Z |
| praticien | / (1280x800) | 18 | 17 | 15 | **0** | **0** | 1 MORT levé(s) | 2026-09-05T13:51:00Z |
| praticien | / (390x844) | 6 | 6 | 4 | **0** | **0** | 2 hors écran | 2026-09-05T13:52:00Z |
| praticien | /consultation (1280x800) | 32 | 32 | 26 | **0** | **0** | 1 MORT levé(s) ; 4 hors écran | 2026-09-05T13:53:00Z |
| praticien | /lab-work-orders (1280x800) | 24 | 22 | 18 | **0** | **0** | 2 MORT levé(s) ; 1 hors écran | 2026-09-05T13:54:00Z |
| praticien | /patients/d0000000-0000-0000-0000-0000000000d1/treatment-p (1280x800) | 30 | 30 | 26 | **0** | **0** | 3 MORT levé(s) | 2026-09-05T13:55:00Z |
| secretariat | /admin-membres (1280x800) | 22 | 22 | 17 | **0** | **0** | 3 MORT levé(s) ; 1 CASSÉ = 403 RBAC | 2026-09-05T13:56:00Z |
| secretariat | /agenda (1280x800) | 27 | 27 | 23 | **0** | **0** | 2 MORT levé(s) ; 1 hors écran | 2026-09-05T13:57:00Z |
| secretariat | /audit-log (1280x800) | 24 | 24 | 19 | **0** | **0** | 2 MORT levé(s) ; 2 CASSÉ = 403 RBAC | 2026-09-05T13:58:00Z |
| secretariat | /cabinet-stats (1280x800) | 24 | 24 | 18 | **0** | **0** | 4 MORT levé(s) ; 1 CASSÉ = 403 RBAC | 2026-09-05T13:59:00Z |
| secretariat | /patients/new (1280x800) | 5 | 5 | 0 | **0** | **0** | 4 MORT levé(s) ; 1 désactivé légitime | 2026-09-05T13:50:00Z |
| secretariat | /salle-attente (1280x800) | 25 | 25 | 20 | **0** | **0** | 4 MORT levé(s) ; « Appeler » prouvé OK ; « Prévenir le praticien » = stub « à venir » | 2026-09-05T13:51:00Z |
| secretariat | /team-messages (1280x800) | 26 | 26 | 20 | **0** | **0** | 5 MORT levé(s) | 2026-09-05T13:52:00Z |

**Total ronde : 24 écrans, 417 contrôles inventoriés, 414 activés, 331 OK — aucun contrôle mort ni cassé retenu.**

> *Portée exacte de cette affirmation, pour qu'elle soit relisible :* les 42 verdicts bruts MORT/CASSÉ se répartissent
> en **quatre causes documentées ci-dessous**. Pour chacune, au moins un cas a été **rejoué et prouvé individuellement**
> (les 10 puces de facette du coffre-fort re-testées après défilement horizontal ; les 4 champs de `/patients/new`
> relus par leur `value` et la fiche réellement créée en base ; le 403 de `/cabinet-stats` confronté à
> `ProPractitionerClaims` ET à l'écran « Réservé aux praticiens » ; « Motifs de RDV »/« Stock » du rail re-cliqués
> après défilement, qui naviguent alors correctement). **Les autres verdicts n'ont pas été rejoués un par un** :
> ils ont été rattachés à l'une de ces causes par leur signature (contrôle déjà actif de la route courante,
> coordonnée hors viewport, `textbox`, ou 4xx purement RBAC). Aucun n'a résisté à cet examen, mais un contrôle
> mort isolé pourrait s'y cacher — d'où les écrans listés en « à traiter en priorité » ci-dessous.

### Les 42 verdicts MORT/CASSÉ du lot automatique ont TOUS été levés — aucun n'était un vrai défaut

C'est le résultat le plus important de la ronde sur ce volet : **le lot brut annonçait 38 MORT + 4 CASSÉ sur 23 écrans, et la vérification ciblée les a tous expliqués.** (27 contrôles supplémentaires sont
sortis « hors écran », donc explicitement NON jugés plutôt que déclarés morts.) Détail des quatre causes :

1. **Contrôle déjà actif (majorité des cas)** — cliquer l'élément déjà sélectionné ne produit légitimement rien :
   onglet « Disponibilité » (infirmière), « Messages » et facette « Toutes 4 » (pharmacie /messages),
   « Tableau de bord » depuis `/`, « Statistiques » depuis `/cabinet-stats`, plan déjà ouvert dans
   `/treatment-plans`, « Messages »/« Équipe » depuis `/team-messages`.
2. **Hors viewport HORIZONTAL (8 cas)** — les puces de facette de `patient /documents` s'étendent de
   `x=16` à `x=1272` dans un rail à défilement horizontal, pour un viewport de **390 px** : 7 des 10 puces
   étaient hors écran et le clic tombait dans le vide. **Re-testées après défilement horizontal, les 10
   passent `checked=true` — 10/10 OK.** *Ma garde « hors écran » ne testait que l'axe vertical ; corrigée.*
3. **Signal de repeinture aveugle à la saisie (5 cas : les 4 champs de `/patients/new` + « Entité » de `/audit-log`)** — les 4 champs de `secretariat /patients/new`
   sortaient MORT parce que ma signature d'écran ne retenait que `label+x+y`, pas la **valeur** du champ.
   Relecture avec un lecteur de `value` : « Prénom » → `"QA-R41"`, « Nom » → `"FormTest157878"`,
   « Téléphone » → `"0612345678"`, « Date de naissance » → `"01/01/1990"` — **les 4 champs marchent**,
   le bouton passe de DÉSACTIVÉ à ACTIVÉ, et la soumission crée réellement la fiche (vérifié en base
   via `GET /cabinet/patients?q=FormTest` → 2 fiches avec le bon téléphone).
4. **403 RBAC légitime pris pour un « cassé » (4 cas : « Actualiser » de `/cabinet-stats` et `/admin-membres`, « Filtrer » et « Réinitialiser » de `/audit-log`)** — ces contrôles re-déclenchent un appel admin
   (`/cabinet/stats/activity`, `/cabinet/members`, `/cabinet/audit-log`) → 403, mais ce 403 est **la bonne RBAC** (`ProPractitionerClaims`,
   `cabinet_stats.rs:61`) et l'écran l'affiche correctement (« Réservé aux praticiens / Votre rôle ne
   permet pas d'afficher l'activité par praticien ») — c'est le correctif #6369, **confirmé en place**.

### Contrôles DÉSACTIVÉS dont la légitimité a été prouvée
| contrôle | écran | preuve |
|---|---|---|
| « Créer le dossier » | secretariat /patients/new | désactivé tant que le formulaire est vide ; **passe à ACTIVÉ** dès les 4 champs remplis, puis `POST /cabinet/patients/quick` crée la fiche (persistance vérifiée en API). Désactivation légitime. |

### Pièges de méthode (à relire avant la prochaine ronde)
- **nº 14 (NOUVEAU, coûteux) — l'écran empilé sans changement d'URL.** Ouvrir « Préférences de
  notifications » depuis le rail empile l'écran **sans changer l'URL** (c'est le bug #6541). Un audit qui
  se fie à l'URL pour savoir « suis-je encore sur ma route ? » continue alors de cliquer sur l'écran
  empilé en croyant auditer `/devis` : mon premier lot praticien a produit une dizaine de faux MORT
  sur des interrupteurs de préférences qui n'avaient rien à faire là. **Toujours comparer la signature
  de l'inventaire, pas l'URL.**
- **nº 15 — hors écran horizontal.** Voir cause 2 : tester `x` autant que `y` avant de conclure MORT.
- **nº 16 — la saisie ne change ni le libellé ni la position.** Pour un `textbox`, le seul signal fiable
  est la **relecture de `value`** (ou `aria-valuetext`), pas la repeinture de l'arbre.
- **nº 17 — une capture peut expirer sur un écran lourd.** `page.screenshot()` a dépassé 30 s sur le fil
  de 155 messages de `patient /messaging` et a **tué le run** (routes suivantes perdues). Capture
  désormais encapsulée avec repli à `-1`.
- **nº 18 (NOUVEAU) — couper `**/v1/**` PUIS recharger, c'est tester la déconnexion, pas la page.**
  Un `route.abort()` sur tout `/v1/` suivi d'un `reload()` fait aussi échouer le bootstrap de session :
  l'app retombe légitimement sur l'écran de connexion. Mon heuristique a lu « 6 contrôles, ratio blanc
  0,937, aucun message d'erreur » et conclu à un écran blanc — **la capture montre la page de login**,
  parfaitement rendue (`qa/screenshots/patient/r41-adv-reseau-documents.png`). Pour éprouver la
  résilience d'un ÉCRAN, couper les seules routes de données **sans recharger** et déclencher l'action
  depuis la page déjà chargée — c'est ce que faisait le test pharmacie de la ronde précédente (« la
  liste reste rendue, 39 → 27 contrôles »). Toujours ouvrir la capture avant de conclure « écran blanc ».
- **nº 19 (NOUVEAU) — un `SnackBar` Flutter n'apparaît PAS dans ma signature d'écran.**
  Trois contrôles sont sortis MORT alors qu'ils déclenchent bien un bandeau : « Épingler » et
  « Joindre un patient, un devis… » de `/team-messages` (`cabinet_team_messages_page.dart:1013`, `:1031`)
  et « Prévenir le praticien » de `/salle-attente` (`waiting_room_page.dart:168-174`, snackbar
  « Notification du praticien à venir »). Ce sont des **jalons « à venir » assumés dans le code**, pas des
  boutons morts — mais ma signature (`label+x+y` des nœuds Semantics) ne les distingue pas d'un vrai
  no-op. **Pour trancher un MORT sur un bouton sans navigation ni requête : lire le code du `onPressed`
  AVANT de conclure**, ou capturer une image juste après le clic et y chercher le bandeau.
- **Rappel nº 6 (toujours d'actualité)** : les jetons expirent en ~15 min et `POST /auth/login` est
  rate-limité à ~4 connexions par fenêtre — partagé entre les sondes API et les logins Playwright.
  Reconnexion paresseuse (seulement si `exp - now < 120 s`) + backoff 20/40/60 s sur 429.

### À traiter en priorité à la prochaine ronde
- **secretariat — en-tête de section « Ma journée » du rail : verdict INCOHÉRENT entre écrans, à trancher.**
  Sorti OK (repeinture) depuis `/cabinet-stats`, mais MORT depuis `/agenda`, `/audit-log` et
  `/admin-membres`. Hypothèse à vérifier : un en-tête de section refuserait de se replier quand la
  route active est DANS cette section (`Agenda` est sous « Ma journée ») — mais cela n'explique pas
  `/audit-log` ni `/admin-membres`, dont la route active est sous « Réglages du cabinet ». À reprendre
  avec un signal réel (compter les entrées de rail visibles avant/après clic), pas la seule repeinture.
- **patient `/messaging` et `/implant-passport`** : perdus par le timeout de capture (piège nº 17),
  ré-audités en fin de ronde — reprendre si le lot est incomplet.
- **praticien `/lab-work-orders`** : jamais comparé à `Praticien Travaux labo v2.html`.
- **secretariat `/audit-log`, `/admin-membres`** : les deux appellent des routes `ProAdminClaims`
  (403 pour les comptes de démo) — vérifier qu'ils affichent un état « réservé » comme `/cabinet-stats`
  (#6369) et non une erreur brute.
- **pharmacie `/orders/:id` (Délivrance)** : re-vérifier le panneau des lignes d'ordonnance après #6368
  (`prescriberName` transmis au panneau).

---

## Ronde 2026-09-05 (18:00–20:30 UTC) — 5 apps, ciblage diff-driven des 2 merges API de 17h56–18h00

Contexte de ciblage (Étape 1bis) : depuis le dernier commit de registre (`4d03521`), **aucun fichier
`front/` n'a bougé** — seuls `api/src/scheduling.rs` et ses tests. Les deux merges (#6549 `patient_id`
dans la salle d'attente, #6548 `deny_unknown_fields` sur le PATCH RDV) ont donc été **re-vérifiés de
droit** en priorité, puis le budget est allé aux écrans jamais audités et aux points laissés ouverts par
la ronde précédente.

| app | écran/route (viewport) | inventoriés | activés | OK | morts confirmés | cassés confirmés | levées / notes | last_check ISO |
|---|---|---|---|---|---|---|---|---|
| praticien | `/` Tableau de bord (1280) | 23 | 1 | 1 | 0 | 0 | **#6549 re-vérifié en UI** : « Ouvrir le dossier » du hero navigue bien vers `/patients/d0000000-…-d1` (et non plus l'annuaire), avec `GET /cabinet/patients/<id>` émis. Correctif confirmé bout-en-bout. | 2026-09-05T18:07:00+00:00 |
| praticien | `/lab-work-orders` (1280) | 22 | 9 | 9 | 0 | 0 | « Nouveau bon » sorti MORT par le détecteur → **levé** : `lab_work_orders_page.dart:139-148` affiche un `SnackBar` « Création de bon de travail à venir » (jalon assumé, invisible dans ma signature — piège nº 19). « Marquer retourné » et « Programmer la pose » émettent bien leur requête. | 2026-09-05T18:12:00+00:00 |
| praticien | `/stock-inventory` (1280) | 28 | 15 | 12 | 0 | 0 | 3 « Mouvement » MORT → **levés** : ce sont les 3 dernières lignes, hors viewport vertical (piège nº 2). Les 8 premières sont OK. | 2026-09-05T18:15:00+00:00 |
| praticien | `/ordonnances` (1280) | 17 | 4 | 4 | 0 | 0 | « Choisir un patient » ouvre bien le sélecteur. | 2026-09-05T18:14:00+00:00 |
| praticien | `/devis` (1280) | 24 | 11 | 9 | 0 | 0 | 2 cartes MORT → **levées** (hors viewport, mêmes 2 dernières lignes). Les 6 premières cartes ouvrent le détail. Montants « 33,25 € » / « 100 € » : `_formatCents` local (`devis_page.dart:553`) duplique `formatQuoteCents(alwaysShowDecimals:false)` — non filé (option documentée, pas de maquette v2 pour cet écran). | 2026-09-05T18:16:00+00:00 |
| praticien | `/patients/:id` Dossier patient (1280/1440/1920) | 49 | — | — | — | — | Audité en **structure** plutôt qu'en activation : la page fait 115 600 px → **#6559**. Les 5 actions du pied sont atteignables (prouvé par 60× molette 20 000 px), donc ni mortes ni cassées — seulement à 128 écrans du haut. | 2026-09-05T18:38:00+00:00 |
| secretariat | `/` Tableau de bord + rail (1280) | 28 | — | — | — | — | Inventaire de navigation pour la comparaison design-v2. Badges peints 3 / 7 / 31 mais absents des Semantics → **#6555**. | 2026-09-05T18:20:00+00:00 |
| secretariat | `/patients` Fiches patients (1280) | 44 | 5 | 4 | 0 | 0 | Volet latéral conforme au clic sur une ligne. **4 touches clavier prouvées sans effet** (`/`, `↑`, `↓`, `⏎`) alors que la pastille « ⌘N » est peinte → **#6558**. | 2026-09-05T18:34:00+00:00 |
| secretariat | `/cabinet-payouts` Encaissements (1280) | 26 | 3 | 3 | 0 | 0 | « Mois précédent » ×2 → juillet 2026 se remplit (3 virements + « Détail » + « Analyser »). « Exporter (CSV) » grisé sur un mois vide = **DÉSACTIVÉ légitime prouvé**. | 2026-09-05T18:30:00+00:00 |
| secretariat | `/liste-attente` (1280) | 20 | 4 | 4 | 0 | 0 | RAS. | 2026-09-05T18:52:00+00:00 |
| secretariat | `/appointment-motifs` (1280) | 24 | 7 | 5 | 0 | 0 | « Motifs de RDV » MORT = nav de l'écran courant (piège nº 1). « Statistiques » CASSE → **levé** : navigue vers `/cabinet-stats`, dont le 403 est rendu en état « réservé » (#6369). | 2026-09-05T18:55:00+00:00 |
| secretariat | `/audit-log` (1280) | 24 | 8 | 5 | 0 | **2** | État « Accès réservé aux administrateurs » **correct** (cadenas + explication) — la question laissée ouverte par la ronde précédente est **tranchée : pas d'erreur brute**. Mais « Filtrer » et « Réinitialiser » restent actifs et rejouent un 403 silencieux → **#6561**. « Entité » MORT = textbox (piège nº 16). | 2026-09-05T18:57:00+00:00 |
| secretariat | `/admin-membres` (1280) | 22 | 6 | 3 | 0 | **1** | Même état « réservé » correct. « Actualiser » actif → 403 silencieux → **#6561**. Onglets « Membres »/« Secrétariats » MORT = onglet actif (piège nº 1). | 2026-09-05T18:58:00+00:00 |
| patient | `/implant-passport` (390) | 5 | 5 | 4 | 0 | 0 | La 4e carte MORT → **levée** : elle est réduite à 6 px de haut, rognée par le pied figé → c'est le symptôme de **#6560**, pas un bouton mort. | 2026-09-05T18:36:00+00:00 |
| patient | `/profile/dependents` (390) | 22 | 22 | 17 | 0 | 0 | 5 MORT → **levés** : les 5 contrôles des 2 dernières cartes, hors viewport (piège nº 2). « Planifier » / « Prendre RDV » / « Documents » émettent 10 à 18 requêtes chacun. | 2026-09-05T18:33:00+00:00 |
| patient | `/reviews` (390) | 1 | 1 | 1 | 0 | 0 | « Retour » fonctionne (l'écran à 0 commande de #6457 est corrigé) mais l'écran reste sans autre action. | 2026-09-05T18:33:00+00:00 |
| patient | `/home-care/new` (390) | 12 | 8 | 8 | 0 | 0 | Parcours complet joué : cocher « Injection » **active** « Obtenir un devis » (`aria-disabled` passe de `true` à absent), les 3 champs d'adresse acceptent la saisie. Voir la section adversariale ci-dessous. | 2026-09-05T18:46:00+00:00 |
| pharmacie | `/` File des commandes (1280) | 35 | — | — | — | — | Inventaire : 8 « Délivrer », 2 « Marquer prête », 4 puces de filtre avec compteurs (Toutes 56 / Reçues 10 / En préparation 3 / Prêtes 43). | 2026-09-05T18:25:00+00:00 |
| pharmacie | `/messages` (1280) | 15 | 14 | 12 | 0 | 0 | 2 MORT → **levés** (nav de l'écran courant + puce de filtre déjà sélectionnée). Les 4 fils s'ouvrent. | 2026-09-05T18:27:00+00:00 |
| pharmacie | `/stock` (1280) | 15 | 14 | 12 | 0 | 0 | 2 MORT → **levés** (idem). « Accepter » émet bien sa requête (effet constaté côté cabinet, ligne X7). | 2026-09-05T18:29:00+00:00 |
| pharmacie | `/orders/:id/pickup` (1280) | 4 | — | — | — | — | Atteint via le test de coupure réseau (voir adversariaux). | 2026-09-05T18:56:00+00:00 |
| infirmiere | `/` Disponibilité / Offres / Ma visite (390) | 7 | 6 | 5 | 0 | 0 | « Disponibilité » MORT = onglet actif (piège nº 1). L'interrupteur « En ligne » **émet bien son PATCH** — ⚠️ il a basculé mon infirmière hors ligne pendant un test API concurrent, cf. leçon nº 20. | 2026-09-05T18:23:00+00:00 |
| **TOTAL** | **21 écrans** | **446** | **141** | **123** | **0** | **3** | | |

### Adversariaux joués cette ronde
| cas | écran | résultat |
|---|---|---|
| Texte très long (240 caractères) dans un champ libre | patient `/home-care/new` (390) | **OK** — `ymax` reste à 844, **0 nœud hors cadre horizontal**. Pas de débordement. |
| Retour navigateur au milieu d'un flux | patient `/` → `/book` → `goBack()` | **OK** — retour propre à `/`, 16 contrôles interactifs, ni écran blanc ni cul-de-sac. |
| Double-clic rapide (60 ms) sur une action métier | patient `/home-care/new` → « Confirmer la demande » | **Non concluant** : le bouton est légitimement désactivé tant que l'étape « Obtenir un devis » n'a pas abouti (`onPressed: (state is! HomeCareRequestEstimated …) ? null : …`, `home_care_request_page.dart:158-166`), et la géolocalisation est indisponible en navigateur headless. À rejouer avec une position simulée. |
| Coupure réseau `route.abort()` sur `**/v1/**` **sans recharger**, puis action depuis la page déjà chargée | pharmacie `/` → clic « Délivrer » | **OK, erreur digne** — navigue vers `/orders/:id/pickup` et affiche « **Caméra indisponible — utilisez la saisie manuelle ci-dessous** » avec le champ « Code de retrait » + « Valider le code ». Ni écran blanc, ni spinner infini, `console.error` vide. |
| Géolocalisation refusée (navigateur headless) | patient `/home-care/new` → « Obtenir un devis » | **OK, erreur digne** — après le timeout de 10 s de `_defaultCurrentPosition` (`home_care_request_cubit.dart:146-155`), un `SnackBar` « **Position indisponible : activez la géolocalisation.** » s'affiche et le formulaire se déverrouille. Voir leçon nº 21. |

### Leçons de méthode ajoutées cette ronde
- **nº 20 (NOUVEAU) — ne jamais laisser tourner un audit UI et une sonde API sur le MÊME compte en parallèle.**
  Mon audit de l'app infirmière a activé l'interrupteur « En ligne » (c'est son travail) pendant que je
  testais X10 en curl : la demande de visite est alors partie alors qu'aucune infirmière n'était en ligne,
  elle est restée en `requested` sans offre, et j'ai failli conclure à un **fan-out cassé**. C'était mon
  propre test qui interférait. Après remise en ligne, la demande part en `offered` et l'offre arrive
  immédiatement. **Sérialiser, ou utiliser des comptes distincts.**
- **nº 21 (NOUVEAU) — un délai d'attente côté client se lit dans le CODE avant de crier au spinner infini.**
  « Obtenir un devis » n'émettait aucune requête et verrouillait le formulaire : j'ai attendu 4 s puis
  conclu au blocage. Le cubit borne en réalité la géolocalisation à **10 s**
  (`home_care_request_cubit.dart:148`) avant d'émettre son échec. En re-testant à 9,5 / 10,5 / 11,5 s et en
  **ouvrant la capture**, le `SnackBar` « Position indisponible » est bien là (piège nº 19 à nouveau : un
  `SnackBar` n'entre jamais dans la signature Semantics). **Lire le timeout, puis capturer autour.**
- **nº 22 (NOUVEAU) — les clés de réponse s'inventorient dans le code, pas au jugé.** Quatre faux
  « champ manquant » ce round, tous de mon fait : `POST /v1/cabinet/prescriptions` renvoie
  `prescription_id` (pas `id`), `POST /v1/cabinet/quotes` renvoie `quote_id`, `/v1/search/providers`
  renvoie `provider_id`, et `QuoteItemInput` attend `amount_cents` (pas `unit_amount_cents`). J'ai
  brièvement cru à « une création qui répond 201 sans écrire » — le RE-GET l'a démentie. **Toujours
  imprimer la réponse VERBATIM avant de la parser.**
- **Rappel nº 18/19 re-confirmés** : la coupure réseau pharmacie a produit un ratio de pixels quasi-blancs
  de **0,939** (au-dessus du seuil 0,92 « canvas vide ») alors que la capture montre un écran **parfaitement
  rendu** avec 3 contrôles. Le ratio de blanc seul ne prouve rien sur un écran clair — **ouvrir la capture**.

### À traiter en priorité à la prochaine ronde
- **praticien `/patients/:id`** : ré-auditer bouton par bouton une fois #6559 corrigé (les 49 contrôles
  n'ont pas pu être activés un à un tant que la page fait 128 écrans).
- **patient `/home-care/new`** : rejouer le double-submit avec une **géolocalisation simulée**
  (`context.grantPermissions(['geolocation'])` + `setGeolocation`), seul moyen d'atteindre
  « Confirmer la demande » et donc de tester le double POST.
- **praticien `/messages`, `/team-messages`, `/agenda`, `/consultation`** : non audités cette ronde.
- **patient `/messaging`, `/treatment-plans`, `/financial`, `/pharmacy/*`** : non audités cette ronde.
- **secretariat `/bookable-slots`, `/admin-secretariats`, `/team-messages`** : jamais audités.

### Second lot de la ronde 2026-09-05 (19:20–20:30 UTC) — 13 écrans de plus

| app | écran/route (viewport) | inventoriés | activés | OK | morts confirmés | cassés confirmés | levées / notes | last_check ISO |
|---|---|---|---|---|---|---|---|---|
| praticien | `/messages` (1280) | 24 | 11 | 11 | 0 | 0 | Les 8 fils s'ouvrent chacun sur SON fil. Le message X8 de cette ronde y est visible (« QA-R42 X8 cloisonnement… »), confirmant l'effet cross-app en UI. | 2026-09-05T19:24:00+00:00 |
| praticien | `/team-messages` (1280) | 18 | 5 | 4 | 0 | 0 | Le bouton d'envoi a un **libellé Semantics VIDE** → **#6564** (jumeau de #6544, fichier distinct de l'app praticien). Son verdict MORT est attendu (champ vide ⇒ `onPressed: null`). | 2026-09-05T19:25:00+00:00 |
| praticien | `/stock` (1280) | 18 | 5 | 5 | 0 | 0 | « Nouvelle demande » ouvre bien le dialogue. | 2026-09-05T19:26:00+00:00 |
| praticien | `/agenda` (1280) | 23 | 9 | 8 | 0 | 0 | Navigation semaine ±, « Série de RDV », « Inclure passés », « Filtrer par date » : tous OK. « Démarrer » MORT → **levé** : rect mesuré à **283,929** sur une fenêtre de 800 px — hors champ, le clic n'atteint jamais le bouton (piège nº 2). | 2026-09-05T19:45:00+00:00 |
| praticien | `/consultation` (1280) | 22 | 3 | 3 | 0 | 0 | Onglets « En cours » / « Terminée » fonctionnels. | 2026-09-05T19:28:00+00:00 |
| secretariat | `/bookable-slots` (1280) | 27 | 10 | 7 | 0 | 0 | « Créer un créneau », « Tous les praticiens », « Toutes les dates » OK. 2 MORT = nav de l'écran courant. 1 CASSE (« Statistiques » → 403) → **levé**, même état « réservé » que #6561. | 2026-09-05T19:30:00+00:00 |
| secretariat | `/admin-secretariats` (1280) | 21 | 5 | 5 | 0 | 0 | « Inviter un secrétariat » ouvre son dialogue. Contrairement à `/admin-membres`, cet écran **n'est pas admin-only** en lecture (cf. #5156) et affiche bien ses 2 secrétariats. | 2026-09-05T19:31:00+00:00 |
| secretariat | `/team-messages` (1280) | 18 | 7 | 5 | 0 | 0 | « Mentionner » OK. « Épingler » et « Joindre un patient, un devis… » MORT → **levés** : jalons `SnackBar` « à venir » déjà documentés (piège nº 19). | 2026-09-05T19:32:00+00:00 |
| patient | `/financial` (390) | 10 | 10 | 8 | 0 | 0 | Les 7 cartes ouvrent leur détail. 2 MORT = les 2 dernières, hors écran. **Les 9 cartes portent 2 libellés seulement** → **#6563**. | 2026-09-05T19:22:00+00:00 |
| patient | `/treatment-plans` (390) | 8 | 8 | 6 | 0 | 0 | 6 plans s'ouvrent, dont 2 cartes « À accepter » avec leur bouton « Consulter » (3 requêtes chacune). 2 MORT = les 2 dernières, hors écran. | 2026-09-05T19:23:00+00:00 |
| patient | `/pharmacy` (390) | 5 | 5 | 3 | 0 | 0 | « Envoyer une ordonnance », « Suivre mes commandes », « Changer de pharmacie » OK. « Itinéraire » et « Appeler » MORT → **levés** : ce sont des `url_launcher` vers des schémas externes (`openMapsDirections` / `callPhoneNumber`, `pharmacy_card.dart:87` et `:98`) — sans navigation ni requête XHR, invisibles à mon détecteur. | 2026-09-05T19:23:00+00:00 |
| patient | `/home-care/new` (390, **géoloc simulée**) | 12 | 6 | 6 | 0 | 0 | Parcours complet enfin joué de bout en bout — voir l'adversarial ci-dessous. | 2026-09-05T19:40:00+00:00 |
| pharmacie | `/devis` (1280) | 27 | 19 | 16 | 0 | 0 | Les boutons « Préparer » de ligne naviguent chacun vers **SA** commande (`/orders/085ccb0a…`, `/orders/c64be6aa…`, `/orders/4c88fb41…` — cibles distinctes, pas d'identifiant unique erroné). 3 MORT = dernières lignes hors écran. | 2026-09-05T19:35:00+00:00 |
| pharmacie | `/` File des commandes (**1440**) | 37 | — | — | — | — | Ré-inventaire au viewport de la maquette pour la comparaison design-v2 (voir `design-v2.md`). | 2026-09-05T19:50:00+00:00 |
| **TOTAL RONDE** | **34 écrans** | **~700** | **238** | **214** | **0** | **3** | | |

### Adversarial rejoué avec une position simulée (gap de la 1re moitié, refermé)
| cas | écran | résultat |
|---|---|---|
| **Double-clic rapide (50 ms) sur une action métier**, contexte Playwright avec `permissions:['geolocation']` + `geolocation:{45.7578, 4.8420}` | patient `/home-care/new` → « Confirmer la demande » | **OK — aucun double-envoi.** Avec une position disponible, « Obtenir un devis » émet bien `POST /v1/account/visit-requests/estimate` et le prix s'affiche, ce qui active « Confirmer la demande ». Deux clics à 50 ms d'intervalle ne produisent qu'**UN SEUL** `POST /v1/account/visit-requests`, aucun 4xx, aucune exception, et l'app navigue vers le suivi `/home-care/8798e81e-…`. *À noter : après l'affichage du prix, le bouton descend à y=862 sur une fenêtre de 844 — il faut défiler de 400 px pour l'atteindre, ce qui avait fait échouer mes deux tentatives précédentes.* |

### Faux positifs supplémentaires levés dans ce lot (aucun n'était un défaut)
- **`url_launcher` vers un schéma externe** (`tel:`, `maps:`) — nouveau motif, à ajouter à la liste des
  pièges : « Itinéraire » et « Appeler » de `patient /pharmacy` ne produisent ni navigation, ni requête,
  ni repeinture dans un navigateur sans gestionnaire de protocole. **Lire l'`onPressed` avant de conclure.**
- **Hors viewport, encore** : `praticien /agenda` « Démarrer » à y=929 sur 800 px ; les 2 dernières cartes
  de `patient /financial`, `/treatment-plans`, `pharmacie /devis`.
- **Jalons `SnackBar` déjà connus** : « Épingler » / « Joindre un patient, un devis… ».

### Troisième lot (20:30–21:15 UTC) — 6 écrans de plus

| app | écran/route (viewport) | inventoriés | activés | OK | morts confirmés | cassés confirmés | levées / notes | last_check ISO |
|---|---|---|---|---|---|---|---|---|
| patient | `/mes-rdv` (390) | 7 | 7 | 5 | 0 | 0 | « Historique » **fonctionne et émet 13 requêtes** — le compteur à 0 de #6448 ne se reproduit pas. 2 MORT → levés : onglet « À venir » **déjà actif**, et le 3e « Plus d'actions » hors écran. | 2026-09-05T20:35:00+00:00 |
| patient | `/notifications` (390) | 17 | 17 | **17** | 0 | 0 | **Écran le plus propre de la ronde : 17/17.** Les notifications produites par mes propres flux X3 y sont visibles et actionnables (« Votre commande est prête, vous pouvez la retirer » → « Afficher mon code »). | 2026-09-05T20:36:00+00:00 |
| patient | `/profile` (390) | 12 | 12 | 10 | 0 | 0 | 2 MORT → **levés par lecture du code** : « Modifier la photo de profil » appelle `_pickAndUpload` (`profile_page.dart:731`), un sélecteur de fichier natif qui n'ouvre rien en navigateur headless ; « Authentification biométrique » est un `Switch` (`:234-241`) qui ne réagit qu'à son curseur, pas au centre de la ligne (piège nº 3). | 2026-09-05T20:37:00+00:00 |
| patient | `/book` (390) | 26 | 3 | 3 | 0 | 0 | **Mécanique « 3 jours de créneaux » de la maquette VÉRIFIÉE** : la carte praticien porte bien 3 jours nommés — « Sam. 5 septembre — / Dim. 6 septembre — / Lun. 7 septembre » — avec le tiret comme **état vide par jour**, plus « 1re dispo · Lun. 7 sep ». Les créneaux sont de vrais boutons (`11:00`, `11:30`, `12:00`) et « Voir plus de créneaux » est présent. | 2026-09-05T20:40:00+00:00 |
| patient | `/` Accueil (390) | 20 | — | — | — | — | Inventaire pour la comparaison design-v2. **La carte « Reste à charge » y affiche 1 025 064,40 €** → **#6566**. | 2026-09-05T20:33:00+00:00 |
| praticien | `/waiting-room` (1280×834) | 12 | — | — | — | — | Ré-inventaire au viewport de la maquette (voir `design-v2.md`) — écran désormais très conforme. | 2026-09-05T20:20:00+00:00 |

### Nouveau piège à ajouter à la liste (nº 23)
- **nº 23 — les dialogues NATIFS du navigateur/OS sont invisibles à la sonde.** Trois motifs distincts
  rencontrés cette ronde, tous sortis MORT à tort : (a) `url_launcher` vers un schéma externe
  (`tel:` / `maps:` — « Appeler », « Itinéraire » de `patient /pharmacy`), (b) sélecteur de fichier natif
  (`_pickAndUpload` — « Modifier la photo de profil »), (c) API navigateur indisponible en headless
  (biométrie). **Aucun ne produit navigation, requête XHR ni repeinture.** Réflexe : lire l'`onPressed`
  avant tout verdict MORT — désormais 3 familles de faux positifs (nav active, hors viewport, dialogue natif)
  plus les `SnackBar` (nº 19) et les `Switch` (nº 3).

### Quatrième lot (21:15–21:45 UTC) — secrétariat, écrans restants

| app | écran/route (viewport) | inventoriés | activés | OK | morts confirmés | cassés confirmés | levées / notes | last_check ISO |
|---|---|---|---|---|---|---|---|---|
| secretariat | `/salle-attente` (1280) | 23 | 7 | **7** | 0 | 0 | **7/7.** « **Appeler MD** » est désormais **nommé** (point 1 de la maquette) et émet son `call-next` + rafraîchissement ; le bouton « Appeler » de ligne fonctionne aussi. « Prévenir le praticien » sort OK cette fois (repeinture détectée) — c'était le jalon `SnackBar` de la ronde précédente. | 2026-09-05T21:20:00+00:00 |
| secretariat | `/devis` (1280) | ~24 | 9 | 9 | 0 | 0 | Les 3 puces de filtre portent leur compteur (À signer 52 / Brouillons 74 / Signés 74) et basculent. Recherche « Patient, n° de devis… » fonctionnelle. | 2026-09-05T21:22:00+00:00 |
| secretariat | `/messages` (1280) | — | — | — | — | — | Lancé en fin de ronde, non terminé — **à reprendre en priorité à la prochaine ronde**. | — |
| **TOTAL RONDE (4 lots)** | **~42 écrans** | **~760** | **~254** | **~230** | **0** | **3** | | |

### Ronde 2026-09-06 (12:00–13:05 UTC) — ciblage diff-driven des merges du matin (#6236, #6580, #6588, #6579/#6589/#6590)

| app | écran/route | contrôles inventoriés | activés | OK | morts | cassés | notes | last_check |
|---|---|---|---|---|---|---|---|---|
| patient | `/pharmacy/quotes` (390) — **écran neuf #6580** | 7 | 7 | 5 | 0 | **2** | Premier audit de l'écran livré ce matin. `Retour` OK. Les 3 cartes « À signer » exposent `Accepter`/`Refuser` **non désactivés** ; sur un devis dont la commande est déjà `picked_up`, les deux répondent **409** et la carte reste décidable → **#6607**. La carte « Expiré » n'expose aucune action (correct). | 2026-09-06T13:05:00+00:00 |
| patient | `/documents` (390) | 25 | 14 | 12 | 0 | 0 | Puces de facettes (`Tous 284`, `Facture 41`, `Ordonnance 193`, `Radio 7`, `CBCT 2`, `Photo 8`, `Compte-rendu 5`, `Consentement 4`, `Consigne 4`, `Carte mutuelle 20`) **toutes vérifiées manuellement** : le clic filtre réellement (`aria-checked` false→true, la liste passe d'Ordonnances à Factures). La rangée déborde du viewport mais **défile** (molette + drag) → facettes atteignables, pas un bug. Méta de carte conforme depuis #6545. | 2026-09-06T13:05:00+00:00 |
| patient | `/notifications` (390) | 19 | 8 | 8 | 0 | 0 | « Tout marquer lu », 4 puces de famille et boutons d'action tous actifs. **Mais** : `Afficher mon code` est rendu sur les 3 états de commande (préparation/prête/retirée) et mène à un écran sans code → **#6610** ; la notif `quote_received` n'a aucun bouton d'action → **#6609**. Échec réseau sur une action = écran effacé → **#6613**. | 2026-09-06T13:05:00+00:00 |
| patient | `/messaging` + fil « Cabinet Lyon » (390) | 9 + 8 | 6 | 6 | 0 | 0 | Le bouton d'envoi existe (`role=button` @340,725 42x42) et **fonctionne** (POST /conversations/:id/messages) mais n'a **aucun nom accessible** (`aria-label` null, texte vide) → **#6614**. Puces de réponse rapide (`Proposer un créneau`, `Merci !`, `Je rappelle`) correctement nommées. Texte de 475 caractères : aucun débordement du viewport. | 2026-09-06T13:05:00+00:00 |
| patient | `/mes-rdv`, `/profile`, `/treatment-plans`, `/implant-passport`, `/profile/consents`, `/appointments`, `/pharmacy`, `/profile/dependents` (390) | 73 | 64 | 61 | 3 | 0 | Second lot, harnais corrigé (voir note de méthode). Les 3 « MORT » sont des onglets/filtres **déjà sélectionnés** (`À venir (20)` etc.) — comportement légitime, vérifié. | 2026-09-06T13:05:00+00:00 |
| praticien | `/agenda`, `/waiting-room`, `/patients`, `/ordonnances`, `/messages`, `/consultation`, `/notification-preferences` (1280) | 161 | 101 | 94 | 6 | 1 | Les 6 « MORT » sont tous des entrées du rail de navigation **de la page courante** (auto-navigation) — légitimes. L'unique « CASSÉ » (401 sur `PATCH /me/notification-preferences`) est une **expiration de session en cours de run**, pas un défaut produit. Salle d'attente : divergence design-v2 sur le nom du patient → **#6611**. | 2026-09-06T13:05:00+00:00 |
| secretariat | `/devis`, `/salle-attente`, `/agenda`, `/patients`, `/liste-attente`, `/bookable-slots`, `/messages`, `/notification-preferences` (1280) | 215 | 123 | 109 | 12 | 2 | `/devis` re-vérifié après #6579/#6589/#6590 : table stable, titres `DEV-xxxx` distincts, nom patient complet + pastille d'initiales. « MORT » = rail/filtres déjà actifs ; « CASSÉ » = 401 d'expiration de session. | 2026-09-06T13:05:00+00:00 |
| secretariat | `/`, `/stock`, `/team-messages`, `/cabinet-payouts`, `/appointments` (1280) | 136 | 77 | 68 | 8 | 1 | Second lot. Mêmes catégories de faux positifs (rail courant, filtre actif). | 2026-09-06T13:05:00+00:00 |
| pharmacie | `/` (file), `/stock`, `/devis`, `/messages`, `/notification-preferences` (1280) | 87 | 64 | 51 | 13 | 0 | File des commandes conforme à sa maquette (KPI 10+4+43 = 57 cohérents avec les puces). « MORT » = rail courant + puces de filtre déjà sélectionnées. | 2026-09-06T13:05:00+00:00 |
| infirmiere | `/` (Disponibilité/Offres/Ma visite) + `/notification-preferences` (390) | 10 | 9 | 7 | 2 | 0 | 5e app parcourue. Interrupteur « En ligne » fonctionnel (PATCH /nurse/availability). Les 2 « MORT » = onglet `Disponibilité` déjà actif + l'interrupteur relu avant repeinture. Écran très blanc (ratio 0.973) mais **pas** un canvas vide : arbre Semantics complet + rendu correct (vérifié au screenshot) — faux positif classique du ratio near-white sur écran minimal. | 2026-09-06T13:05:00+00:00 |
| **TOTAL RONDE 2026-09-06 (7 lots, 38 écrans, 5 apps)** | **38 écrans** | **737** | **473** | **408** | **55** | **10** | **MORT/CASSÉ confirmés après vérification manuelle : 0 mort, 2 cassés** (`Accepter`/`Refuser` de #6607). Les 53 autres « MORT » sont des rails/onglets/filtres déjà actifs, les 8 autres « CASSÉ » des 401 d'expiration de session en cours de run. | 2026-09-06T13:05:00+00:00 |
| praticien | `/` (Tableau de bord, 1280) | 18 | 8 | 7 | 1 | 0 | Rail complet + ⌘K + cloche + tuiles « Confirmations en attente 2 » / « Messages non lus 34 ». Le « MORT » est l'entrée de rail de la page courante. Lot interrompu ensuite (contention navigateur en fin de ronde) — `/devis`, `/stock`, `/inventaire`, `/labo`, `/messagerie-interne`, `/ordonnances/new` **restent à auditer, à reprendre en priorité**. | 2026-09-06T13:07:00+00:00 |
| pharmacie | `/orders/:id` (Délivrance, 1280) | 4 | 4 | **4** | 0 | 0 | `Retour`, `Créer un devis`, `Scanner le retrait`, `Voir l'original` — tous actifs et conformes au statut `ready`. Ratio near-white 0.962 signalé « canvas vide » par le détecteur : **faux positif** (page de détail avec grande zone vide sous le contenu), rendu vérifié au screenshot. | 2026-09-06T13:07:00+00:00 |
| praticien | `/devis`, `/stock` + 3 URL erronées (`/labo`, `/inventaire`, `/messagerie-interne`) (1280) | 45 | 27 | 25 | 2 | 0 | Les 2 « MORT » sont les entrées de rail de la page courante. **Les 3 URL inexistantes rendent un écran « Page introuvable » propre** (illustration + « Le lien que vous avez suivi n'existe plus ou a changé. » + CTA « Retour à l'accueil ») — **comportement correct**, pas un défaut. Les vraies routes sont `/stock-inventory`, `/lab-work-orders`, `/team-messages`. | 2026-09-06T13:30:00+00:00 |
| praticien | `/stock-inventory`, `/lab-work-orders`, `/team-messages` (1280) | 67 | 36 | 34 | 2 | 0 | Les 3 écrans manquants de la ronde sont désormais audités. « MORT » = rail de la page courante (`Inventaire`, `Labo`). Aucun contrôle cassé. | 2026-09-06T13:30:00+00:00 |
| secretariat | `/`, `/salle-attente`, `/devis`, `/patients` **au viewport 390x844** | 67 | — (audit de mise en page) | — | — | — | **Contrôle inter-viewport** (l'app est spécifiée PC 1280). `/devis` : **13 contrôles hors viewport** — les colonnes `Reste à charge`, `Statut`, `Échéance` et toute la colonne `Action` (`Relancer`/`Envoyer`/`PDF`, à x=801-896 pour 390 px de large) sont rognées, **sans défilement horizontal** (molette et drag vérifiés, sans effet). **Mais mitigation trouvée** : taper une ligne ouvre le volet de détail qui, lui, expose « Relancer le patient » et « Appeler » **dans** le viewport → les actions restent atteignables. Dégradation responsive, **pas un cul-de-sac** → non rapporté. Les 3 autres écrans ne débordent pas. | 2026-09-06T13:30:00+00:00 |
| patient | `/`, `/pharmacy/quotes`, `/documents`, `/mes-rdv` **au viewport 1280x800** | 81 | — (audit de mise en page) | — | — | — | **Contrôle inter-viewport** (app mobile-first). Aucun débordement horizontal, aucune cible tactile < 24 px. Ratio near-white > 0.92 sur 3 écrans : le contenu reste en colonne étroite centrée et la largeur n'est pas exploitée — **choix mobile-first assumé**, arbre Semantics complet (39 nœuds sur `/documents`), pas un canvas vide. | 2026-09-06T13:30:00+00:00 |


### Ronde 2026-09-06 (18:00–20:05 UTC) — 5 apps, ciblage diff-driven (#6611 salle d'attente, #6613/#6620 notifications, #6609/#6622 deep-link)

| app | écran/route (viewport) | inventoriés | activés | OK | morts | cassés | notes | last_check |
|---|---|---|---|---|---|---|---|---|
| praticien | `/waiting-room` (1280) | 25 | 20 | 18 | 2 | 0 | Les 2 « MORT » sont l'entrée de rail de la page courante et la cloche (voir la note de méthode nº 24 ci-dessous : **faux positif levé**, la cloche marche). `Appeler MD`, `Ouvrir le dossier`, `Actualiser` tous actifs. | 2026-09-06T18:20:00Z |
| secretariat | `/salle-attente` (1280, file de 3 puis 5 patients) | 24→30 | 20 + 15 (rail rejoué) + 4 (boutons de ligne) | 34 | **2 confirmés** | 0 | **Les 2 MORTS sont réels et filés (#6629)** : le bouton `Appeler` des lignes 2 et 3 — clic → `reqs=[]`, `http=[]`, 30 contrôles avant **et** après, URL inchangée, aucun message. Le même bouton sur la **ligne 1** émet `POST /cabinet/waiting-room/call-next` + refresh. Rail rejoué au harnais propre : 15/15 destinations correctes (`Encaissements`→`/cabinet-payouts`, `Devis`→`/devis`, `Fiches patients`→`/patients`…) ; les 5 « MORT » du rail sont les **en-têtes de section** (`Ma journée`, `Patients`, `Facturation`, `Messages`, `Réglages`) qui ne naviguent pas — légitime. | 2026-09-06T19:05:00Z |
| patient | `/notifications` (390) | 20 | 8 | 8 | 0 | 0 | « Tout marquer lu », 4 puces, tuiles et boutons d'action. **2 tuiles sans aucune action** → #6623 (`visit_status_changed`) et #6624 (`review_request`). Adversarial `route.abort()` sur `read-all` : **la liste survit** (20 contrôles avant **et** après) → **#6620 confirmé corrigé**. | 2026-09-06T18:35:00Z |
| patient | `/home-care` (390) | 18 | 14 | **14** | 0 | 0 | 14/14. Chaque carte de visite ouvre son détail (1 requête). | 2026-09-06T19:45:00Z |
| patient | `/home-care/new` (390) | 13 | 12 | 12 | 0 | 0 | **5 « MORT » du premier passage entièrement levés** — voir piège nº 25. Les 2 boutons sont `aria-disabled=true` **à juste titre** sur formulaire vide (`home_care_request_page.dart:144` et `:163`), et les 4 champs texte sortent MORT par limite du harnais (la signature Semantics ne contient pas la *valeur* d'un `textbox`). **Parcours métier complet rejoué avec géolocalisation accordée** : cocher un acte active « Obtenir un devis » → `POST /account/visit-requests/estimate` → « Confirmer la demande » s'active → `POST /account/visit-requests` → navigation vers `/home-care/<id>`. **Rien de cassé.** | 2026-09-06T20:15:00Z |
| patient | `/prescriptions` (390) | 17 | 12 | **12** | 0 | 0 | 12/12, chaque ordonnance ouvre son détail. Libellés de statut corrects (`Signée`, `Transmise à une pharmacie`). | 2026-09-06T19:50:00Z |
| patient | `/reviews`, `/home-care/:id` (390) | 1 + 2 | 3 | 3 | 0 | 0 | `/home-care/:id` rend bien la visite (« Visite terminée / Injection / Infirmière : Camille Infirmière / 43,00 € ») — c'est la **cible de deep-link manquante** de #6623. `/reviews` rend un état vide **en lecture seule** (« Aucun avis pour ce prestataire. ») : aucun champ de saisie → #6624. | 2026-09-06T18:25:00Z |
| infirmiere | `/` (3 onglets Disponibilité / Offres / Ma visite) + `/notification-preferences` (390) | 8 + 5 | 3 + 3 + 1 (cloche) | 7 | 0 | 0 | **5e app parcourue.** Les 3 onglets basculent, l'interrupteur « En ligne » émet `PATCH /nurse/availability`, les 2 bascules de préférences émettent leur requête. Les 3 onglets ont un **état vide correct** (« Aucune offre… », « Aucune visite en cours / Acceptez une offre pour démarrer une visite. ») — invisibles aux Semantics (texte simple), vérifiés **au screenshot**. | 2026-09-06T18:45:00Z |
| praticien | `/ordonnances/new`, `/patients/:id/treatment-plans` (**1440**) | 48 + 37 | — (audit de mise en page design-v2) | — | — | — | Inventaire pris pour la comparaison à `Ecrans PC` (cf. `design-v2.md`) → #6625, #6626. | 2026-09-06T19:15:00Z |
| pharmacie | `/` (file), `/orders/:id`, `/messages` (**1440**) | 37 + 5 + 17 | — (audit de mise en page design-v2) | — | — | — | Inventaire pris pour la comparaison à `Ecrans PC` / `Pharmacie Messagerie v2` → #6627, #6635. | 2026-09-06T19:20:00Z |
| 4 apps pro | cloche « Notifications » (praticien, secrétariat, pharmacie 1280 ; infirmière 390) | 4 | 4 | **4** | 0 | 0 | Voir piège nº 24. Les 3 apps PC ouvrent un panneau qui émet `GET /notifications` + `GET /notifications?unread_only=true&limit=1` et expose `Tout marquer lu` + `Fermer` + les notifications. L'infirmière ouvre un panneau au **bon état vide** (« Aucune notification / Les nouvelles offres apparaîtront ici. ») sans requête — sa liste est chargée à la construction de la page (`infirmiere_home_page.dart:35-38`), c'est correct. | 2026-09-06T19:00:00Z |
| **TOTAL RONDE 2026-09-06 (18:00–20:05), 1er lot** | **15 écrans, 5 apps** | **~277** | **~115** | **~110** | **2 confirmés (#6629)** | **0 confirmé** | | 2026-09-06T20:30:00Z |

### Cas adversariaux joués cette ronde

| cas | écran | résultat |
|---|---|---|
| **Coupure réseau pendant une action** (`route.abort()` sur `/v1/notifications/read-all` et `/:id/read`) | patient `/notifications` | **DIGNE.** 20 contrôles avant, **20 après** ; la liste n'est pas effacée, seule une `ERR_FAILED` apparaît en console. **#6620 confirmé corrigé en live.** |
| **Double-clic rapide sur une action métier** | secrétariat `/salle-attente`, bouton « Appeler MD » | **DÉFAUT → #6637 (P1).** Deux `POST /cabinet/waiting-room/call-next` partent, **tous deux 2xx**, et **deux patients** passent `checked_in`→`in_consultation` (KS `8aaa4373` **et** MD `9a1f8624`) sur un seul geste. `onPressed` ne garde que sur `entries.isNotEmpty` (`waiting_room_page.dart:261`) alors que `state.actionInProgress` existe déjà (`waiting_room_state.dart:42`). |
| **Formulaire soumis vide** | patient `/home-care/new` | **CORRECT.** Les deux CTA sont `aria-disabled=true` tant que le formulaire est invalide ; ils s'activent exactement quand le code le prescrit (acte coché → devis ; devis obtenu + adresse valide → confirmation). Aucun 500, aucun submit silencieux. |
| **Retour navigateur au milieu d'un flux** | secrétariat `/devis` (volet de détail) | Non concluant cette ronde : aucune ligne `DEV-` trouvée dans le laps du test. À rejouer. |
| **Permission navigateur refusée puis accordée** | patient `/home-care/new` | **CORRECT, et leçon de méthode** : sans géolocalisation, « Obtenir un devis » reste en `isLoading` et **aucune requête ne part** — ce qui se lit comme un bouton mort. Avec `permissions:['geolocation']` + `geolocation:{45.7578,4.8320}`, le flux complet passe. **Ne jamais conclure « mort » sur cet écran sans accorder la position.** |

### Nouveaux pièges de méthode (nº 24 et nº 25) — deux faux positifs évités de justesse cette ronde

- **nº 24 — coordonnées PÉRIMÉES après `goBack()`.** L'auditeur v1 réutilisait l'inventaire pris **avant** la première navigation ; après un `page.goBack()` la mise en page a bougé, et les clics suivants tombaient à côté. Symptôme trompeur : le rail secrétariat semblait mener aux **mauvaises routes** (« Encaissements » → `/bookable-slots`, « Messages » → `/appointment-motifs`, « Patients, 34 » → `/stock`) — c'eût été un P1 spectaculaire. **Rejoué avec un rechargement propre de la route avant CHAQUE clic : 15/15 destinations correctes.** L'auditeur v2 (`R46_audit2.js`) ré-inventorie et re-cherche le contrôle par (libellé, position) avant chaque activation, et recharge la route s'il ne le retrouve pas. Même cause pour la cloche sortie « MORT » sur 2 apps : elle ouvre en réalité un panneau parfaitement fonctionnel.
- **nº 25 — un `aria-disabled=true` légitime ressemble à un bouton mort.** Trois contrôles sortis MORT cette ronde étaient simplement désactivés à bon droit (les 2 CTA de `/home-care/new` sur formulaire vide). **Réflexe** : lire `aria-disabled` sur l'élément `role=button` **lui-même** — et non sur le `group` parent, dont le libellé concatène tout l'écran et dont le `dis` vaut toujours `null`. Corollaire : filtrer l'inventaire sur `role==='button' && w<380` avant de chercher un CTA par libellé.

### Second lot (19:05–20:05 UTC) — écrans jamais audités + mécaniques design-v2

| app | écran/route (viewport) | inventoriés | activés | OK | morts | cassés | notes | last_check |
|---|---|---|---|---|---|---|---|---|
| patient | `/prescriptions` (390) | 17 | 12 | **12** | 0 | 0 | 12/12, chaque ordonnance ouvre son détail. Statuts lisibles (`Signée`, `Transmise à une pharmacie`). | 2026-09-06T19:06:00Z |
| patient | `/pharmacy/orders` (390) | 17 | 13 | **13** | 0 | 0 | 13/13. Chaque commande ouvre son suivi (2 à 4 requêtes). Les deux officines sont distinguées (« Pharmacie du Rhône » / « Grande Pharmacie de la Part-Dieu ») et les statuts sont variés et corrects (Prête / Reçue / En préparation / Retirée). | 2026-09-06T19:25:00Z |
| patient | `/oubliettes` (390) | 2 | 1 | 1 | 0 | 0 | Écran jamais audité. `Retour` OK. **Contenu défaillant** : 7 cartes titrées par leur nom de fichier UUID → **#6639**. | 2026-09-06T19:33:00Z |
| patient | `/profile/referring-doctor` (390) | 2 | 1 | 1 | 0 | 0 | « Changer de médecin traitant » actif. | 2026-09-06T19:26:00Z |
| patient | `/profile/notifications` (390) | 17 | 10 | 6 | 4 | 0 | Les 3 canaux (`Notification`/`E-mail`/`SMS`) et les bascules actives émettent bien leur requête. Les 4 « MORT » sont des bascules **`aria-disabled=true` à bon droit** (« Toujours activé », « Bientôt disponible ») — faux positifs levés. **Vrai défaut trouvé ailleurs** : 8 bascules sur 10 sans nom accessible → **#6640**. | 2026-09-06T19:28:00Z |
| secretariat | `/appointment-motifs` (1280) | 27 | 23 | 19 | 3 | 1 | Écran jamais audité. Les 3 « MORT » et le « CASSÉ » sont tous des **faux positifs levés** : en-têtes de section repliables, entrée de rail de la page courante, et le 403 attendu sur `/cabinet/stats/activity`. | 2026-09-06T19:15:00Z |
| secretariat | `/liste-attente`, `/audit-log`, `/admin-membres` (1280) | ~22 + 25 | ~40 | ~34 | 6 | 0 | Écrans jamais audités. Rail complet fonctionnel. Les « MORT » sont des en-têtes de section et, sur `/admin-membres`, les onglets `Membres`/`Secrétariats` d'un écran **RBAC-refusé** au secrétariat (403 en série, cf. #6561 déjà traité). | 2026-09-06T19:20:00Z |
| secretariat | rail, groupe « Réglages du cabinet » (1280) | 4 | 4 | **4** | 0 | 0 | Re-vérification ciblée après une alerte : `Statistiques`, `Créneaux ouverts`, `Motifs de RDV` et `Stock` naviguent tous correctement dès qu'on laisse 3 s à l'animation de dépliage (cf. piège nº 26). | 2026-09-06T19:50:00Z |
| praticien | `/consultation?id=` (1280x834) | 61 | ~8 (mécanique ciblée) | 8 | 0 | 0 | Parcours métier complet : sélection de dent (surlignage vert), clic sur acte favori → dialogue pré-rempli au tarif CCAM, « Ajouter » → `POST …/acts` → **l'encart « Actes de la séance » se remplit** (0 → 1). Défaut de mise en page trouvé : **10 dents sur 32 hors cadre** → **#6642**. | 2026-09-06T19:32:00Z |
| praticien + secretariat | palette ⌘K | 2 | 2 | **2** | 0 | 0 | ⌘K ouvre, la saisie filtre et type les résultats, Échap referme proprement. 1 écart déjà consigné (1er résultat ≠ « Demander à Nubia »). | 2026-09-06T19:45:00Z |
| **TOTAL RONDE 2026-09-06 (2 lots, 24 écrans, 5 apps)** | **24 écrans** | **~440** | **~215** | **~200** | **2 confirmés** | **0 confirmé** | **13 verdicts MORT/CASSÉ sur 15 se sont révélés être des faux positifs après vérification manuelle** (voir pièges nº 24, 25, 26). | 2026-09-06T20:05:00Z |

### Cas adversariaux — second lot

| cas | écran | résultat |
|---|---|---|
| **Scan d'un jeton de retrait sur la MAUVAISE commande** | pharmacie, `POST /pharmacy/orders/pickup-scan` | **CORRECT, et l'invariant tient.** → **409 `pickup_order_mismatch`**, et **les deux commandes restent `ready`** : aucune écriture n'a lieu avant la comparaison (garantie de #6349, vérifiée des deux côtés). |
| **Double scan du même jeton de retrait** | pharmacie | **CORRECT.** 1er scan → 200 + le patient voit `picked_up`/`picked_up_at` ; 2e scan → **409 `invalid_status`** (usage unique). |
| **Rejeu d'une `Idempotency-Key` avec un corps différent** | patient, `POST /payments/intent` | **CORRECT.** Même clé + même corps → **même `payment_id` et même `client_secret`** ; même clé + corps différent → **409 `idempotency_key_conflict`**. |
| **Permission navigateur refusée** | patient `/home-care/new` | Voir piège de méthode : sans géolocalisation le CTA reste en `isLoading` sans émettre de requête — indiscernable d'un bouton mort. |

### Nouveau piège de méthode nº 26 — l'animation d'un groupe repliable

**Le faux positif le plus coûteux de la ronde**, à deux doigts d'être filé en P1. L'entrée de rail
« Stock » du secrétariat est sortie **MORT sur trois exécutions indépendantes** (clic → URL
inchangée, 0 requête, 0 erreur), ce qui aurait signifié que `/stock` — qui fonctionne parfaitement
en URL directe — n'est atteignable par aucune navigation.

**Cause réelle** : le groupe « Réglages du cabinet » est **repliable et animé** (#5139). Le
harnais dépliait le groupe, attendait 2,2 s, relisait les Semantics puis cliquait — mais
l'animation n'était pas finie et la rangée n'était plus à la position lue. Avec **3 s**, les
4 entrées du groupe naviguent correctement.

**Réflexe** : après avoir déplié/replié un conteneur animé, attendre ≥ 3 s **et** relire les
Semantics juste avant le clic. Plus généralement, un verdict MORT sur un contrôle qui vient
d'apparaître à la suite d'une autre interaction doit être rejoué à froid avant d'être écrit.
S'ajoute aux pièges nº 24 (coordonnées périmées après `goBack`) et nº 25 (`aria-disabled` légitime).

### Ronde 2026-09-07 (00:00–01:28 UTC) — 5 apps, écrans jamais audités + mécaniques ciblées

> **Contexte indispensable** : les 5 fronts sont figés au commit `0744df0` (18:43 UTC) et l'API à
> un binaire antérieur — le pipeline de déploiement est **bloqué** (#6649). Aucun symptôme
> imputable aux 8 correctifs mergés après 18:55 n'est compté ici comme régression.

| app | écran/route (viewport) | inventoriés | activés | OK | morts | cassés | notes | last_check |
|---|---|---|---|---|---|---|---|---|
| patient | `/coverage-setup` (390) | 9 | 8 | 5 | 3 | 0 | **Écran jamais audité.** Les 3 « MORT » sont le `radiogroup` conteneur, le radio **déjà sélectionné** (« Régime général » — pas de repeinture) et un `textbox` (limite de harnais, la signature Semantics ne porte pas la valeur). `AME` et `CSS` repeignent correctement. | 2026-09-07T00:18:00Z |
| patient | `/rdv/:id/prepare` (390) | 3 | 2 | 1 | 1 | 0 | **Écran jamais audité.** Rend correctement la préparation (`GET /appointments/:id/preparation`) : « Dr Claire Lefèvre / 12 rue de la République / Parking disponible / Accès PMR / Rappel Lun 7 sep à 10:00 / Carte Vitale ». `Retour` OK, la case « Carte Vitale » est le 1 « MORT » (bascule sans changement de signature Semantics). | 2026-09-07T00:19:00Z |
| patient | `/pharmacy/search` (390) | 2 | 2 | **2** | 0 | 0 | **Écran jamais audité.** 2/2. | 2026-09-07T00:19:00Z |
| patient | `/rdv/:id/modifier` (390) | 51 | 42 | 1 | 41 | 0 | **Écran jamais audité — et le plus gros piège de la ronde (nº 27, ci-dessous).** Les 41 « MORT » sont **tous expliqués** : 5 créneaux `aria-disabled=true` **à bon droit** (préavis 24 h, `modify_rdv_bloc.dart::_withReschedulePreavis`) et 36 sélections de créneau que l'auditeur ne sait pas voir (la sélection ne change **que des pixels**). **Rejoué à la main avec comparaison de captures** : cliquer un créneau à J+1 modifie l'image **et fait apparaître « Confirmer la modification »**. Mécanique conforme. | 2026-09-07T00:19:00Z |
| patient | `/profile/dependents` + feuille « Ajouter un proche » (390) | 25 + 9 | 34 | 33 | 1 | 0 | **43 comptes gérés, liste entièrement défilable** (15 × molette 700 px jusqu'au fond, vérifié par égalité de captures consécutives). Feuille d'ajout : `Prénom`, `Nom`, `Enfant`/`Conjoint`/`Autre`, `Date de naissance`, `Ajouter`. Le seul « MORT » est le CTA `aria-disabled=true` **à bon droit** sur formulaire vide. **Défaut trouvé** : le FAB masque la mention légale en bas de liste → **#6652**. | 2026-09-07T00:40:00Z |
| praticien | `/agenda` (1280) | 30 | 24 | 21 | 2 | **1 confirmé** | Rail 13/13 correct. Le « CASSÉ » est **réel et central** : « Démarrer » → `409 too_early`. Rejoué en ciblé : **3 boutons « Démarrer » à l'écran, 3 échecs** (2 × 409, 1 × 403 sur le RDV d'un confrère) → **#6651 (P1)**. Les 2 « MORT » sont l'entrée de rail de la page courante et « Confirmer » (hors viewport après défilement, non concluant). | 2026-09-07T00:32:00Z |
| praticien | `/devis` (1280) | 27 | 21 | 20 | 1 | 0 | **Écran jamais audité.** Le « MORT » est l'entrée de rail de la page courante. | 2026-09-07T00:22:00Z |
| praticien | `/messages` (1280) | 27 | 23 | **22** | 1 | 0 | **Écran jamais audité.** Idem, rail de la page courante. | 2026-09-07T00:25:00Z |
| praticien | `/waiting-room` (**1440**, file de 3 patients réellement mise en place) | 20 (vide) → 29 (peuplé) | — (comparaison design-v2) | — | — | — | Re-shooté après 3 `POST /cabinet/appointments/:id/checkin` pour rendre la comparaison utile. Défauts : « Retard sur le planning −426 min » en couleur d'alerte → **#6655** ; héros/CTA/file en « MD » → **preuve (d) de #6649**, pas une récidive de #6611. | 2026-09-07T00:56:00Z |
| secretariat | `/devis/:id` (1280) | 23 | 19 | 18 | 1 | 0 | **Écran jamais audité** (volet de détail atteint par URL directe). Le « MORT » est l'en-tête de section « Facturation » du rail. | 2026-09-07T00:20:00Z |
| secretariat | `/appointments` (Prendre un RDV, 1280) | 27 | 23 | 20 | 3 | 0 | **Écran jamais audité.** Les 3 « MORT » : en-tête de section « Patients », entrée de rail de la page courante, et la facette « Tous » **déjà sélectionnée**. | 2026-09-07T00:22:00Z |
| secretariat | `/onboard` (1280) | 28 | 24 | 22 | 2 | 0 | **Écran jamais audité.** `/onboard` est dans `authRoutes` (`app_router.dart:91`) : un compte connecté est **redirigé vers `/`** par `buildAuthGuard` — comportement correct, pas un écran mort. Les 2 « MORT » sont l'en-tête « Ma journée » et l'entrée « Tableau de bord » de la page courante. Les 6 CTA du tableau de bord (`Ouvrir l'agenda`, `Appeler` ×2, `Relancer`, `Ouvrir` ×2) émettent tous leur requête. | 2026-09-07T00:24:00Z |
| pharmacie | `/notification-preferences` (1280) | 13 | 9 | **9** | 0 | 0 | **Écran jamais audité.** 9/9 : les 9 bascules (Messagerie / Devis / Demandes de stock × app/e-mail/push) émettent chacune leur `PATCH`. | 2026-09-07T00:21:00Z |
| pharmacie | `/devis` (1280) | 42 | 22 | 20 | 2 | 0 | Les 2 « MORT » : entrée de rail de la page courante et facette « Tous (81) » **déjà sélectionnée**. | 2026-09-07T00:23:00Z |
| pharmacie | `/stock` (1280) | 18 | 13 | 11 | 2 | 0 | Idem : rail de la page courante + facette « À répondre (1) » déjà active. | 2026-09-07T00:24:00Z |
| pharmacie | `/` et `/orders/:id` et `/messages` (1280 et **1440**) | 35 + 38 + 17 | — (comparaison design-v2) | — | — | — | Inventaires pris pour la comparaison aux maquettes. Défaut : seuil de l'alerte « À traiter » tronqué **aux deux viewports** → **#6654**. `/orders/:id` : les **lignes de l'ordonnance sont bien visibles** (« Ordonnance — 1 ligne », posologie, badge « Substituable ») et le rail + la file du jour sont conservés (correctif #6627 confirmé en live). | 2026-09-07T00:41:00Z |
| infirmiere | `/` (3 onglets) et `/notification-preferences` (390) | 8 + 5 | 9 | **8** | 1 | 0 | **5ᵉ app parcourue.** Le seul « MORT » est l'onglet « Disponibilité » **déjà actif**. Les 2 bascules de préférences émettent leur requête. | 2026-09-07T00:26:00Z |
| **TOTAL RONDE 2026-09-07** | **17 écrans, 5 apps** | **313** | **241** | **180** | **60 → 0 confirmés après triage** | **1 confirmé (#6651)** | Les 60 verdicts « MORT » sont **tous** expliqués : 36 sélections de créneau invisibles aux Semantics (piège nº 27), 8 `aria-disabled` légitimes, 11 entrées de rail de la page courante / en-têtes de section, 5 facettes déjà sélectionnées. | 2026-09-07T01:00:00Z |

### Cas adversariaux joués cette ronde

| cas | écran | résultat |
|---|---|---|
| **Formulaire soumis à vide** | patient, feuille « Ajouter un proche » | **CORRECT.** Le CTA « Ajouter » est `aria-disabled=true` tant que prénom/nom/relation ne sont pas renseignés. Aucun envoi silencieux, aucun 500. |
| **Texte très long (245 caractères) dans les champs libres** | patient, feuille « Ajouter un proche » | **CORRECT côté mise en page** : après saisie de 245 caractères dans `Prénom`, **aucun élément hors cadre** (`x<0` ou `x+w>390`), 9 contrôles avant comme après. **Mais l'API l'accepte** (`first_name` de 300 caractères → 201) → **#6653**. |
| **Retour navigateur au milieu d'un flux** | patient, `/profile/dependents` → feuille ouverte → `goBack()` | **CORRECT.** Retour propre à l'accueil, écran entièrement rendu (héros « Bonjour Marc Dubois », « À faire 3 », barre d'onglets), 0 erreur console. *Piège levé* : l'arbre Semantics ressort **vide** après `goBack()` parce que Flutter désactive `semanticsEnabled` à la navigation — ne jamais conclure « écran blanc » sans capture. |
| **Double clic rapide sur une action métier** | praticien `/agenda`, bouton « Démarrer » | **Pas de double effet** : les deux clics produisent chacun un `POST …/start` refusé (`409 too_early`), l'état serveur des 3 RDV est inchangé après. Le défaut est ailleurs (affordance) → #6651. |
| **Transition hors ordre / rejeu, sur 5 machines à états** | visite à domicile, commande pharmacie, demande de stock, devis cabinet, devis d'officine | **CORRECT partout.** 14 transitions interdites testées → **14 × 409** (`invalid_status`), 0 acceptée à tort. Aucun cul-de-sac : chaque ressource conserve une sortie (`cancel` patient possible jusqu'à `arrived` inclus sur une visite ; `complete` verrouille la consultation et l'ajout d'acte postérieur est refusé). |
| **Jeton forgé / altéré / `alg:none`** | API, `/v1/account` | **CORRECT.** 401 dans les 4 variantes (signature altérée, `alg:none`, header sans `Bearer`, header absent). |

### Nouveau piège de méthode nº 27 — une sélection qui ne change que des pixels

**Le plus gros faux positif de la ronde** : `/rdv/:id/modifier` est sorti **41 MORT sur 42
activés**, ce qui aurait signifié qu'aucun créneau n'est sélectionnable et que la
reprogrammation patient est morte — un P1 spectaculaire.

**Cause réelle** : l'auditeur juge « MORT » quand il n'observe ni navigation, ni requête, ni
changement de la signature Semantics (`label + aria-checked`). Or un `SlotChip` sélectionné ne
navigue pas, n'émet **aucune requête** (la sélection est locale au bloc) et **ne porte pas
`aria-checked`** — seule sa couleur change. Le seul créneau sorti « OK » est celui qui a fait
apparaître un contrôle **nouveau** (« Confirmer la modification »), donc modifié la signature.

**Réflexe** : sur un écran de sélection (créneaux, dents, facettes, cases à cocher peintes),
comparer **les captures d'écran avant/après le clic**, pas la signature Semantics. Vérification
faite ici : `Buffer.compare(avant, après) === 0` sur les 2 créneaux `aria-disabled` (vraiment
inertes, à bon droit) et **`!== 0`** sur le créneau à J+1, qui fait de surcroît apparaître le CTA
de confirmation. S'ajoute aux pièges nº 24 (coordonnées périmées), nº 25 (`aria-disabled`
légitime) et nº 26 (animation d'un groupe repliable).

**Corollaire nº 27 bis** : un `SnackBar` Flutter est bien dans le DOM mais **sans `role` ni
`aria-label`** (`<flt-semantics role=null aria=null txt="Il est trop tôt pour démarrer cette
séance…">`). Un auditeur qui ne lit que `[role]`/`[aria-label]` conclut « échec silencieux »
alors que l'utilisateur voit un message parfaitement clair. Toujours redescendre au DOM brut
`flt-semantics` **et** à la capture avant de rapporter une absence de retour visuel.

### Second lot de la même ronde (00:50–01:15 UTC) — 12 écrans de plus, 5 apps

| app | écran/route (viewport) | inventoriés | activés | OK | morts | cassés | notes | last_check |
|---|---|---|---|---|---|---|---|---|
| praticien | `/patients` (1280) | 35 | 27 | 15 | 1 | **11 → 0 confirmés** | **Écran jamais audité.** Les 11 « CASSÉ » sont **tous des 403 légitimes** : la garde « relation de soin » (§14, #4974/#6210) sur les blocs cliniques d'un patient que ce praticien n'a jamais suivi. **Vérifié écran à écran** : `/patients/15a67def` (sans relation) rend « Vous n'avez pas encore suivi ce patient — l'historique clinique n'est pas accessible. » via `PatientAccessDeniedNotice`, et sert quand même identité, solde, journal, RDV, étiquettes et documents ; `/patients/d0000000` (avec relation) rend le dossier complet, **0 requête en erreur**. En API : `GET /cabinet/patients/:id` → **200 pour les 44 patients**, seuls les sous-endpoints cliniques renvoient 403 hors relation de soin. Le « MORT » est le rail de la page courante. | 2026-09-07T01:20:00Z |
| praticien | `/ordonnances` (1280) | 19 | 16 | 15 | 1 | 0 | **Écran jamais audité.** « Choisir un patient » émet sa requête. Le « MORT » est le rail de la page courante. | 2026-09-07T01:12:00Z |
| praticien | `/lab-work-orders` (1280) | 30 | 19 | 16-17 | 2 | **1 confirmé** | **Écran jamais audité — et il donne le 2e P1 de la ronde.** « Programmer la pose » émet `PATCH /cabinet/lab-work-orders/:id {"status":"fitted"}` → **403** (relation de soin) et **l'écran passe de 30 à 21 contrôles**, la liste des 26 bons disparaît au profit d'un `NubiaErrorWidget` plein écran + « Réessayer » → **#6657 (P1)**. Sur les 3 bons non finaux, **aucune transition n'aboutit** (1 × 403, 2 × 409 `returned`→`sent`). Les 2 « MORT » sont le rail de la page courante et « Nouveau bon » (qui affiche une snackbar « bientôt disponible », `lab_work_orders_page.dart:140-146` — volontaire). | 2026-09-07T01:10:00Z |
| praticien | `/stock-inventory` (1280) | 42 | 24 | 23 | 1 | 0 | **Écran jamais audité.** 23/24. Le « MORT » est le rail de la page courante. | 2026-09-07T01:14:00Z |
| secretariat | `/bookable-slots` (1280) | 30 | 26 | 21 | 4 | 1 | **Écran jamais audité.** Les 4 « MORT » sont le groupe repliable « Réglages du cabinet » et 3 de ses entrées (**piège nº 26**, animation) ; le « CASSÉ » est le 403 attendu sur `/cabinet/stats/activity` (#4592/#6369). « Créneaux ouverts » navigue bien vers `/bookable-slots`. | 2026-09-07T01:17:00Z |
| secretariat | `/cabinet-stats` (1280) | 27 | 23 | 18 | 4 | 1 | **Écran jamais audité.** Mêmes 4 « MORT » (groupe repliable animé) et même 403 bénin. | 2026-09-07T01:19:00Z |
| patient | `/treatment-plans` (390) | 10 | 7 | **7** | 0 | 0 | 7/7. Chaque plan ouvre son détail (1 à 3 requêtes) ; les libellés portent l'étape et le montant (« Étape 1 sur 2 · Phase 1 · 50 € », « À accepter · Reste à votre charge estimé »). | 2026-09-07T01:05:00Z |
| patient | `/implant-passport` (390) | 6 | 4 | **4** | 0 | 0 | 4/4. Chaque implant déplie sa fiche (dent FDI, libellé anatomique, marque, date de pose). | 2026-09-07T01:06:00Z |
| patient | `/oubliettes` (390) | 2 | 1 | 1 | 0 | 0 | `Retour` OK. Le défaut de titre reste ouvert (**#6639**, correctif non déployé — cf. #6649). | 2026-09-07T01:12:00Z |
| patient | `/documents` (390) | 41 | 22 | 14 | **8 → 0 confirmés** | 0 | Les 8 « MORT » sont des facettes de catégorie **hors cadre** : au repos elles sont posées à x = 408, 501, 594, 689, 843, 998 et 1117 dans un viewport de **390** — l'auditeur cliquait donc à des coordonnées invisibles. La rangée **défile horizontalement** (molette : x passe de 16…1117 à −891…210, pixels modifiés), exactement comme celle de `/appointments`. Les 3 facettes atteignables au repos (`Tous 290`, `Facture 41`, `Ordonnance 199`) répondent, et `Tous 290` est `aria-checked=true` **à bon droit** (déjà sélectionnée). **Aucun contrôle mort.** | 2026-09-07T01:16:00Z |
| patient | `/appointments` (Réservation, 390) | 32 | — (mécanique design-v2) | — | — | — | Rangée de facettes **défilante horizontalement** : « Généraliste » et « Dentiste » sont hors cadre au repos (x=366 et x=490 pour un viewport de 390) mais **la molette et le glisser les ramènent** (x=157 et x=281 après défilement) et « Dentiste » s'active alors correctement (`aria-checked` false→true + `GET /search/providers?q=dentiste`). **Faux positif évité.** | 2026-09-07T01:08:00Z |
| **TOTAL 2e LOT** | **12 écrans** | **291** | **204** | **166** | **24** | **14 → 1 confirmé (#6657)** | 13 des 14 « CASSÉ » sont les 403 « relation de soin » du dossier patient, correctement rendus par `PatientAccessDeniedNotice`. | 2026-09-07T01:15:00Z |
| **TOTAL RONDE 2026-09-07 (2 lots)** | **29 écrans, 5 apps** | **604** | **445** | **346** | **84 → 0 confirmés** | **2 confirmés (#6651, #6657)** | | 2026-09-07T01:15:00Z |

### Troisième lot (01:15–01:28 UTC) — derniers écrans jamais audités

| app | écran/route (viewport) | inventoriés | activés | OK | morts | cassés | notes | last_check |
|---|---|---|---|---|---|---|---|---|
| patient | `/financial` (390) | 11 | 8 | **8** | 0 | 0 | **Écran jamais audité.** 8/8. | 2026-09-07T01:20:00Z |
| patient | `/pharmacy/quotes` (390) | 8 | 1 | **1** | 0 | 0 | **Écran jamais audité.** 1/1 activable (les 7 autres nœuds sont des conteneurs/textes hors périmètre d'activation). | 2026-09-07T01:21:00Z |

### Cas adversariaux — troisième lot

| cas | écran / flux | résultat |
|---|---|---|
| **Scan d'un jeton de retrait sur la MAUVAISE commande** | pharmacie, `POST /pharmacy/orders/pickup-scan` | **CORRECT, invariant #6349 vérifié des deux côtés.** → **409 `pickup_order_mismatch`** (avec la commande réellement visée par le jeton dans le corps de réponse, pour que le pharmacien la reconnaisse) et **les deux commandes restent `ready`** : aucune écriture avant la comparaison. |
| **Jeton de retrait inventé (64 caractères)** | pharmacie | **404 `not_found`** — pas de fuite sur l'existence de la commande. |
| **Code court au lieu du jeton complet** | pharmacie | **200** — c'est la porte de secours « QR illisible ou caméra indisponible ? Saisir le code de retrait » prescrite par `Pharmacie Delivrance v2.html` : `short_code` (`CQTT-JR5M`) est accepté au même titre que le jeton de 64 caractères. **Mécanique design-v2 vérifiée.** |
| **Rejeu du même jeton après retrait** | pharmacie | **409 `invalid_status`** (usage unique). Le patient voit `picked_up` + `picked_up_at` et reçoit `order_status_changed{status:"picked_up"}`. |
| **Scan par un rôle non-pharmacie** | praticien et patient | **403** pour les deux. |
| **Actions cabinet sur le RDV d'un AUTRE cabinet** | secrétariat + praticien du Cabinet Lyon sur 2 RDV pris chez Dr Amélie Dubois | **CORRECT, 8 refus sur 8** : `confirm`, `start`, `checkin`, `no-show` → **404** (anti-énumération, pas 403) sur les deux RDV ; l'agenda du Cabinet Lyon (18 RDV ce jour) ne les contient pas ; le patient, lui, les lit normalement (200). |
| **Demande de visite créée alors que l'infirmière est HORS LIGNE** | patient → infirmière | **CORRECT.** `GET /search/nurses?online_only=true` → 0 ; la demande naît `status:"requested"` avec `nurse_id:null` (et non `offered` comme lorsqu'elle est en ligne) ; `GET /nurse/offers` reste vide. **Pas de cul-de-sac** : `cancel` patient → 200. Disponibilité restaurée à `is_online:true` en fin de ronde. |

---

## Ronde 2026-09-07 (06:00–08:30 UTC)

Chromium headless (`/ms-playwright/chromium-1155`), locale `fr-FR`, fuseau `Europe/Paris`.
Inventaire = arbre Semantics du DOM après activation de l'accessibilité. **Note d'outillage :**
sur cette version de Flutter web les champs de saisie sont des `<input aria-label>` **hors**
`flt-semantics`, et les boutons sont des `flt-semantics[role=button]` **sans** `aria-label`
(libellé porté par `textContent`) — un sélecteur qui ne vise que `flt-semantics[aria-label]`
ne voit aucun champ et fait échouer le login. Sélecteur utilisé : `flt-semantics[role],
flt-semantics[flt-tappable], input, textarea, [role=…]`.

| app | écran / route | vp | inventoriés | activés | OK | morts | cassés | last_check |
|---|---|---|---|---|---|---|---|---|
| praticien | `/patients/:id/treatment-plans` | 1440×900 | 33 | 33 | 30 | 3 | 0 | 2026-09-07T06:55:00Z |
| praticien | `/waiting-room` | 1280×800 | 21 | 21 | 20 | 0 | 1 | 2026-09-07T06:51:00Z |
| praticien | `/lab-work-orders` | 1440×900 | 20 | 3 (ciblés) | 2 | 0 | 1 | 2026-09-07T07:10:00Z |
| secretariat | `/salle-attente` | 1280×800 | 25 | 25 | 23 | 0 | 2 | 2026-09-07T06:55:00Z |
| pharmacie | `/` (commandes) | 1280×800 | 23 | 19 | 18 | 1 | 0 | 2026-09-07T07:20:00Z |
| pharmacie | `/stock` | 1280×800 | 8 | 7 | 6 | 1 | 0 | 2026-09-07T07:20:00Z |
| pharmacie | `/devis` | 1280×800 | 27 | 22 | 19 | 2 | 1 | 2026-09-07T08:05:00Z |
| pharmacie | `/messages` | 1280×800 | 15 | 14 | 14 | 0 | 0 | 2026-09-07T07:25:00Z |
| patient | `/profile/dependents` | 390×844 | 22 | 17 | 17 | 0 | 0 | 2026-09-07T07:20:00Z |
| patient | `/profile` | 390×844 | 13 | 8 | 8 | 0 | 0 | 2026-09-07T07:55:00Z |
| patient | `/messaging` | 390×844 | 8 | 8 | 8 | 0 | 0 | 2026-09-07T07:30:00Z |
| infirmiere | `/` — onglets Disponibilité / Offres / Ma visite | 390×844 | 9 | 9 | 9 | 0 | 0 | 2026-09-07T07:20:00Z |
| **TOTAL** | 12 écrans | — | **224** | **186** | **174** | **10 bruts → 1 réel** | **5 bruts → 0 réel** | — |

### Les 10 « morts » et 5 « cassés » bruts, un par un — 1 seul défaut réel

Conformément à la leçon de méthode ci-dessus, **chaque** verdict négatif a été rejoué à la main.

| contrôle | verdict brut | après vérification |
|---|---|---|
| praticien `/patients/:id/treatment-plans` — « Générer le devis de la phase 1 » | MORT | **Défaut réel, mais pas « mort »** : le clic émet bien `GET /v1/cabinet/quotes` (le premier passage l'avait raté faute de `mouse.move` préalable). Le vrai défaut est la **cible** : liste de devis de tout le cabinet au lieu du devis de la phase → **#6672 (P1)**. |
| praticien `/patients/:id/treatment-plans` — 2 cartes de plan + « Ajouter une phase » | MORT ×3 | **Artefact d'outillage** : rects à `y=942`, `y=1055` et `y=1079`, **hors** du viewport 900 — le clic tombait à côté. Non reproductible après défilement. |
| praticien `/waiting-room` — « Messagerie interne » | CASSÉ (500) | **Bruit d'infra hors produit** : `GET /favicon.png → 500 nginx`, aucune requête `/v1/` en échec. La navigation vers `/team-messages` aboutit. |
| secretariat `/salle-attente` — « Devis, 8 » et « Équipe » | CASSÉ ×2 (403 `/cabinet/stats/activity`) | **Faux positifs.** Le rail de navigation est un arbre à sections dépliables : cliquer un en-tête décale les items suivants, donc les coordonnées mémorisées visaient un autre nœud. Re-testé un par un : « Devis » → `/devis` (200, `cabinet/quotes`), « Équipe » → `/team-messages`, ainsi que Agenda, Salle d'attente, Demandes de créneau, Fiches patients, Prendre un RDV, Encaissements — **9/9 corrects**. *(À noter au passage : la route `/cabinet-stats` existe dans `app_router.dart:260` mais n'a **aucune entrée de navigation**, et `GET /v1/cabinet/stats/activity` répond 403 au secrétariat contre 200 au praticien — écran inatteignable, non filé.)* |
| pharmacie `/` — 7ᵉ « Délivrer » | MORT | **Artefact de bord** : rect `855,769 89×31`, centre à `y=784` dans un viewport de 800 — clic sur le bord. Les 6 autres « Délivrer » naviguent correctement. |
| pharmacie `/stock` — « Réessayer » | MORT | **Non reproductible** : rechargé deux fois sur session fraîche, l'écran rend normalement ses 13 contrôles (4 facettes chiffrées + recherche), `GET /v1/pharmacy/stock-requests` → 200. L'état d'erreur venait de la session expirée du parcours long. |
| pharmacie `/devis` — « Préparer » ×1 puis « Réémettre »/« Relancer » | CASSÉ + MORT ×2 | **Symptôme de #6682, pas un défaut de l'écran.** Sur session fraîche, les 5 premiers CTA (`Préparer` ×3, `Réémettre`, `Préparer`) naviguent tous vers `/orders/:id`. C'est au 6ᵉ, ~15 min après le login, que la séquence 401 → refresh → **403** apparaît et que les boutons suivants deviennent inertes. |
| patient `/profile` — « Modifier la photo de profil » | MORT | **Faux positif.** Le contrôle ouvre un sélecteur de fichier natif, invisible pour le détecteur (ni navigation, ni requête, ni repaint). Vérifié avec un écouteur `filechooser` : **`FILECHOOSER OPENED`** aux deux points de clic testés. |

**Bilan : 1 défaut réel sur 15 verdicts négatifs bruts** (#6672), 2 renvoyés à #6682, 12 artefacts.

### Cas adversariaux — quatrième lot

| cas | écran / flux | résultat |
|---|---|---|
| **Double-clic rapide sur un CTA d'action** | praticien `/lab-work-orders`, « Programmer la pose » | **CORRECT** — un seul `PATCH /v1/cabinet/lab-work-orders/:id` émis pour deux clics. |
| **Échec d'action et intégrité de la liste** | praticien `/lab-work-orders`, CTA sur un bon sans relation de soin | **CORRECT, #6657 tenu** — le 403 n'efface plus rien : 20 contrôles avant, 20 après, les 2 cartes en place, snackbar « Impossible de mettre à jour le statut. ». *(Le 403 lui-même est un défaut à part : #6673.)* |
| **Retour arrière navigateur au milieu d'un flux** | praticien `/patients/:id/treatment-plans` → CTA → retour | **CORRECT sur l'état** : retour à l'écran des plans avec ses 33 contrôles et la colonne de couverture. *(L'URL n'avait pas suivi l'écran à l'aller — noté dans #6672.)* |
| **Coupure réseau pendant une action métier** | praticien `/waiting-room`, `route.abort()` sur `**/v1/**` puis clic « Appeler Marc Dubois » | **CORRECT** — snackbar « Impossible d'appeler le patient suivant. » à **t+1,5 s**, liste conservée, bouton toujours actif, ni spinner infini ni écran blanc. *Piège de mesure : une capture à t+8 s rate la snackbar (durée ~4 s) et fait conclure à tort au silence.* |
| **Coupure réseau pendant un rechargement** | praticien `/waiting-room` | **CORRECT** — état d'erreur avec bouton « Réessayer ». |
| **Soumission d'un formulaire à vide** | patient `/profile/dependents`, feuille « Ajouter un proche » | **CORRECT** — « Ajouter » **désactivé** tant que les champs requis sont vides ; aucune requête émise. Désactivation légitime, vérifiée contre le code. |
| **Texte très long (220 caractères) dans un champ libre** | patient `/profile/dependents`, champ « Prénom » | **CORRECT au rendu** — défilement horizontal du champ, aucun débordement ni chevauchement, la feuille garde sa mise en page. *Réserve : aucun `maxLength` côté client alors que l'API plafonne à 100 (#6653) — l'utilisateur ne l'apprend qu'au 422.* |
| **Session laissée inactive au-delà des 900 s du JWT** | infirmière (16 min) puis pharmacie (16 min), et parcours continu pharmacie | **DÉFAUT — #6682 (P0).** Infirmière : 401 → `auth/refresh` → **403** sur `nurse/profile`, `nurse/offers`, `nurse/visits` ; écran sans donnée, sans message, et affichant « Vous êtes hors ligne » alors que le serveur répond `is_online = true`. Pharmacie : se rétablit sur un **rechargement de page** (0 échec) mais tombe de la même façon **en cours de navigation**. Praticien : contrôle **CORRECT**, le refresh conserve `cabinet_id`/`role`/`secretariat_id`. |
| **Champ inconnu dans un corps de POST** | praticien `POST /v1/cabinet/prescriptions`, patient `POST /v1/account/dependents` | **DÉFAUT — #6677 (P2).** `non_renewable`/`non_substitution` (au lieu de `non_renouvelable`/`non_substitution_reason`) → **201**, mentions légales perdues sans signal ; `is_admin:true` sur un proche → **201**. 93 corps `*Body*` sur 188 structs `Deserialize` sont sans `deny_unknown_fields`. |
| **Acte de soin répété 200 fois** | patient `POST /v1/account/visit-requests` | **DÉFAUT — #6671 (P1).** Ni dédoublonnage ni plafond : `estimated_price_cents = 502 500` (5 025,00 €) figé sur la demande et poussé à l'infirmière. |

### Ronde 2026-09-07 (12:00–15:30 UTC) — 5/5 apps, 2 viewports

| app | écran/route | inventoriés | activés | OK | morts | cassés | last_check |
|---|---|---|---|---|---|---|---|
| patient | `/` (Accueil, 390×844) | 22 | 15 | 13 | 2 (`Itinéraire`, `Accueil`) | 0 | 2026-09-07T15:30:00Z — `Accueil` = onglet déjà actif (no-op légitime). `Itinéraire` non reconfirmé cette ronde. |
| patient | `/mes-rdv` (390×844) | 5 | 4 | 3 | 1 (`À venir (20)`) | 0 | 2026-09-07T15:30:00Z — Onglet déjà sélectionné → no-op légitime. |
| patient | `/messaging` (390×844) | 9 | 8 | 8 | 0 | 0 | 2026-09-07T15:30:00Z — Les 9 contrôles sont les lignes de conversation. **Aucune barre d'onglets, aucun retour → #6694.** |
| patient | `/documents` (Coffre-fort, 390×844) | 41 | 22 | 14 | 0 (après vérification) | 0 | 2026-09-07T15:30:00Z — **Les 8 « MORT » du 1er passage étaient un artefact d'outil** : les facettes vivent dans une rangée à défilement horizontal, `x` allant jusqu'à 1117 px pour un viewport de 390 → clics hors écran. Rejouées en scrollant la rangée : **les 10 facettes filtrent réellement** (`Tous`→13, `Radio`→7, `CBCT`→2, `Photo`→8, `Compte-rendu`→5, `Consentement`→4, `Carte mutuelle`→12 lignes). Auditeur corrigé (`R48_audit.js`). |
| patient | `/prescriptions` (390×844) | 17 | 12 | 12 | 0 | 0 | 2026-09-07T15:30:00Z — Les 12 ordonnances ouvrent leur détail (1 requête chacune). |
| patient | `/financial` (390×844) | 11 | 8 | 8 | 0 | 0 | 2026-09-07T15:30:00Z — 6 devis ouvrent leur détail. |
| patient | `/notifications` (390×844) | 20 | 15 | 14 | 1 (`Toutes 1123`) | 0 | 2026-09-07T15:30:00Z — Facette déjà active → no-op légitime. |
| patient | `/profile` (390×844) | 17 | 8 | 7 | 0 (après vérification) | 0 | 2026-09-07T15:30:00Z — `Modifier la photo de profil` classé MORT à tort : le clic **ouvre bien le sélecteur de fichier** (événement `filechooser` capté sur 2 points du rect). Un file picker n'émet ni requête ni repeinture → angle mort de l'auditeur, consigné. |
| patient | `/profile/dependents` (390×844) | 24 | 17 | 17 | 0 | 0 | 2026-09-07T15:30:00Z |
| patient | `/treatment-plans` (390×844) | 10 | 7 | 7 | 0 | 0 | 2026-09-07T15:30:00Z |
| patient | `/home-care` (390×844) | 18 | 14 | 14 | 0 | 0 | 2026-09-07T15:30:00Z |
| praticien | `/` (Tableau de bord, 1280×800) | 23 | 17 | 16 | 1 (`Tableau de bord`) | 0 | 2026-09-07T15:30:00Z — Onglet actif. `Démarrer la consultation` et `Ouvrir le dossier` naviguent correctement. |
| praticien | `/waiting-room` (1280×800) | 25 | 20 | 19 | 1 (`Salle d'attente`) | 0 | 2026-09-07T15:30:00Z — Onglet actif. **Les 3 `Appeler` émettent bien leur requête** (2 requêtes chacun). |
| praticien | `/agenda` (1280×800) | 27 | 21 | 20 | 1 (`Agenda`) | 0 | 2026-09-07T15:30:00Z — Onglet actif. |
| praticien | `/patients` (1280×800) | 35 | 27 | 15 | 1 (`Patients`) | 11 (403) | 2026-09-07T15:30:00Z — **Les 11 « CASSÉ » sont légitimes** : garde §14 « relation de soin ». Ouvrir un patient jamais suivi → 403 sur `/medical-record`, `/documents`, `/prescriptions` — et **l'UI l'explique** (« Vous n'avez pas encore suivi ce patient — … »). Vérifié contre un patient AVEC relation (Marc Dubois) : 200 partout. |
| praticien | `/lab-work-orders` (1280×800) | 26 | 18 | 15 | 1 réel (`Nouveau bon`) + 1 onglet actif | 1 (403 §14) | 2026-09-07T15:30:00Z — **`Nouveau bon` = stub → #6695** (snackbar « bientôt disponible », 0 requête sur 2 points de clic, non grisé) alors que `POST /v1/cabinet/lab-work-orders` existe. Le 403 sur `Programmer la pose` est la garde §14 sur un bon d'un patient non suivi (couvert par #6673, mergé non déployé — cf. #6691). |
| secretariat | `/` (Tableau de bord, 1280×800) | 27 | 23 | 21 | 2 (`Ma journée`, `Tableau de bord`) | 0 | 2026-09-07T15:30:00Z — Onglets actifs. |
| secretariat | `/salle-attente` (1280×800) | 32 | 24 | 20 | 1 réel (`Prévenir le praticien`) + 3 onglets/déjà-appelés | 0 | 2026-09-07T15:30:00Z — **`Prévenir le praticien` = stub → #6696** : 0 requête, 0 repeinture, non grisé, snackbar « Notification du praticien à venir ». **Contrôle dans la même session : `Appeler` émet bien `POST /cabinet/waiting-room/call-next` + 2 `GET /cabinet/waiting-room`** — donc ni session ni coordonnées en cause. |
| pharmacie | `/` (File des commandes, 1280×800) | 35 | 18 | 18 | 0 | 0 | 2026-09-07T15:30:00Z |
| pharmacie | `/devis` (1280×800) | 42 | 22 | 20 | 2 (`Devis`, `Tous (85)`) | 0 | 2026-09-07T15:30:00Z — Onglet + facette déjà actifs. |
| pharmacie | `/stock` (1280×800) | 14 | 12 | 10 | 2 (`Stock`, `À répondre (0)`) | 0 | 2026-09-07T15:30:00Z — Onglet actif + facette à 0 élément. |
| pharmacie | `/messages` (1280×800) | 17 | 14 | 12 | 2 (`Messages`, `Toutes 4`) | 0 | 2026-09-07T15:30:00Z — Onglet + facette déjà actifs. |
| pharmacie | `/notification-preferences` (1280×800) | 13 | 9 | 9 | 0 | 0 | 2026-09-07T15:30:00Z |
| infirmiere | `/` (3 onglets, 390×844) | 8 | 6 | 5 | 1 (`Disponibilité`) | 0 | 2026-09-07T15:30:00Z — Onglet déjà actif. La bascule `En ligne` émet bien `PATCH /nurse/availability`. |
| infirmiere | `/notification-preferences` (390×844) | 5 | 3 | 3 | 0 | 0 | 2026-09-07T15:30:00Z — Les 2 bascules persistent (1 requête chacune). |

**Total ronde : 523 contrôles inventoriés, 364 activés, 320 OK.** **2 contrôles morts confirmés** (`Nouveau bon` → #6695, `Prévenir le praticien` → #6696), tous deux des **stubs à snackbar**, pas des boutons non câblés. Tous les autres verdicts « MORT » de l'auditeur se sont révélés être, après vérification manuelle systématique : des onglets/facettes **déjà actifs** (no-op légitime), des contrôles **hors viewport en X** (rangées à défilement horizontal — auditeur corrigé), ou un **sélecteur de fichier** (angle mort du détecteur). Les 12 verdicts « CASSÉ 403 » se sont révélés être la **garde §14 « relation de soin »**, correctement expliquée à l'écran.

> **Deux angles morts de l'auditeur corrigés/consignés cette ronde** : (1) un contrôle dont le `rect` sort du viewport **en X** était cliqué à des coordonnées hors écran → faux « MORT » ; `R48_audit.js` fait désormais défiler la rangée horizontalement avant de juger, et classe `SKIP` s'il reste hors champ. (2) Une **snackbar** Flutter et un **sélecteur de fichier** n'apparaissent ni dans l'arbre Semantics interrogé, ni en requête, ni en navigation : un contrôle qui n'en produit qu'un est signalé MORT à tort. À vérifier à la main avant tout rapport.

### Ronde 2026-09-07 (12:00–13:20 UTC) — 2e lot : seconds viewports + écrans denses

| app | écran/route | inventoriés | activés | OK | morts | cassés | last_check |
|---|---|---|---|---|---|---|---|
| patient | `/` (Accueil, **1280×800**) | 21 | 13 | 11 | 0 (après vérification) | 0 | 2026-09-07T13:20:00Z — 2e viewport. `Accueil` = onglet actif. **`Itinéraire` classé MORT à tort aux DEUX viewports** : le clic ouvre bien Google Maps — `window.open` intercepté = `https://www.google.com/maps/search/?api=1&query=12+rue+de+la+République%2C+69002+Lyon`, avec ouverture réelle d'un onglet. Un `window.open` externe n'émet ni requête `/v1/`, ni navigation, ni repeinture → 4e angle mort de l'auditeur. |
| patient | `/mes-rdv` (**1280×800**) | 9 | 5 | 4 | 1 (onglet actif) | 0 | 2026-09-07T13:20:00Z — 2e viewport. |
| patient | `/documents` (**1280×800**) | 39 | 21 | 20 | 1 (`Tous 292`, facette active) | 0 | 2026-09-07T13:20:00Z — 2e viewport ; les facettes sont ici toutes dans le viewport (pas de défilement horizontal à 1280). |
| patient | `/financial` (390×844) | 11 | 8 | 8 | 0 | 0 | 2026-09-07T13:20:00Z |
| praticien | `/` (Tableau de bord, **390×844**) | 5 | 2 | 2 | 0 | 0 | 2026-09-07T13:20:00Z — 2e viewport. L'app praticien (tablette/PC d'abord) se replie correctement en mobile : rail remplacé par « Ouvrir le menu de navigation ». Densité attendue, pas un défaut. |
| praticien | `/waiting-room` (**390×844 et 1280×800**) | 4 | 4 | 3 | 0 (après vérification) | 0 | 2026-09-07T13:20:00Z — **`Appeler suivant` n'est pas mort : il porte `aria-disabled=true` aux deux viewports**, la file ayant été vidée par mes propres tests X5/B4. Désactivation **légitime** (rien à appeler). 5e angle mort : l'auditeur clique sans lire `aria-disabled` et conclut MORT au lieu de DÉSACTIVÉ. |
| praticien | `/patients` (**390×844**) | 4 | 3 | 3 | 0 | 0 | 2026-09-07T13:20:00Z — 2e viewport. |
| secretariat | `/agenda` (grille semaine, 1280×800) | 100 | 76 | 62 | 2 onglets actifs + 12 vérifiés non morts | 0 | 2026-09-07T13:20:00Z — Écran le plus dense de la ronde. **Les cartes de RDV et les pastilles de créneau libre ne sont PAS mortes** : un clic sur une carte ouvre le volet de détail à droite (repeinture confirmée), un clic sur une pastille « 10:00 » émet `GET /cabinet/patients?page=1` (ouverture du choix de patient). Les 14 « MORT » du lot automatique = 2 onglets actifs + 12 contrôles jugés sur une signature Semantics prise trop tôt. **Le vrai défaut de cet écran est dans le volet, pas dans la grille → #6697.** |
| secretariat | `/patients` (Fiches patients, 1280×800) | 42 | 0 | 0 | — | — | 2026-09-07T13:20:00Z — Écran **comparé à sa maquette** (cf. `design-v2.md`) sans audit bouton-par-bouton cette ronde — audité en profondeur le 2026-09-05 (#6558). Constat de donnée neuf : colonne « Dernière visite » vide sur 30/30 → **#6701**. |
| secretariat | `/stock` (1280×800) | 40 | 0 | 0 | — | — | 2026-09-07T13:20:00Z — Écran comparé à sa maquette cette ronde ; audit de contrôles couvert le 2026-09-04. |
| pharmacie | `/` + `/orders` (**1440×900**) | 0 | 0 | 0 | — | — | 2026-09-07T13:20:00Z — 2e viewport lancé en fin de ronde — parcours non terminé dans le budget, à reprendre en tête de la prochaine ronde. |

**Total 2e lot : 275 inventoriés, 132 activés, 113 OK.** **Total de la ronde (2 lots) : 798 contrôles inventoriés, 486 activés.**

> **Angles morts de l'auditeur — liste consolidée après cette ronde.** Sur 2 rondes de vérification manuelle systématique, **2 verdicts « MORT » sur 16 étaient de vrais défauts**. Les 5 causes de faux positifs, à écarter AVANT de rapporter :
> 1. **Hors viewport en X** — rangée à défilement horizontal (facettes `/documents`) : clic hors écran. *Corrigé dans `R48_audit.js` (scroll horizontal puis re-inventaire, sinon SKIP).*
> 2. **Snackbar** — `ScaffoldMessenger.showSnackBar` n'apparaît pas dans l'arbre Semantics interrogé : ni requête, ni navigation, ni repeinture. C'est le cas des stubs #6695 / #6696, qui sont donc des « stubs », pas des « morts ».
> 3. **Sélecteur de fichier** — `FilePicker` (avatar patient) : se détecte uniquement par l'événement Playwright `filechooser`.
> 4. **`window.open` externe** — « Itinéraire » ouvre Google Maps : se détecte en instrumentant `window.open` et l'événement `page`/`popup`.
> 5. **`aria-disabled=true`** — « Appeler suivant » sur une file vide : l'auditeur clique sans lire l'attribut et conclut MORT. **Un contrôle désactivé doit être classé DÉSACTIVÉ puis jugé légitime ou non contre le code**, jamais MORT.
> S'y ajoute une cause de faux « CASSÉ » : les **403 de la garde §14 « relation de soin »** (praticien ouvrant un patient jamais suivi), qui sont volontaires **et** correctement expliqués à l'écran.
> 6. **Page légitimement clairsemée** — un écran 404 ou un état vide correct fait monter le ratio de pixels near-white au-dessus du seuil `0.92` du détecteur d'« écran blanc ». Vérifié cette ronde : `/orders` (pharmacie) et `/zzz-inexistant` donnent `white=0.992` **avec** une page « Page introuvable » complète et un CTA « Retour à l'accueil ». **Le ratio de blanc ne suffit jamais seul** : le croiser avec le nombre de contrôles inventoriés ET une lecture de la capture avant de conclure au blank-canvas.

