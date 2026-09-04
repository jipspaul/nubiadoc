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
| infirmiere | / (390) | 6 | 2 | 1 | 0 | 0 | 2026-09-04T21:45:00+00:00 |
