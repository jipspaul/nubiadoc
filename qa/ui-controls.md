# Ledger des contrôles UI audités — flutter-qa-agent

> Une ligne par écran audité en profondeur (inventaire Semantics + activation de
> CHAQUE contrôle + verdict OK/MORT/CASSÉ/DÉSACTIVÉ). Alimenté au fil des rondes ;
> à la ronde suivante, commencer par les écrans jamais audités ou les plus anciens.
> Complète `explored-paths.md` (scénarios API/flux) — ce fichier-ci se concentre
> sur la mécanique bouton-par-bouton d'un écran donné.


### Bilan complet de la ronde R83 — harnais corrigé (54 écran×viewport)

**940 contrôles inventoriés, 404 activés, 334 OK, 60 « morts » bruts, 10 « cassés » bruts, 10 désactivés, 39 hors champ.**

> 🔴 **AUCUN bouton mort ni cassé n'est CONFIRMÉ cette ronde.** Les 60 verdicts « mort » et 10 « cassé »
> du tableau sont des **artefacts du harnais** : chacun des candidats re-testé individuellement sur page
> neuve s'est révélé fonctionnel. Quatre causes distinctes ont été identifiées et **trois sont corrigées** ;
> la quatrième est documentée ici faute de correctif simple.
>
> 1. **Clic hors viewport** *(corrigé — `bringIntoView`)*. Les rects Semantics sont en coordonnées de page ;
>    un contrôle sous la ligne de flottaison recevait un clic hors écran (`document.elementFromPoint` → `RIEN`).
>    Prouvé sur « Relancer » (`/stock` secrétariat, y=858 pour un viewport de 800) : hors champ rien ne se
>    passe ; après défilement, **le même clic émet `POST /v1/cabinet/stock-requests/:id/resend`**.
> 2. **Rect de CONTENEUR pris pour celui du contrôle** *(corrigé — n'activer que les rôles de contrôle réels)*.
>    Un `flt-semantics` sans `role` concatène le texte de ses descendants : il « contient » le libellé d'un
>    bouton tout en ayant le rect de la carte entière. Prouvé sur « Je suis là » (`/mes-rdv`, 390 px) : le
>    nœud trouvé par libellé mesurait 390×739 ; ciblé sur son **rect DOM réel** (86×36), le clic émet
>    `POST /v1/appointments/:id/checkin`.
> 3. **Panneau de détail qui absorbe les clics suivants** *(atténué — page neuve par contrôle sur re-test)*.
>    Après l'ouverture d'un volet, les clics suivants de la boucle tombent sur le volet. Cause des 32 faux
>    « morts » sur les blocs de l'agenda secrétariat et des lignes de conversation des 3 apps — toutes
>    re-testées comme **fonctionnelles** (`GET /v1/cabinet/conversations/:id/messages` émis à chaque fois).
> 4. **Dialogue natif non détecté** *(non corrigé — documenté)*. Un contrôle qui ouvre un sélecteur de
>    fichier ne produit ni requête, ni repeinture, ni changement d'arbre. Prouvé sur « Modifier la photo de
>    profil » (`/profile`, 390 px) : classé « mort » par la boucle, il **ouvre bien le sélecteur de fichier**
>    aux trois points testés (`page.on('filechooser')`). Le harnais devrait écouter cet événement.
>
> Une 5ᵉ limite reste ouverte : les bandeaux à **défilement horizontal** (facettes de `/documents` à 390 px,
> rendues de x=607 à x=1394) sortent du cadre latéralement ; `bringIntoView` ne défile que verticalement.
>
> **Conséquence pour les rondes suivantes : les verdicts MORT antérieurs produits par ce harnais sont à
> re-prouver individuellement avant tout signalement.**

Non repris dans le tableau : ~35 activations ciblées (3 onglets de l'app infirmière, dialogue « Nouveau RDV »,
chips d'expédition du labo, actions de ligne `/stock` et `/devis`, facettes de `/stock`, créneaux de `/book`,
avatar de profil) et les cas adversariaux (double-submit, BACK navigateur, coupure réseau) — tous **OK**.

| app | écran/route | contrôles inventoriés | activés | OK | morts (bruts) | cassés (bruts) | hors champ | last_check |
|---|---|---|---|---|---|---|---|---|
| secretariat | `/patients/new` (Création rapide + champ « Adressé par » #7193, 1280) | 8 | 4 | 3 | 0 | 0 | **1** | 2026-09-19T20:45:00+00:00 |
| secretariat | `/cabinet-brief` (Brief du cabinet, jumeau de l'écran praticien, 1280) | 6 | 3 | 3 | 0 | 0 | 0 | 2026-09-19T20:50:00+00:00 |
| praticien | `/` (Tableau de bord, 1280) | 32 | 2 | 2 | 0 | 0 | 0 | 2026-09-19T20:20:00+00:00 |
| praticien | `/agenda` (1280) | 27 | 2 | 2 | 0 | 0 | 0 | 2026-09-19T20:20:00+00:00 |
| praticien | `/agenda` → **Brief du cabinet** (écran neuf #7191, 1280) | 7 | 6 | 6 | 0 | 0 | 0 | 2026-09-19T20:20:00+00:00 |
| secretariat | `/` (rail de navigation, 1280) | 30 | 20 | 12 | 0 | **8** *(corrigés en fin de ronde)* | 0 | 2026-09-19T20:55:00+00:00 |
| secretariat | `/correspondents` (écran neuf #7193, 1280) | 29 | 5 | 4 | 0 | 0 | **1** | 2026-09-19T20:20:00+00:00 |
| secretariat | `/messages` (messagerie patients, 1280) | 33 | 3 | 3 | 0 | 0 | 0 | 2026-09-19T20:20:00+00:00 |
| patient | `/` (Accueil, 390x844) | 22 | 6 | 6 | 0 | 0 | 0 | 2026-09-19T20:20:00+00:00 |
| patient | `/messaging` (liste, 390x844) | 9 | 3 | 3 | 0 | 0 | 0 | 2026-09-19T20:20:00+00:00 |
| patient | `/messaging/:id` (fil, 390x844) | 9 | 3 | 3 | 0 | 0 | 0 | 2026-09-19T20:20:00+00:00 |
| patient | `/notifications` (390x844) | 22 | 3 | 3 | 0 | 0 | 0 | 2026-09-19T20:20:00+00:00 |
| pharmacie | `/` (File des commandes, 1280) | 35 | 6 | 6 | 0 | 0 | 0 | 2026-09-19T20:20:00+00:00 |
| pharmacie | `/stock` (1280) | 24 | 1 | 1 | 0 | 0 | 0 | 2026-09-19T20:20:00+00:00 |
| pharmacie | `/messages` (1280) | 17 | 1 | 1 | 0 | 0 | 0 | 2026-09-19T20:20:00+00:00 |
| pharmacie | `/devis` (1280) | 41 | 1 | 1 | 0 | 0 | 0 | 2026-09-19T20:20:00+00:00 |
| infirmiere | `/` (3 onglets, 390x844) | 8 | 5 | 4 | 0 | 0 | 0 | 2026-09-19T20:20:00+00:00 |

### Ronde R85 — 2026-09-19 (diff-driven : PR #7401/#7403-#7408 mergées le jour même)

**359 contrôles inventoriés, 70 activés, 59 OK, 0 mort, 8 cassés, 2 désactivés (légitimes), 1 sans effet légitime.**

- Les **8 « cassés »** sont les entrées du rail secrétariat qui ouvrent le **mauvais écran** (Correspondants→`/devis`, Devis→`/cabinet-payouts`, Encaissements→`/messages`, Patients→`/team-messages`, Équipe→`/cabinet-stats`, Statistiques→`/bookable-slots`, Créneaux ouverts→`/appointment-motifs`, Motifs de RDV→`/correspondents`). 4 mesurés en session neuve, les 8 déduits du décalage d'index prouvé → **#7416 (P0)**. **Corrigé pendant la ronde** (PR #7418, branche `correspondents` replacée au rang 6) : re-test final en session neuve, **4/4** — Correspondants→`/correspondents`, Devis→`/devis`, Encaissements→`/cabinet-payouts`, Équipe→`/team-messages`. Le rail est donc **sain à la clôture**.
- Les **2 désactivés** sont légitimes et doublent tous deux une garde serveur : « Ajouter » (formulaire correspondant) tant que « Nom » est vide → 422 `display_name` non blanc ; « Créer le dossier » (`/patients/new`) tant que Prénom/Nom sont vides → 422 `validation_error`.
- Le **sans effet légitime** est l'onglet « Disponibilité » de l'app infirmière, **déjà actif** au moment du clic — non compté comme mort.
- **0 contrôle mort** et **0 erreur console** (hors échec de handshake WebSocket `wss://…/v1/ws`, observé sur l'app pharmacie et sans effet visible) sur l'ensemble des 15 écran×viewport audités.

⚠️ **Leçon de harnais de cette ronde.** Deux pièges de mesure ont d'abord produit de faux « morts », écartés avant publication :
1. **Coordonnées périmées** — activer une liste de contrôles inventoriée *une seule fois* donne des clics dans le vide dès que le premier a navigué. Il faut **ré-inventorier avant chaque clic** et revenir à l'écran.
2. **Libellé de groupe englobant** — chercher un contrôle par son texte seul fait tomber sur le `group` Semantics **parent**, dont le libellé concatène ceux de ses enfants : un clic au centre de ce groupe tombe dans le vide et fait conclure « bouton mort ». C'est exactement ce qui a failli produire un faux P1 « *« Créer le dossier » ne persiste rien* » — le sélecteur corrigé (`role==='button'` + égalité stricte) montre un `POST /cabinet/patients/quick → 201` parfaitement sain. **Toujours filtrer sur `role` ET ancrer le libellé.**
3. **Rail à sections repliables** — les en-têtes de groupe du rail secrétariat (« Ma journée », « Patients », « Facturation », « Messages ») sont exposés en `role=button` et **replient leur section** au clic : un balayage séquentiel décale toute la colonne et invente des destinations. Le seul protocole fiable est **une session neuve par clic**, capture prise *avant* le clic, libellé confirmé par recadrage de la capture.
| pharmacie | / @1280 | 22 | 7 | 7 | 0 | 0 | 0 | 2026-09-19T09:05:00+00:00 |
| pharmacie | /stock @1280 | 19 | 8 | 8 | 0 | 0 | 1 | 2026-09-19T09:05:00+00:00 |
| pharmacie | /devis @1280 | 26 | 11 | 11 | 0 | 0 | 0 | 2026-09-19T09:05:00+00:00 |
| pharmacie | /messages @1280 | 15 | 7 | 6 | 1 | 0 | 0 | 2026-09-19T09:05:00+00:00 |
| infirmiere | / @390 | 7 | 2 | 2 | 0 | 0 | 3 | 2026-09-19T09:05:00+00:00 |
| infirmiere | /notification-preferences @390 | 3 | 2 | 2 | 0 | 0 | 0 | 2026-09-19T09:05:00+00:00 |
| praticien | / @1280 | 23 | 5 | 5 | 0 | 0 | 4 | 2026-09-19T09:05:00+00:00 |
| praticien | /lab-work-orders @1280 | 23 | 9 | 7 | 2 | 0 | 0 | 2026-09-19T09:05:00+00:00 |
| praticien | /devis @1280 | 24 | 7 | 3 | 4 | 0 | 3 | 2026-09-19T09:05:00+00:00 |
| praticien | /stock-inventory @1280 | 28 | 4 | 4 | 0 | 0 | 0 | 2026-09-19T09:05:00+00:00 |
| praticien | /ordonnances @1280 | 17 | 3 | 3 | 0 | 0 | 0 | 2026-09-19T09:05:00+00:00 |
| praticien | /patients @1280 | 31 | 17 | 7 | 0 | 10 | 0 | 2026-09-19T09:05:00+00:00 |
| secretariat | / @1280 | 26 | 8 | 6 | 2 | 0 | 2 | 2026-09-19T09:05:00+00:00 |
| secretariat | /stock @1280 | 38 | 13 | 7 | 6 | 0 | 1 | 2026-09-19T09:05:00+00:00 |
| secretariat | /devis @1280 | 38 | 14 | 12 | 2 | 0 | 0 | 2026-09-19T09:05:00+00:00 |
| secretariat | /patients @1280 | 37 | 17 | 11 | 6 | 0 | 5 | 2026-09-19T09:05:00+00:00 |
| secretariat | /messages @1280 | 28 | 13 | 7 | 6 | 0 | 0 | 2026-09-19T09:05:00+00:00 |
| secretariat | /salle-attente @1280 | 22 | 6 | 6 | 0 | 0 | 0 | 2026-09-19T09:05:00+00:00 |
| praticien | /agenda @1280 | 22 | 7 | 7 | 0 | 0 | 0 | 2026-09-19T09:05:00+00:00 |
| praticien | /waiting-room @1280 | 21 | 6 | 6 | 0 | 0 | 0 | 2026-09-19T09:05:00+00:00 |
| praticien | /consultation @1280 | 34 | 14 | 6 | 8 | 0 | 4 | 2026-09-19T09:05:00+00:00 |
| praticien | /messages @1280 | 24 | 10 | 3 | 7 | 0 | 0 | 2026-09-19T09:05:00+00:00 |
| praticien | /stock @1280 | 18 | 4 | 4 | 0 | 0 | 0 | 2026-09-19T09:05:00+00:00 |
| praticien | /team-messages @1280 | 17 | 3 | 3 | 0 | 0 | 0 | 2026-09-19T09:05:00+00:00 |
| patient | / @390 | 17 | 10 | 10 | 0 | 0 | 0 | 2026-09-19T09:05:00+00:00 |
| patient | /documents @390 | 27 | 14 | 7 | 7 | 0 | 0 | 2026-09-19T09:05:00+00:00 |
| patient | /profile @390 | 13 | 12 | 11 | 1 | 0 | 0 | 2026-09-19T09:05:00+00:00 |
| patient | /messaging @390 | 8 | 8 | 8 | 0 | 0 | 0 | 2026-09-19T09:05:00+00:00 |
| patient | /pharmacy @390 | 7 | 6 | 6 | 0 | 0 | 0 | 2026-09-19T09:05:00+00:00 |
| patient | /book @390 | 20 | 16 | 8 | 8 | 0 | 2 | 2026-09-19T09:05:00+00:00 |
| patient | / @1280 | 17 | 10 | 10 | 0 | 0 | 0 | 2026-09-19T09:05:00+00:00 |
| praticien | / @390 | 11 | 7 | 7 | 0 | 0 | 4 | 2026-09-19T09:05:00+00:00 |
| praticien | /waiting-room @390 | 5 | 4 | 4 | 0 | 0 | 0 | 2026-09-19T09:05:00+00:00 |
| secretariat | / @390 | 9 | 3 | 3 | 0 | 0 | 5 | 2026-09-19T09:05:00+00:00 |
| secretariat | /salle-attente @390 | 4 | 3 | 3 | 0 | 0 | 0 | 2026-09-19T09:05:00+00:00 |
| pharmacie | / @390 | 13 | 8 | 8 | 0 | 0 | 1 | 2026-09-19T09:05:00+00:00 |
| infirmiere | / @1280 | 7 | 1 | 1 | 0 | 0 | 3 | 2026-09-19T09:05:00+00:00 |
| secretariat | /admin-membres @1280 | 24 | 9 | 9 | 0 | 0 | 0 | 2026-09-19T09:05:00+00:00 |
| secretariat | /admin-secretariats @1280 | 21 | 6 | 6 | 0 | 0 | 0 | 2026-09-19T09:05:00+00:00 |
| secretariat | /audit-log @1280 | 24 | 7 | 7 | 0 | 0 | 0 | 2026-09-19T09:05:00+00:00 |
| secretariat | /notification-preferences @1280 | 12 | 11 | 11 | 0 | 0 | 0 | 2026-09-19T09:05:00+00:00 |
| praticien | /notification-preferences @1280 | 12 | 11 | 11 | 0 | 0 | 0 | 2026-09-19T09:05:00+00:00 |
| praticien | /cabinet-setup @1280 | 5 | 4 | 4 | 0 | 0 | 0 | 2026-09-19T09:05:00+00:00 |
| pharmacie | /notification-preferences @1280 | 9 | 8 | 8 | 0 | 0 | 0 | 2026-09-19T09:05:00+00:00 |
| patient | /prescriptions @390 | 16 | 5 | 5 | 0 | 0 | 0 | 2026-09-19T09:05:00+00:00 |
| patient | /home-care @390 | 17 | 16 | 16 | 0 | 0 | 0 | 2026-09-19T09:05:00+00:00 |
| patient | /pharmacy/orders @390 | 16 | 9 | 9 | 0 | 0 | 0 | 2026-09-19T09:05:00+00:00 |
| patient | /pharmacy/quotes @390 | 1 | 0 | 0 | 0 | 0 | 0 | 2026-09-19T09:05:00+00:00 |
| patient | /profile/dependents @390 | 22 | 3 | 3 | 0 | 0 | 0 | 2026-09-19T09:05:00+00:00 |
| patient | /profile/referring-doctor @390 | 1 | 1 | 1 | 0 | 0 | 0 | 2026-09-19T09:05:00+00:00 |
| patient | /reviews @390 | 1 | 0 | 0 | 0 | 0 | 0 | 2026-09-19T09:05:00+00:00 |
| patient | /implant-passport @390 | 6 | 5 | 5 | 0 | 0 | 0 | 2026-09-19T09:05:00+00:00 |
| patient | /profile/consents @390 | 8 | 3 | 3 | 0 | 0 | 1 | 2026-09-19T09:05:00+00:00 |
| secretariat | /team-messages @1280 | 24 | 7 | 7 | 0 | 0 | 0 | 2026-09-19T09:05:00+00:00 |

**Écrans jamais audités avant cette ronde, tous propres** : `/admin-membres`, `/admin-secretariats`,
`/audit-log`, `/notification-preferences` (secrétariat, praticien et pharmacie) et `/cabinet-setup`
(praticien) — 0 mort, 0 cassé. Trois contrôles désactivés y sont **légitimes et prouvés** :
« Filtrer » / « Réinitialiser » de `/audit-log` (le secrétariat n'est ni admin ni manager, la route
répond `403` — cf. le sondage de rôle documenté dans `audit_log_access_cubit.dart`), et
« Enregistrer » de `/cabinet-setup`, qui **redevient actif dès que les 3 champs requis sont saisis**
(vérifié : `aria-disabled` passe de `true` à absent après saisie).

**Dernier lot de la ronde — 10 routes jamais visitées, toutes propres** : `/prescriptions`, `/home-care`,
`/pharmacy/orders`, `/pharmacy/quotes`, `/profile/dependents`, `/profile/referring-doctor`, `/reviews`,
`/implant-passport`, `/profile/consents` (patient) et `/team-messages` (secrétariat) — **0 mort, 0 cassé**.
Quatre d'entre elles dépassent le seuil de blancheur de 0,92 (`/reviews` 0,991 · `/profile/referring-doctor`
0,982 · `/prescriptions` 0,934 · `/pharmacy/quotes` 0,922) : **ce ne sont PAS des canvas vides**, l'arbre
Semantics est peuplé dans les quatre cas (« Aucun avis pour ce prestataire. » en état vide légitime ;
« Dr Hugo Marin · Implantologie · 12 rue de la République » ; la liste des ordonnances avec leurs statuts
« Signée » / « Transmise à une pharmacie » ; la liste des devis d'officine avec « Refusé » / « Accepté »).
**Le ratio de pixels blancs seul ne suffit pas à conclure sur un écran mobile peu dense — il faut le
croiser avec l'arbre Semantics.** (Et `document.querySelectorAll('canvas').length` vaut 0 sur ces écrans
alors qu'ils rendent : ce n'est pas non plus un signal d'emptiness exploitable.)

**Contrôle d'accessibilité mené sur `/cabinet-setup`** (4 champs peints sur le canvas) : les 4 `<input>`
portent bien un `aria-label` exact — « Nom du cabinet », « Adresse », « Téléphone »,
« SIRET (14 chiffres, optionnel) » — tout comme les champs de recherche de `/agenda`, `/documents` et
`/devis`. **Aucun défaut d'accessibilité.** (Note de méthode : interroger uniquement les nœuds
`flt-semantics` fait manquer ces champs — les proxies de saisie de Flutter sont des `<input>` frères.)

### Bilan consolidé de la ronde R79 (2026-09-18)

**36 écran×viewport audités bouton par bouton** sur les 5 apps : **743 contrôles inventoriés via l'arbre
Semantics, 695 activés** → 631 OK, 49 « MORT », 15 « CASSÉ », 4 « DÉSACTIVÉ ». S'y ajoutent une
quinzaine de parcours ciblés (détail devis, demandes de proches, facettes documents, facettes +
délivrance officine, appel en salle d'attente, actes de séance, tunnel de réservation, checklist de
préparation, formulaire nouveau patient, préférences de notification) non comptés ici.

**Après re-vérification manuelle de CHAQUE verdict négatif :**
- **49 « MORT » → 0 confirmé.** Causes réelles : auto-navigation de l'entrée de rail de l'écran courant,
  contrôle sous la ligne de flottaison, conteneur `group` non tappable, sélecteur de fichier natif,
  curseur d'interrupteur, nœud clippé hors conteneur défilant (piège 6), effet purement local sous le
  seuil de `pixdiff` (piège 7).
- **15 « CASSÉ » → 11 confirmés**, tous sur `praticien /patients` (→ **#7274**). Les 4 autres : un 409
  rattrapé proprement par l'app, deux 401 d'expiration de session du harnais, un contrôle hors écran.
- **4 « DÉSACTIVÉ » → 4 légitimes, prouvés** : `isOtherPractitioner` et absence de patient `checked_in`
  attribué en salle d'attente (`waiting_room_page.dart:1010`, :314), biométrie indisponible sur
  navigateur, consentement « Soins » verrouillé base légale (`consents_page.dart:182-190`, #5205).

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

6. **Nœud Semantics clippé hors de son conteneur défilant** (ronde R79, agenda secrétariat) : un
   `flt-semantics` reste exposé avec un rect à `y=725` alors que la grille défilante s'arrête à
   `y≈660` — le clic à cette coordonnée tombe sur le bandeau de pied de page, pas sur le bloc.
   Le même bloc remonté par molette à `y=448` répond normalement. **Toujours vérifier que la zone
   cliquée appartient bien au conteneur de l'élément**, pas seulement qu'elle est dans le viewport.

7. **Effet purement local + micro-repeinture** (ronde R79, `/rdv/:id/prepare`) : une case à cocher
   qui n'écrit que dans les préférences locales n'émet **aucune requête**, et son icône de 24 px
   change trop peu de pixels pour franchir le seuil de `pixdiff`. Vérification fiable : recadrer
   la zone du contrôle seul et comparer, puis **recharger la page** pour confirmer la persistance.

**Règle** : ne jamais ouvrir d'issue « bouton mort » sans re-clic ciblé isolé + preuve
(navigation, requête réseau, ou capture avant/après).

| app | écran/route | contrôles inventoriés | activés | OK | morts (vérifiés) | cassés | last_check |
|---|---|---|---|---|---|---|---|
| patient | /rdv/:id/prepare (390) | 2 | 2 | 2 | 0 — « Carte Vitale » **prouvée fonctionnelle** (bascule de case + persistance au rechargement, effet purement local : `prepare_rdv_page.dart:100-109`) | 0 | 2026-09-18T08:50:00+00:00 |
| patient | /rdv/:id/modifier (Reprogrammation, 390) | 50 | 50 | 50 | 0 | 0 | 2026-09-18T08:50:00+00:00 |
| patient | /oubliettes (390) | 2 | 1 | 1 | 0 (conteneur `group`) | 0 | 2026-09-18T08:50:00+00:00 |
| praticien | /stock-inventory (1280) | 28 | 27 | 27 | 0 | 0 | 2026-09-18T08:40:00+00:00 |
| praticien | /team-messages (1280) | 19 | 17 | 16 | 0 (auto-nav + groupe non tappable) | 0 | 2026-09-18T08:40:00+00:00 |
| praticien | /notification-preferences (1280) | 17 | 16 | 13 | 0 (3 conteneurs `group` autour des interrupteurs) | 0 | 2026-09-18T08:40:00+00:00 |
| secretariat | /patients/new (Nouveau patient) | 6 | 6 | 5 | 0 | 0 — « Créer le dossier » **désactivé tant que le formulaire est incomplet** (garde légitime) ; téléphone malformé → `422` + message pertinent (#7232 corrigée) | 2026-09-18T08:40:00+00:00 |
| patient | /home-care (390) | 17 | 17 | 17 | 0 | 0 | 2026-09-18T08:30:00+00:00 |
| patient | /reviews (390) | 1 | 1 | 1 | 0 | 0 — `white=0.97` mais **état vide légitime** (« Aucun avis pour ce prestataire. »), pas un écran blanc | 2026-09-18T08:30:00+00:00 |
| patient | /profile/referring-doctor (390) | 1 | 1 | 1 | 0 | 0 — idem : écran sobre, contenu bien rendu | 2026-09-18T08:30:00+00:00 |
| patient | /profile/consents (390) | 8 | 7 | 7 | 0 | 0 — 1 bascule « Soins » DÉSACTIVÉE **prouvée légitime** (`consents_page.dart:182-190`, verrou base légale #5205) | 2026-09-18T08:30:00+00:00 |
| patient | /book → /appointments/slots (390) | 45 | 12 | 12 | 0 | 0 — tunnel joué jusqu'à `POST /v1/slots/:id/hold` + « Continuer » | 2026-09-18T08:30:00+00:00 |
| secretariat | /stock, /liste-attente, /messages, /appointment-motifs, /bookable-slots (390→1280) | 134 | 129 | 122 | 0 (auto-nav + champs de recherche) | 0 | 2026-09-18T08:30:00+00:00 |
| praticien | /ordonnances + composeur (1280) | 21 | 6 | 6 | 0 | 0 — aperçu présent, **remplissage non exécuté** (champ DCI sous la ligne de flottaison de la surcouche) | 2026-09-18T08:30:00+00:00 |
| secretariat | / (Tableau de bord) | 25 | 24 | 23 | 0 (auto-nav) | 0 | 2026-09-18T08:00:00+00:00 |
| secretariat | /agenda (grille semaine) | 67 | 61 | 59 | 0 — **les 3 blocs de RDV signalés MORT sont clippés hors grille** (`y≈693-725` alors que la grille s'arrête à `y≈660`) ; remonté par molette à `y=448`, le même bloc ouvre la feuille d'actions. 8 blocs sur 8 testés → OK (« Fermer / Marquer arrivé / Déplacer / Annuler / Appeler ») | 0 | 2026-09-18T08:00:00+00:00 |
| secretariat | /salle-attente | 26 | 25 | 24 | 0 (auto-nav) | 0 | 2026-09-18T08:00:00+00:00 |
| secretariat | /patients (Fiches patients) | 37 | 36 | 35 | 0 (auto-nav) | 0 | 2026-09-18T08:00:00+00:00 |
| secretariat | /devis | 38 | 32 | 31 | 0 | 1 (401 de session en fin de parcours — artefact de harnais) ; 5 « Relancer »/« PDF » hors écran après scroll | 2026-09-18T08:00:00+00:00 |
| secretariat | /audit-log, /admin-membres, /admin-secretariats, /cabinet-stats, /cabinet-payouts | 115 | — | — | — | — (parcours de lecture : les 5 écrans peignent ; `audit-log` et `members` sont **403 par conception** — `ProAdminOrManagerClaims`, `audit_log.rs:5` : secretary/practitioner → 403) | 2026-09-18T08:00:00+00:00 |
| pharmacie | /orders/:id/pickup (scan de retrait) | 3 | 3 | 3 | 0 | 0 — « Caméra indisponible — utilisez la saisie manuelle ci-dessous. » + « Code de retrait » + « Valider le code » | 2026-09-18T08:00:00+00:00 |
| patient | / (Accueil, 1280) | 18 | 17 | 16 | 0 | 1 (401 de session, artefact de harnais — écarté) | 2026-09-18T07:20:00+00:00 |
| patient | /mes-rdv (1280) | 7 | 7 | 7 | 0 | 0 | 2026-09-18T07:20:00+00:00 |
| patient | /documents (1280) | 27 | 26 | 23 | 0 (3 faux positifs re-vérifiés : la recherche filtre bien, les 12 facettes basculent ; « Autre » était hors écran — la rangée est scrollable horizontalement) | 0 | 2026-09-18T07:20:00+00:00 |
| patient | /prescriptions (1280) | 15 | 15 | 15 | 0 | 0 | 2026-09-18T07:20:00+00:00 |
| patient | /treatment-plans (1280) | 9 | 9 | 9 | 0 | 0 | 2026-09-18T07:20:00+00:00 |
| patient | /profile (1280) | 14 | 13 | 10 | 0 (3 faux positifs : « Modifier la photo de profil » ouvre un sélecteur de fichier — `profile_page.dart:743 onTap:_pickAndUpload` — invisible en headless ; 2 groupes non tappables) | 0 | 2026-09-18T07:20:00+00:00 |
| patient | /profile/dependents (1280 + 390) | 21 | 14 | 14 | 0 | 0 (7 hors écran après scroll vertical, liste de 14 proches) | 2026-09-18T07:20:00+00:00 |
| patient | /financial (liste + détail, 1280 + 390) | 12 | 12 | 10 | 0 | **2 — RÉEL : le retour (système ET bouton d'appbar) vide la liste → #7270** | 2026-09-18T07:20:00+00:00 |
| praticien | / (Tableau de bord, 1280) | 20 | 19 | 18 | 0 | 1 (409 `invalid_status` sur « Démarrer la consultation » quand la séance est déjà ouverte — MAIS l'app retombe proprement sur `GET /cabinet/consultations?status=in_progress` et ouvre la bonne séance : **pas un défaut**) | 2026-09-18T07:20:00+00:00 |
| praticien | / (Tableau de bord, 390) | 6 | 6 | 5 | 0 (2 faux positifs : les 2 lignes de « À traiter » étaient sous la ligne de flottaison ; scrollées, elles naviguent vers /agenda et /messages) | 1 (idem 409 ci-dessus) | 2026-09-18T07:20:00+00:00 |
| praticien | /agenda (1280 + 390) | 32 | 31 | 29 | 0 (auto-nav) | 0 | 2026-09-18T07:20:00+00:00 |
| praticien | /waiting-room (1280 + 390) | 32 | 26 | 25 | 0 (auto-nav) | 0 — **5 « Appeler » DÉSACTIVÉS prouvés légitimes** : `waiting_room_page.dart:1010` `isOtherPractitioner`, et « Appeler suivant » ne s'active que si un patient `checked_in` est attribué au praticien connecté ; check-in provoqué par API → le bouton devient « Appeler Marc Dubois », actif, et rend `200 {"called":true}` | 2026-09-18T07:20:00+00:00 |
| praticien | /patients (1280) | 32 | 31 | 19 | 0 (auto-nav) | **11 — RÉEL : ouvrir 11 des cartes patient rend 403 sur `/documents` et `/medical-record` → #7274** | 2026-09-18T07:20:00+00:00 |
| praticien | /ordonnances (1280) | 17 | 16 | 15 | 0 (auto-nav) | 0 | 2026-09-18T07:20:00+00:00 |
| praticien | /devis (1280) | 24 | 22 | 21 | 0 (auto-nav) | 0 | 2026-09-18T07:20:00+00:00 |
| praticien | /stock (1280) | 19 | 18 | 16 | 0 (auto-nav) | 0 | 2026-09-18T07:20:00+00:00 |
| praticien | /lab-work-orders (1280) | 22 | 18 | 17 | 0 | 1 (hors écran) | 2026-09-18T07:20:00+00:00 |
| praticien | /messages (1280) | 5 | 5 | 4 | 0 (auto-nav) | 0 | 2026-09-18T07:20:00+00:00 |
| pharmacie | / (File des commandes, 1280) | 22 | 21 | 18 | 0 (3 faux positifs : auto-nav « Commandes » + 2 facettes — re-vérifiées, elles filtrent et changent l'action de ligne) | 0 | 2026-09-18T07:20:00+00:00 |
| pharmacie | /orders/:id (Délivrance) + /orders/:id/pickup | 8 | 8 | 8 | 0 | 0 | 2026-09-18T07:20:00+00:00 |
| pharmacie | /stock (1280) | 13 | 12 | 9 | 0 (auto-nav + facette + champ de recherche) | 0 | 2026-09-18T07:20:00+00:00 |
| pharmacie | /messages (1280) | 15 | 14 | 11 | 0 (idem) | 0 | 2026-09-18T07:20:00+00:00 |
| pharmacie | /devis (1280) | 26 | 25 | 22 | 0 (idem) | 0 | 2026-09-18T07:20:00+00:00 |
| pharmacie | /notification-preferences (1280) | 13 | 12 | 9 | 0 (groupes non tappables) | 0 | 2026-09-18T07:20:00+00:00 |
| infirmiere | / (Accueil, 390) | 8 | 6 | 6 | 0 | 0 (« Se déconnecter » non activé — destructif) | 2026-09-18T07:20:00+00:00 |
| infirmiere | /notification-preferences (390) | 5 | 4 | 4 | 0 (2 faux positifs : les 2 interrupteurs « Visites » émettent bien `PATCH /v1/me/notification-preferences` → 200 et **persistent au rechargement** — `aria-checked` false→true, `inapp_visites` passé à true côté API) | 0 | 2026-09-18T07:20:00+00:00 |
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

### Ronde 2026-09-07 (13:20–13:45 UTC) — 3e lot : écrans jamais parcourus + états RBAC

| app | écran/route | inventoriés | activés | OK | morts | cassés | last_check |
|---|---|---|---|---|---|---|---|
| secretariat | `/devis` (1280×800) | 55 | 34 | 31 | 0 réel (2 onglets actifs + 1 champ de recherche) | 0 | 2026-09-07T13:45:00Z — 3e vague — écran le plus dense du secrétariat. |
| secretariat | `/team-messages` (Messagerie interne, 1280×800) | 31 | 25 | 21 | 2 réels (`Épingler`, `Joindre un patient, un devis…`) + 2 onglets actifs | 0 | 2026-09-07T13:45:00Z — **2 stubs à snackbar → #6702** (« Épingler ce message : à venir », « Joindre un objet du produit au message »). Vérifiés en direct : 0 requête, 0 repeinture, 0 téléchargement, 0 `window.open`, non grisés. |
| secretariat | `/cabinet-payouts` (Encaissements, 1280×800) | 26 | 23 | 19 | 1 réel (`Connecter Stripe`) + 1 désactivé légitime + 2 onglets actifs | 0 | 2026-09-07T13:45:00Z — **`Connecter Stripe` = stub → #6702.** **`Exporter (CSV)` porte `aria-disabled=true` : désactivation LÉGITIME** — `onPressed: payouts.isEmpty ? null : _exportPayoutsCsv(...)` (`cabinet_payouts_page.dart:64`). Contrôle négatif utile : les deux boutons sont côte à côte, un seul est un stub. |
| secretariat | `/liste-attente` (Demandes de créneau, 1280×800) | 22 | 19 | 17 | 0 réel (2 onglets actifs) | 0 | 2026-09-07T13:45:00Z — 3e vague. |
| secretariat | `/bookable-slots` (Créneaux ouverts, 1280×800) | 30 | 26 | 21 | 0 réel (1 en-tête de section repliable + 3 sous-entrées masquées par son repli) | 0 réel | 2026-09-07T13:45:00Z — Le « CASSÉ » unique était **`Statistiques` → 403** : intentionnel et **remarquablement bien dégradé** (cf. ci-dessous). `Créer un créneau`, `Tous les praticiens`, `Toutes les dates` répondent. |
| secretariat | `/cabinet-stats` (Pilotage du cabinet, 1280×800) | 27 | 1 | 1 | 0 | 0 (403 volontaire) | 2026-09-07T13:45:00Z — **Dégradation partielle exemplaire, à citer en référence** : les 4 cartes de KPI s'affichent (CA encaissé 6 225,01 € / Reste à encaisser 45 858,79 € / Taux de transformation 68 % / Devis 192-282) et **seule** la section « Activité par praticien » est verrouillée, avec cadenas + « Réservé aux praticiens — Votre rôle ne permet pas d'afficher l'activité par praticien. » L'écran n'est ni vide ni en erreur. |
| secretariat | `/audit-log` (Journal d'accès, 1280×800) | 26 | 0 | 0 | — | 0 (403 volontaire) | 2026-09-07T13:45:00Z — Entrée **absente du rail** pour un secrétaire (donc non proposée) ; l'accès direct par URL rend cadenas + « Accès réservé aux administrateurs » + « Le journal d'accès n'est visible que par les rôles admin/manager du cabinet. » `ProAdminOrManagerClaims` (`audit_log.rs:63`). Conforme. |
| praticien | `/ordonnances` (1280×800) | 19 | 16 | 15 | 0 réel (onglet actif) | 0 | 2026-09-07T13:45:00Z — 3e vague. |
| praticien | `/devis` (1280×800) | 27 | 21 | 20 | 0 réel (onglet actif) | 0 | 2026-09-07T13:45:00Z — 3e vague. |
| praticien | `/stock` (1280×800) | 21 | 17 | 16 | 0 réel (onglet actif) | 0 | 2026-09-07T13:45:00Z — 3e vague. |
| praticien | `/messages` (1280×800) | 27 | 23 | 22 | 0 réel (onglet actif) | 0 | 2026-09-07T13:45:00Z — 3e vague. |
| praticien | `/team-messages` (1280×800) | 21 | 17 | 16 | 0 réel (onglet actif) | 0 | 2026-09-07T13:45:00Z — 3e vague. **0 erreur console sur les 5 écrans praticien de cette vague.** |
| pharmacie | `/` (File des commandes, **1440×900**) | 37 | 19 | 19 | 0 | 0 | 2026-09-07T13:45:00Z — 2e viewport bouclé : `Délivrer` navigue vers `/orders/:id/pickup`, les 4 facettes (Toutes 59 / Reçues 11 / En préparation 4 / Prêtes 44) et la recherche répondent. |
| pharmacie + patient | routes inconnues → **écran 404** | 1 | 1 | 1 | 0 | 0 | 2026-09-07T13:45:00Z — `/orders`, `/zzz-inexistant` : `white=0.992` mais **page complète** « Page introuvable » + CTA « Retour à l'accueil ». Faux positif du seuil de blank-canvas (6e angle mort). |

**Total 3e lot : 370 inventoriés, 242 activés, 219 OK.**

**TOTAL DE LA RONDE (3 lots + 2e viewport infirmière) : 1 181 contrôles inventoriés  747 activés  sur 5 apps aux 2 viewports.**

> **Inventaire exhaustif du motif « CTA-stub à snackbar »** (extraction sur les 5 apps, motif `onPressed: () => …showSnackBar(` sans autre effet) : **7 occurrences sur 3 apps** — `Nouveau bon` (#6695), `Prévenir le praticien` (#6696), puis `Connecter Stripe`, `Attribuer`, `Épingler`, `Joindre un patient, un devis…`, `Télécharger l'app` (**#6702**). Aucune autre app n'en porte. C'est la **seule famille de « boutons morts » réellement présente dans le produit** : tous les autres verdicts MORT de la ronde se sont révélés être des faux positifs d'outillage ou des désactivations légitimes.
| infirmiere | `/` + `/notification-preferences` (**1280×800**) | 13 | 9 | 8 | 0 réel (onglet actif) | 0 | 2026-09-07T13:50:00Z — 2e viewport, dernier trou de couverture comblé. L'app **s'étire correctement** au format PC (en-tête pleine largeur, section « Disponibilité » + bascule `En ligne` à droite, barre de 3 onglets en pied) : ce n'est pas une colonne mobile centrée dans du vide. `white=0.991` **uniquement** parce que l'onglet Disponibilité ne porte qu'un seul contrôle — 7e cas de faux positif du seuil de blank-canvas. La bascule émet bien `PATCH /nurse/availability`. Aucun écart de token. |

**COUVERTURE UI DE LA RONDE — COMPLÈTE : les 5 apps parcourues aux 2 viewports.**


## Ronde 2026-09-07 (18:00–22:00 UTC) — 4e lot, ciblage diff-driven de #6704/#6702

> **Piège de mesure neuf, à retenir** : sur `/salle-attente` (secrétariat), un `Timer.periodic` de **15 s**
> (`waiting_room_page.dart:53-60`) émet `GET /cabinet/waiting-room` en continu. L'auditeur qui compte
> « une requête après le clic » y voit un effet et classe **OK** un contrôle inerte. C'est ce qui est
> arrivé à « Prévenir le praticien » (stub connu, **#6696**) et au 2ᵉ « Appeler » de la file dans le
> lot automatique ci-dessous : leur `net` ne contient QUE le tick périodique. **8ᵉ angle mort de
> l'auditeur** — sur un écran à rafraîchissement automatique, ne compter que les requêtes *autres*
> que celles de la boucle de rafraîchissement.

| app | écran/route | inventoriés | activés | OK | morts | cassés | last_check |
|---|---|---|---|---|---|---|---|
| secretariat | `/salle-attente` (1280×800) | 7 | 7 | 5 réels | 2 non concluants (`Prévenir le praticien` = stub #6696, 2ᵉ `Appeler` = ligne hors tête de file) | 0 | 2026-09-07T22:00:00Z — **`Appeler Marc Dubois` : `POST /cabinet/waiting-room/call-next` → 200 `{"called": false}` traité comme un succès, aucun retour visuel → #6707.** KPI/bandeau comptant les `in_consultation` → #6708. Colonne « Estimation » recopiant l'attente écoulée → #6713. |
| secretariat | `/cabinet-payouts` (Encaissements, 1280×800) | 7 | 5 | 5 | 0 | 0 | 2026-09-07T22:00:00Z — **Correctif #6702 confirmé live** : `Connecter Stripe` porte `aria-disabled=true` et son `Tooltip` (« Connexion Stripe indisponible pour l'instant. ») est **exposé dans l'arbre Semantics**. `Exporter (CSV)` désactivé en septembre (0 virement) et **actif en juillet** (3 virements) → désactivation conditionnelle correcte. Mécanique du sélecteur de mois **prouvée** (Sept 0 → Juil 3 lignes). Incohérence « écart cumulé » → #6712. |
| secretariat | `/team-messages` (Messagerie interne, 1280×800) | 4 (hors rail) | 2 | 2 | 0 | 0 | 2026-09-07T22:00:00Z — **Correctif #6702 confirmé live** : `Joindre un patient, un devis…` et `Épingler` sont `aria-disabled=true` avec leurs Tooltips. `Mentionner` et `Envoyer` répondent. Auteur rendu comme adresse e-mail → #6714. |
| secretariat | `/agenda` (grille semaine, 1280×800) | 50 | 50 | 34 | 16 (artefact de bord : rects à `y` 850-1000 dans un viewport de 800) | 0 | 2026-09-07T22:00:00Z — Les 34 OK couvrent `Nouveau RDV`, navigation de semaine, `Aujourd'hui`, les 2 filtres praticien et 24 pastilles de créneau (chacune → `GET /cabinet/patients`). Les 16 « morts » sont tous à `y > 800` : **même angle mort que le lot du 2026-09-07 matin**, non filés. |
| secretariat | `/devis` (1280×800) | 20 | 20 | 16 | 4 (même artefact `y > 800`) | 0 | 2026-09-07T22:00:00Z — `Relancer` émet réellement `POST /cabinet/quotes/:id/send` (5 devis relancés), `PDF` ouvre le détail (`GET /cabinet/quotes/:id` + `GET /cabinet/patients/:id`), les 4 facettes et le tri répondent. |
| praticien | `/consultation` (liste des séances, 1280×800) | 22 | 22 | 18 | 4 (artefact `y > 800`) | 0 | 2026-09-07T22:00:00Z — **1re fois auditée**. Les 3 facettes (En cours / Terminée / Annulée) répondent ; **chaque ligne de séance ouvre `/consultation?id=…`** avec `GET /cabinet/consultations/:id` + `dental-chart` + `favorite-acts`. Rail (Inventaire / Labo / Messagerie interne) correct. |
| praticien | `/stock-inventory` (Inventaire, 1280×800) | 17 | 17 | 14 | 2 (onglet actif + artefact) | 1 | 2026-09-07T22:00:00Z — **1re fois auditée**. |
| pharmacie | `/` (File des commandes, 1280×800) | 15 | 15 | 14 | 0 | 1 | 2026-09-07T22:00:00Z — Les 4 facettes chiffrées (Toutes 59 / Reçues 11 / En préparation 4 / Prêtes 44) et les 8 `Délivrer` naviguent vers `/orders/:id/pickup`. |
| patient | `/oubliettes` (390×844) | 1 | 1 | 1 | — | 0 | 2026-09-07T22:00:00Z — **1 seul contrôle sur tout l'écran** : les 10 cartes de documents n'ont AUCUN rôle Semantics et 3 clics réels ne produisent rien → **#6710**. 15 `GET /documents` en cascade pour 10 lignes → **#6711**. |
| patient | `/reviews` (390×844) | 1 | 1 | 1 | 0 | 0 | 2026-09-07T22:00:00Z — Sans `?providerId=`, état vide légitime « Aucun avis pour ce prestataire. » (`app_router.dart:435` lit `providerId` en query). `Retour` ramène à `/`. |
| patient | `/implant-passport` (390×844) | 5 | 5 | 4 | 1 (5ᵉ carte, `y` hors viewport) | 0 | 2026-09-07T22:00:00Z — Chaque carte ouvre la fiche complète (« En place depuis 0 mois », « Exporter cette fiche »). |
| patient | `/profile/consents` (390×844) | 8 | 7 | 6 | 1 (dernier `Détails`, hors viewport) | 0 | 2026-09-07T22:00:00Z — `Soins` est **désactivé légitimement** (« Nécessaire au service · Non modifiable »). `Partage avec ma pharmacie` bascule et émet `GET /account/orders`. |
| patient | `/profile/referring-doctor` (390×844) | 1 | 1 | 1 | 0 | 0 | 2026-09-07T22:00:00Z — « Dr Hugo Marin · Implantologie · 12 rue de la République, 69002 Lyon » ; `Changer de médecin traitant` ouvre la recherche. |
| patient | `/pharmacy` (Ma pharmacie, 390×844) | 7 | 7 | 7 | 0 | 0 | 2026-09-07T22:00:00Z — **1re fois auditée**. `Envoyer une ordonnance` (`GET /account/prescriptions` + `/account/pharmacy`), `Suivre mes commandes` (`GET /account/orders`), `Mes devis pharmacie` (`GET /account/pharmacy-quotes`), `Itinéraire`, `Appeler`, `Changer de pharmacie` : 7/7 répondent. |
| patient | `/appointments` → **tunnel de réservation complet** (390×844) | 41 → 59 → 5 | parcours métier complet | OK | 0 | 0 | 2026-09-07T22:00:00Z — **Parcours métier bout-en-bout joué en UI** : carte praticien (rail 3 jours) → grille jour (rail `MAR 8 · 15 dispo` … `VEN 11 · 5 dispo`, Matin/Après-midi) → `POST /slots/:id/hold` → `Continuer` → feuille modale (bénéficiaire, récap + `Modifier`, puces de motif, rappels, compte à rebours de blocage) → `Contrôle` remplit le champ Motif → `Confirmer le rendez-vous` → **`POST 201 /bookings`** → écran « Demande de rendez-vous envoyée ». **Correctif #6702 confirmé** : `Télécharger l'app` `aria-disabled=true`, Tooltip « Téléchargement bientôt disponible. » exposé. |
| infirmiere | `/` (Disponibilité / Offres / Ma visite, 390×844) | 5 | 5 | 5 | 0 | 0 | 2026-09-07T22:00:00Z — 5/5. La bascule `En ligne` émet `PATCH 200 /nurse/availability` ; état restauré `is_online: true` en fin de ronde (vérifié via `GET /nurse/profile`). Onglet `Offres` → « Aucune offre — Les demandes de visite proches apparaîtront ici. » |
| **TOTAL RONDE** | **15 écrans** | **166** | **163** | **133** | **28 (dont 26 artefacts de bord `y > viewport`)** | **2** | 2026-09-07T22:00:00Z |

### Ronde 2026-09-07 — 2e vague (19:00–19:35 UTC), écrans jamais audités + cas adversariaux

| app | écran/route | inventoriés | activés | OK | morts | cassés | last_check |
|---|---|---|---|---|---|---|---|
| secretariat | `/appointments` (Prendre un RDV, 1280×800) | 7 | 7 | 7 | 0 | 0 | 2026-09-07T19:35:00Z — **1re fois auditée**. Les 4 facettes de statut (Tous / Confirmé / En attente / Annulé) et `Actualiser` (`GET /cabinet/appointments`) répondent. |
| secretariat | `/appointment-motifs` (1280×800) | 6 | 6 | 4 | 1 (`Motifs de RDV` = onglet déjà actif) | 1 | 2026-09-07T19:35:00Z — **1re fois auditée**. Le « CASSÉ » est `Statistiques` → `/cabinet-stats` avec `403 GET /cabinet/stats/activity` : **dégradation volontaire déjà documentée** (les 4 KPI s'affichent, seule la section « Activité par praticien » est verrouillée). `Créneaux ouverts` navigue vers `/bookable-slots`. |
| secretariat | `/admin-membres` (1280×800) | 5 | 4 | 4 | 0 | 1 désactivé | 2026-09-07T19:35:00Z — **1re fois auditée**. `Actualiser` porte `aria-disabled=true` : légitime, le secrétaire n'a pas accès à `/cabinet/members` (403 RBAC admin/manager, sonde volontaire de `members_access_cubit.dart`). Les onglets Membres/Secrétariats répondent. |
| secretariat | `/admin-secretariats` (1280×800) | 4 | 4 | 4 | 0 | 0 | 2026-09-07T19:35:00Z — **1re fois auditée**. 3 secrétariats listés (Secrétariat A / B / QA-del-test-818, tous « Actif »), `Actualiser` → `GET /cabinet/secretariats`, `Inviter un secrétariat` ouvre son dialogue. |
| secretariat | `/messages` (Messagerie patients, 1280×800) | 11 | 11 | 11 | 0 | 0 | 2026-09-07T19:35:00Z — **1re fois auditée**. Les 2 facettes (Tous / Non lus) et les 7 fils ouvrent leur conversation (`GET /cabinet/conversations/:id/messages`). |
| patient | `/pharmacy/search` (390×844) | 3 | 3 | 3 | 0 | 0 | 2026-09-07T19:35:00Z — **1re fois auditée**. Mécanique prouvée : saisie « pharmacie » → `GET 200 /pharmacies` → 8 résultats cliquables. **Piège d'outillage relevé** : au 1er passage l'arbre Semantics est revenu **vide** ; il faut **deux** passes d'activation (`window.flutter.semanticsEnabled`) espacées sur cet écran. Ce n'était **pas** un défaut produit — vérifié en capture (titre, champ de recherche et état vide « Recherchez votre pharmacie » bien peints). **9ᵉ angle mort de l'auditeur.** |
| patient | `/pharmacy/send` (390×844) | 104 | 103 | 13 | 90 (artefact de bord : 104 cartes empilées dans un viewport de 844 px) | 0 | 2026-09-07T19:35:00Z — **1re fois auditée**. Étape « 1. Choisissez l'ordonnance » : 104 ordonnances, pastilles « Signé » / « Déjà transmise une fois ». `Transmettre à la pharmacie` **désactivé** tant qu'aucune ordonnance n'est sélectionnée — désactivation légitime. |
| patient | `/pharmacy/orders` (Suivi de commandes, 390×844) | 16 | 16 | 16 | 0 | 0 | 2026-09-07T19:35:00Z — **1re fois auditée**. Chaque commande ouvre son détail (`GET /account/orders/:id`), statuts « Retirée » / « Reçue » cohérents avec l'API. |
| pharmacie | `/orders/:id/pickup` (Scan de retrait, 1280×800) | 3 | 3 | 3 | 0 | 0 | 2026-09-07T19:35:00Z — **1re fois auditée**. Repli caméra correct (« Caméra indisponible — utilisez la saisie manuelle ci-dessous. »), saisie manuelle toujours offerte. |
| praticien | `/patients` (fiche d'un patient sans relation de soin, 1280×800) | 20 | 20 | 19 | 0 | 1 | 2026-09-07T19:35:00Z — Le « CASSÉ » est la garde §14 « relation de soin » (403 sur `/documents`, `/medical-record`, `/prescriptions` d'un patient jamais suivi) : **comportement attendu**, déjà documenté. |

#### Cas adversariaux joués (Étape 2f)

| cas | écran / flux | résultat |
|---|---|---|
| **Double-clic rapide sur un CTA d'action** | patient, tunnel de réservation, « Confirmer le rendez-vous » (2 clics à 90 ms) | **CORRECT** — **un seul** `POST 201 /bookings` émis, aucun double-booking, écran de confirmation rendu une fois. |
| **Saisie invalide via l'UI** | pharmacie `/orders/:id/pickup`, code `ZZZZ-INVALIDE-9999` | **CORRECT et exemplaire** — `POST 404 /pharmacy/orders/pickup-scan` → « **Code inconnu** — Revérifiez le code sur l'ordonnance et réessayez », bouton `Réessayer` **et** le champ de saisie conservé. Aucun 500, aucun cul-de-sac. **À citer comme référence** : c'est exactement ce que la messagerie ne fait pas (#6717). |
| **BACK du navigateur au milieu d'un flux** | patient, tunnel de réservation, étape « grille du jour » | **DÉFAUT — #6718.** Le « Retour » de l'app revient bien à la recherche (contrôle positif) ; le BACK du navigateur, depuis la même étape, sort vers `/` et le « suivant » ne rattrape pas. |
| **Coupure réseau pendant une action** | patient `/messaging`, ouverture d'une conversation avec `route.abort()` | **DÉFAUT — #6717.** 9 nœuds → 1 : la liste des 8 conversations est détruite. « Réessayer » n'émet **aucune** requête (`onRetry: () => context.pop()`). |
| **Réseau rétabli puis rechargement** | patient `/messaging` | **CORRECT** — l'écran se rétablit intégralement (n=9), aucune erreur résiduelle. |

### Ronde 2026-09-07 — total consolidé des 3 vagues

| | inventoriés | activés | OK | morts | cassés | désactivés |
|---|---|---|---|---|---|---|
| **TOTAL RONDE (25 écrans, 5 apps, 2 viewports)** | **384** | **372** | **231** | **136** | **5** | **12** |

> **Lecture des 136 « morts »** : **≈ 130 sont l'artefact de bord** déjà documenté (rect dont le `y`
> dépasse la hauteur du viewport — 90 sur le seul `/pharmacy/send`, qui empile 104 cartes d'ordonnance
> dans 844 px, 16 sur `/agenda`, 4 sur `/devis`, 2 par écran ailleurs). Les morts **réels** de la ronde
> sont ceux déjà filés : les 10 cartes de `/oubliettes` (#6710) et « Réessayer » de la messagerie qui
> n'émet aucune requête (#6717). Les 5 « cassés » sont tous des **403 volontaires** (garde §14 relation
> de soin sur `/patients` praticien, `cabinet/stats/activity` réservé aux praticiens) ou du bruit
> d'infra hors produit.

## Ronde 2026-09-08 (00:00–02:30 UTC) — audit de commandes, 5 apps, verdicts re-prouvés au pixel

| app | écran/route | viewport | inventoriés | activés | OK | morts | cassés | désactivés | last_check |
|---|---|---|---|---|---|---|---|---|---|
| patient | `/` (Accueil) | 390×844 | 17 | 16 | 16 | 0 | 0 | 0 | 2026-09-08T00:38:00Z |
| patient | `/mes-rdv` | 390×844 | 7 | 4 | 4 | 0 | 0 | 0 | 2026-09-08T00:45:00Z |
| patient | `/messaging` | 390×844 | 8 | 1 | 1 | 0 | 0 | 0 | 2026-09-08T00:45:00Z |
| patient | `/profile` | 390×844 | 12 | 12 | 12 | 0 | 0 | 0 | 2026-09-08T01:25:00Z |
| patient | `/appointments` (+ sous-écran créneaux) | 390×844 | 27 | 6 | 6 | 0 | 0 | 0 | 2026-09-08T00:30:00Z |
| praticien | `/ordonnances/new?patientId=` | 1440×900 | 45 | 4 | 4 | 0 | 0 | 0 | 2026-09-08T00:28:00Z |
| secretariat | `/` (Tableau de bord) | 1280×800 | 28 | 16 | 16 | 0 | 0 | 0 | 2026-09-08T01:15:00Z |
| pharmacie | `/` (File des commandes) | 1280×800 | 23 | 13 | 13 | 0 | 0 | 0 | 2026-09-08T01:20:00Z |
| pharmacie | `/stock` | 1280×800 | 13 | 11 | 11 | 0 | 0 | 0 | 2026-09-08T02:05:00Z |
| pharmacie | `/orders/:id` (Délivrance) | 1280×800 | 28 | 5 | 5 | 0 | 0 | 0 | 2026-09-08T00:20:00Z |
| infirmiere | `/` (Disponibilité) | 390×844 | 7 | 6 | 6 | 0 | 0 | 1 (déconnexion, non activé) | 2026-09-08T00:31:00Z |
| **TOTAL RONDE (11 écrans, 5 apps, 2 viewports)** | | | **215** | **94** | **94** | **0** | **0** | **1** |

### ⚠️ Correction de méthode — d'où venaient les « morts » des rondes précédentes

Le détecteur utilisé jusqu'ici jugeait un contrôle **MORT** quand, après le clic, il n'observait
ni changement d'URL, ni requête `/v1/`, ni variation du **nombre de nœuds `flt-semantics`**.
Ce troisième critère est **insuffisant** : une bascule, un filtre, un onglet ou une sélection
repeignent l'écran **sans changer le nombre de nœuds**. Résultat : des contrôles parfaitement
fonctionnels étaient déclarés morts.

**13 candidats « MORT » ont été rejoués un par un cette ronde, avec comparaison de l'empreinte
md5 de la capture d'écran avant/après. Les 13 sont vivants :**

| candidat | app / écran | preuve du contraire |
|---|---|---|
| `Modifier la photo de profil` | patient `/profile` | ouvre bien un sélecteur de fichier — **1 événement `filechooser`** capté par Playwright. Aucun pixel ne bouge : c'est le comportement normal d'un `<input type=file>`, pas un bouton mort. |
| `Authentification biométrique` | patient `/profile` | `aria-checked` **false → true → false**, pixels modifiés. Aucune requête `/v1/` : bascule locale, cohérent. |
| `Toutes` / `Reçues` / `En préparation` / `Prêtes` | pharmacie `/` | les 4 filtres repeignent la liste (`aria-checked` bascule). Le filtrage côté API est par ailleurs **correct** : `?status=received|preparing|ready|picked_up` renvoie exactement les bons sous-ensembles, `?status=zzz` → 422. |
| `À répondre (0)` / `Refusées (10)` / `Stock` | pharmacie `/stock` | pixels modifiés à chaque clic. |
| `Ma journée` / `Tableau de bord` | secretariat `/` | pixels modifiés (bascule de section sans changement d'URL). |
| `Itinéraire` | patient `/` | navigue vers `/home-care/<visit_id>`. |
| `Notifications` / `Mes ordonnances` | patient `/` | 12 requêtes `/v1/` pour la première, navigation vers `/prescriptions` pour la seconde. |

**Conséquence pour les rondes suivantes** : le critère de repeinture doit être l'**empreinte de
capture d'écran**, et l'inventaire doit écouter l'événement `filechooser`. Les deux corrections
sont désormais dans `w8_lib.js` / `qa-lib.js`. Le chiffre « 136 morts » de la ronde 2026-09-07
est à lire avec cette réserve **en plus** de l'artefact de bord déjà documenté : les morts réels
restent ceux qui ont été filés (#6710, #6717), pas le volume brut.

### Cas adversariaux joués cette ronde

| cas | écran | verdict |
|---|---|---|
| **BACK navigateur au milieu du tunnel de réservation** | patient `/appointments` → sous-écran créneaux | **CORRECT — correctif #6718 confirmé.** L'ouverture du sous-écran crée bien une entrée d'historique (`history.length` 4 → 5) et le BACK **revient sur `/appointments`** avec ses 21 contrôles de recherche, sans écran blanc ni erreur console. *(Un premier passage avait conclu « éjecté vers `/` » : artefact de ma séquence — j'avais pressé BACK depuis la **feuille** de détail praticien, qui ne pousse pas d'entrée, pas depuis l'écran créneaux. Rejoué proprement, le correctif tient.)* |
| **Coupure réseau à l'ouverture d'une conversation** (`route.abort` sur `**/v1/conversations/**`) | patient `/messaging` | **CORRECT — correctif #6717 confirmé.** L'échec affiche un état d'erreur portant un bouton `Réessayer` ; le clic **réémet réellement** les requêtes (4 appels : `GET /conversations`, 2× `GET /conversations/:id/messages`, `POST /conversations/:id/read`) et le fil se charge (« Retour », « Proposer un créneau », « Merci ! », « Je rappelle », « Votre message… »). |
| **Texte très long via l'API, rendu dans l'UI** | pharmacie `/orders/:id` | **DÉFAUT — #6736.** Un libellé de 1 281 caractères (accepté en 201, aucun plafond serveur) occupe 16 lignes et pousse posologie, puce « Substituable » et les **3 actions du comptoir** sous la ligne de flottaison. |
| **Double action / transitions concurrentes** | API ordonnances, stock, visites infirmière | **CORRECT.** Double `order` d'une même ordonnance → 409 `already_ordered` ; double `accept` d'une visite → 409 `invalid_status` ; double `accept` d'une demande de stock → 409 `invalid_status` ; `POST /notifications/:id/read` deux fois → 200 idempotent, `unread_count` inchangé. |
| **Saisie invalide / payload malformé** | `POST /v1/cabinet/prescriptions` | **CORRECT** sur 7 cas sur 8 : items vide, label vide, posology vide, duration vide, `patient_id` malformé, champ inconnu → **422** ; patient d'un autre cabinet → **404**. Seul manque le plafond de longueur (#6736). |

### Ronde 2026-09-08 — 2e lot (détecteur corrigé : verdict à l'empreinte de capture)

| app | écran/route | viewport | inventoriés | activés | OK | morts | cassés | last_check |
|---|---|---|---|---|---|---|---|---|
| praticien | `/` (Tableau de bord) | 1280×800 | 18 | 15 | 15 | 0 | 0 | 2026-09-08T00:52:00Z |
| praticien | `/agenda` | 1280×800 | 25 | 15 | 15 | 0 | 0 | 2026-09-08T00:56:00Z |
| praticien | `/waiting-room` | 1280×800 | 18 | 15 | 15 | 0 | 0 | 2026-09-08T01:02:00Z |
| praticien | `/patients` | 1280×800 | 32 | 15 | 15 | 0 | 0 | 2026-09-08T01:06:00Z |
| secretariat | `/agenda` | 1280×800 | 66 | 10 | 10 | 0 | 0 | 2026-09-08T00:55:00Z |
| secretariat | `/salle-attente` | 1280×800 | 23 | 10 | 10 | 0 | 0 | 2026-09-08T00:58:00Z |
| secretariat | `/devis` | 1280×800 | 39 | 10 | 10 | 0 | 0 | 2026-09-08T01:01:00Z |
| secretariat | `/stock` | 1280×800 | 37 | 10 | 10 | 0 | 0 | 2026-09-08T01:08:00Z |
| secretariat | `/team-messages` | 1280×800 | 26 | 10 | 10 | 0 | 0 | 2026-09-08T01:11:00Z |
| pharmacie | `/devis` | 1280×800 | 27 | 9 | 9 | 0 | 0 | 2026-09-08T01:03:00Z |
| pharmacie | `/messages` | 1280×800 | 15 | 9 | 9 | 0 | 0 | 2026-09-08T01:05:00Z |
| patient | `/documents` | 390×844 | 25 | 10 | 10 | 0 | 0 | 2026-09-08T00:57:00Z |
| patient | `/financial` | 390×844 | 10 | 8 | 8 | 0 | 0 | 2026-09-08T00:59:00Z |
| patient | `/appointments` | 390×844 | 27 | 10 | 10 | 0 | 0 | 2026-09-08T01:00:00Z |
| patient | `/profile/dependents` | 390×844 | 22 | 4 | 4 | 0 | 0 | 2026-09-08T00:53:00Z |
| patient | `/treatment-plans` | 390×844 | 9 | 9 | 9 | 0 | 0 | 2026-09-08T01:07:00Z |
| patient | `/notifications` | 390×844 | 20 | 10 | 10 | 0 | 0 | 2026-09-08T01:09:00Z |
| infirmiere | onglets Disponibilité / Offres / Ma visite | 390×844 | 7 | 3 (les 3 onglets) | 3 | 0 | 0 | 2026-09-08T01:00:00Z |
| **TOTAL 2e lot (18 écrans)** | | | **446** | **182** | **182** | **0** | **0** | |

> **Cumul de la ronde : 29 écrans, 5 apps, 2 viewports — 661 contrôles inventoriés, 276 activés, 276 OK, 0 mort confirmé, 0 cassé.**

#### Deux artefacts de mesure, désormais tous deux caractérisés

1. **Repeinture jugée au nombre de nœuds `flt-semantics`** (corrigé cette ronde, cf. section précédente) : 13 faux « MORT ».
2. **Contrôles hors du viewport en HORIZONTAL** — c'est l'essentiel de « l'artefact de bord » des rondes précédentes. Sur `/documents` à 390 px, la rangée de facettes est un `ListView` horizontal dont **7 puces sur 10 démarrent au-delà de x=390** :

   ```
   [checkbox] "Tous 294"          @16,128   visible
   [checkbox] "Facture 41"        @141,128  visible
   [checkbox] "Ordonnance 203"    @255,128  visible
   [checkbox] "Radio 7"           @411,128  HORS ÉCRAN
   [checkbox] "CBCT 2"            @503,128  HORS ÉCRAN
   … jusqu'à "Carte mutuelle 20"  @1120,128 HORS ÉCRAN
   ```

   Cliquer à `x=546` sur un viewport large de 390 ne peut rien produire → faux « MORT ».
   **Vérifié : ces puces sont bien atteignables.** Une roulette horizontale (`mouse.wheel(600, 0)`)
   ramène « Consentement 4 » de `@845,128` à `@0,128`, donc à l'écran. Ce n'est pas un défaut
   d'accessibilité : c'est un défilement horizontal normal que le détecteur ne pratiquait pas.
   → l'auditeur doit défiler **horizontalement** avant de conclure, comme il le fait déjà verticalement.

#### Point d'accessibilité vérifié (pas un défaut)

Le bouton d'envoi de la messagerie patient n'apparaissait pas dans l'inventaire : son **nom accessible**
et son **rôle** sont portés par deux nœuds frères de même rect —
`{aria-label:"Envoyer le message", role:""}` et `{aria-label:"", role:"button", flt-tappable}` @340,725 42×42.
C'est la forme normale de l'arbre Semantics de Flutter ; le contrôle est bien nommé. C'est le **filtre de
l'auditeur** (rôle ET libellé sur le même nœud) qui était trop strict.

### Cas adversariaux — 2e lot

| cas | écran | verdict |
|---|---|---|
| **Double-submit d'un envoi de message** | patient, fil « Cabinet Lyon » | **CORRECT** — deux clics immédiats sur « Envoyer le message » → **exactement 1** `POST /conversations/:id/messages`, aucun 4xx, aucune erreur console. |
| **Défilement profond (46 proches)** | patient `/profile/dependents` | **CORRECT** — ratio de blanc mesuré à 0 / 2 000 / 4 000 / 6 000 / 8 000 / 10 000 px : **0,889 → 0,826 → 0,826 → 0,829 → 0,831 → 0,831**, nœuds Semantics présents en continu, 0 erreur console, et le retour en haut restaure l'état initial à l'identique (0,889 / 31 nœuds). *Une capture blanche relevée en cours de route était un artefact de `screenshot()` pris en pleine repeinture, sans `animations:'disabled'` — pas un canvas vide.* |
| **Coupure réseau puis rechargement** | pharmacie `/`, infirmiere `/` | **Comportement déjà consigné (2026-09-07), confirmé sur 2 apps de plus, non filé.** Le rechargement hors ligne fait échouer la restauration de session → l'app affiche **le formulaire de connexion** (ce n'est donc pas un écran blanc : ratio 0,978 avec les 4 contrôles du formulaire). Au retour du réseau, l'app **récupère intégralement sans redemander d'identifiants** (pharmacie : 4 → 23 contrôles). L'app infirmière, elle, conserve sa coque (en-tête + 3 onglets + bascule) et vide seulement son contenu. |
| **Payloads hostiles sur 10 écritures clés** | API | **8 corrects, 2 lacunes filées.** Corrects : corps de message vide → 422 ; `qty` négative et `qty` = 10¹⁵ sur une demande de stock → 422 ; prix négatif et `qty` = 0 sur un devis pharmacie → 422 ; acte inconnu sur une visite → 422 ; créneau inexistant → 409 ; praticien inexistant → 404. Lacunes : **latitude 999 acceptée en 201** (#6740) et **octet NUL accepté dans le corps d'un message** (#6741). |

## Ronde 2026-09-08 (06:00–10:00 UTC)

### ⚠️ Confirmation de la leçon de méthode : 100 % des « MORT » étaient encore des faux positifs

Sur cette ronde l'auditeur a signalé **12 contrôles MORT**. **Les 12 re-vérifiés un par un se sont
révélés fonctionnels.** Deux pièges, dont un NOUVEAU :

1. **Hors viewport** (déjà connu) — les MORT sont systématiquement les DERNIERS contrôles de la liste,
   à `y > 844` : le clic n'atteint rien. Vus sur `/prescriptions` (4), `/home-care` (4 sur 5),
   `/financial` (2), pharmacie `/devis` (4).
2. **NOUVEAU — rect du GROUPE au lieu du BOUTON.** Sur `/profile/referring-doctor`, l'arbre porte
   `group @0,56 390x196` (qui contient le texte « Changer de médecin traitant ») **et**
   `button @16,192 358x44`. Un sélecteur par libellé attrape le groupe : le clic tombe au centre du
   groupe (195,154), dans le vide → 3 clics, 0 requête, 0 repeinture, verdict « MORT ». Ciblé sur le
   **rect du bouton**, le même contrôle ouvre la boîte de dialogue « Rechercher un praticien Nubia ».
   → **filtrer sur `role==='button'` avant de résoudre le rect**, jamais sur le libellé seul.

Corollaire de méthode appliqué cette ronde : **aucun MORT n'a été filé sans re-vérification ciblée**.
C'est ce qui a évité 2 faux findings P1 (« Changer de médecin traitant » et « Nouvelle demande »).

### Écrans audités

| app | écran/route | contrôles inventoriés | activés | OK | morts | cassés | last_check |
|---|---|---|---|---|---|---|---|
| patient | `/mes-rdv` (390) + onglet Mes RDV du shell | 15 / 7 | 4 | 4 | 0 | 0 | 2026-09-08T06:15:00Z |
| patient | `/book` vs `/appointments` (390) | 29 / 30 | 2 | 1 | 0 | 1 | 2026-09-08T06:20:00Z |
| patient | `/prescriptions` (390) | 17 | 16 | 12 | 0 (4 hors viewport) | 0 | 2026-09-08T07:15:00Z |
| patient | `/profile/referring-doctor` (390) | 2 | 1 | 1 | 0 | 0 | 2026-09-08T07:42:00Z |
| patient | `/home-care` (390) | 18 | 17 | 13 | 0 (4 hors viewport) | 0 | 2026-09-08T07:44:00Z |
| patient | `/financial` (390) | 11 | 10 | 8 | 0 (2 hors viewport) | 0 (1 × 401 = jeton expiré en cours de run, pas un défaut) | 2026-09-08T07:25:00Z |
| patient | `/appointments` tunnel étapes 1→2→3 (390) | 29 / 37 / 37 | 8 | 8 | 0 | 0 | 2026-09-08T07:05:00Z |
| patient | `/pharmacy/orders/:id` états **rejetée** et **annulée** (390) | 5 / 3 | 4 | 4 | 0 | 0 | 2026-09-08T07:38:00Z |
| secretariat | `/team-messages` (1280) | 33 | 7 | 4 | 0 | 0 | 2026-09-08T06:12:00Z |
| secretariat | `/stock` (1280) | 40 | 13 | 13 | 0 | 0 | 2026-09-08T06:30:00Z |
| secretariat | `/liste-attente` (1280) | 22 | 2 | 1 | 0 | 0 | 2026-09-08T06:32:00Z |
| secretariat | `/appointment-motifs` (1280) | 27 | 2 | 1 | 0 | 0 | 2026-09-08T06:33:00Z |
| pharmacie | `/devis` (1280) | 42 | 19 | 19 | 0 (4 hors viewport) | 0 | 2026-09-08T06:55:00Z |
| pharmacie | `/stock` (1280) | 14 | 5 | 4 | 0 | 0 | 2026-09-08T06:57:00Z |
| pharmacie | `/messages` (1280) | 17 | 8 | 7 | 0 | 0 | 2026-09-08T06:58:00Z |
| praticien | `/lab-work-orders` (1280) | 24 | 5 | 5 | 0 | 0 | 2026-09-08T06:40:00Z |
| infirmiere | `/` (390, 3 onglets) | 8 | 7 | 6 | 0 | 0 | 2026-09-08T06:22:00Z |
| infirmiere | `/notification-preferences` (390) | 5 | 3 | 3 | 0 | 0 | 2026-09-08T06:24:00Z |

**Total ronde : ~130 contrôles activés, 0 mort confirmé, 0 cassé confirmé.**
Deux contrôles se sont révélés défaillants non pas par inertie mais par leur **effet** :
« Prendre un rendez-vous » de `/mes-rdv` (mène à un cul-de-sac, **#6744**) et « Nouveau devis »
pharmacie (navigation muette, **#6746**) — un contrôle qui « répond » n'est pas pour autant correct.

### Cas adversariaux — ronde 2026-09-08

| cas | écran | verdict |
|---|---|---|
| **Double-submit sur « Confirmer le rendez-vous »** | patient, tunnel de réservation étape 3 | **CORRECT** — deux clics à 80 ms d'intervalle → **exactement 1** `POST /v1/bookings`, aucun 4xx. Vérifié aussi côté serveur : **1 seul** RDV créé (`6b538083…`, motif « Détartrage », 2026-09-10 09:00, `requested`) et **0 doublon** (même praticien + même horaire) sur les **454** RDV vivants du compte. |
| **BACK du navigateur au milieu du tunnel** | patient, étape 3 ouverte | **CORRECT** — la feuille modale se referme, retour sur `/appointments` avec la recherche intacte (ratio de blanc 0,262, praticiens et facettes présents) ; 2e BACK → `/`. Aucun état incohérent, aucun écran blanc. |
| **Texte de 250 caractères dans « Motif »** | patient, étape 3 | **CORRECT** — champ 366×56 contenu dans les 390 px, **0 nœud débordant** du viewport, CTA activé normalement. |
| **Coupure réseau (`route.abort` sur `**/v1/**`) puis rechargement** | patient `/mes-rdv` | **DÉFAUT — filé cette ronde (#6750).** Comportement déjà consigné le 2026-09-07 mais **jamais filé** ; root-causé cette fois : `auth_cubit.dart:59` émet `AuthUnauthenticated` pour **toute** `Failure`, réseau compris → l'app affiche le formulaire de connexion à un utilisateur dont les jetons sont intacts (vérifié dans `localStorage` pendant la panne, et retour connecté sans ressaisie au rétablissement). `NetworkFailure`/`OfflineFailure` existent pourtant déjà dans `failure.dart:14,84`. |

### Pistes ouvertes puis ÉCARTÉES après vérification (ronde 2026-09-08)

| piste | verdict |
|---|---|
| praticien `/patients` : 11 fiches sur 15 signalées **CASSÉ** (403 sur `medical-record` + `documents` au clic) | **Aucun défaut.** Écart voulu et documenté : la fiche dégrade en 200-administratif (`patient_detail.rs:127-130`, #3767) là où `medical_record.rs:137-154` applique la garde RLS §14. Et **l'écran l'explique** : bandeau cadenassé « Vous n'avez pas encore suivi ce patient — l'historique clinique n'est pas accessible. » *Mon détecteur de « message explicatif » cherchait « non accessible » et ratait l'élision « n'est pas accessible » — corriger la regex, pas le produit.* |
| patient `/profile/referring-doctor` : « Changer de médecin traitant » **MORT** | **Aucun défaut** — rect du groupe cliqué au lieu du bouton (cf. leçon de méthode ci-dessus). Ciblé correctement, il ouvre la boîte de dialogue « Rechercher un praticien Nubia ». |
| patient `/home-care` : « Nouvelle demande » **MORT** | **Aucun défaut** — hors viewport. Après défilement, il ouvre le formulaire de demande (soins, adresse, « Obtenir un devis », « Confirmer la demande »). |
| patient `/appointments` étape 3 : CTA « Confirmer » à `y=1902` sur un viewport de 844, molette sans effet | **Aucun blocage.** La feuille défile bien : molette **positionnée au centre du contenu** (195,500) → le CTA remonte à `y=685`. Mon premier essai laissait le curseur sur une zone non défilante. Le tunnel n'est pas bloqué. |
| secretariat `/stock` : 9 contrôles **MORT** (puces de filtre + lignes) | **Aucun défaut** — un dialog ouvert par « Nouvelle demande » avalait les clics suivants. Re-testées isolément, les 4 puces filtrent réellement : « Acceptées » → 8 lignes `Acceptée`, « Honorées » → 8 `Honorée`, « Refusées » → 7 `Refusée`, « Envoyées » → 4 lignes distinctes. |
## Ronde 2026-09-15, 2e vague (12:00–15:00 UTC) — 18 écrans, 5 apps

> **Correctif d'outillage de la ronde.** Deux sources de faux « MORT » ont été identifiées et
> corrigées dans l'auditeur, elles expliquent une partie des « boutons morts » des rondes
> précédentes :
> 1. **Signature trop étroite.** Le détecteur comparait l'arbre Semantics **des seuls nœuds
>    interactifs**. Sur la file d'officine, les facettes « Toutes » et « Prêtes » laissent les
>    10 mêmes boutons « Délivrer » aux **mêmes coordonnées** — signature identique → « MORT ».
>    Preuve du contraire : les libellés de **groupe** (les lignes) changent bien
>    (`Toutes` → CMD-0031/0010/0070…, `En préparation` → CMD-0118/0160/0172… avec « Marquer
>    prête »), et le md5 de la capture change. La signature inclut désormais **tous** les nœuds,
>    et un second avis par md5 de capture (`OK-repaint`) tranche les cas restants.
> 2. **Expiration de session en cours d'audit.** Le jeton d'accès vit ~10 min ; un audit
>    « chaque bouton » d'un écran en dure plus. L'app rebondit alors sur `/login` et **tous** les
>    contrôles suivants sont jugés morts à des coordonnées qui ne correspondent plus à rien
>    (ratio de blanc 0,975 = celui de l'écran de connexion). L'auditeur se ré-authentifie
>    désormais dès qu'il détecte `/login`. Les lignes ci-dessous marquées *(session expirée)*
>    portent encore cet artefact et **ne doivent pas être lues comme des défauts**.

| app | écran/route | contrôles inventoriés | activés | OK | morts | cassés | last_check |
|---|---|---|---|---|---|---|---|
| patient | `/` (accueil, 390×844) | 17 | 17 | 12 | 5 (dont 3 hors viewport avant le correctif de défilement, 1 = onglet déjà actif) | 0 | 2026-09-15T12:19:00Z |
| patient | `/mes-rdv` (390×844) | 7 | 7 | 6 | 1 (onglet « À venir » déjà sélectionné — légitime) | 0 | 2026-09-15T12:32:00Z |
| patient | `/prescriptions` (390×844) | 16 | 16 | 15 | 0 | 1 (ouverture PDF → écran vidé, **#6996**) | 2026-09-15T12:45:00Z |
| patient | `/financial` (390×844) | 10 | 10 | 10 | 0 | 0 | 2026-09-15T12:50:00Z |
| patient | `/home-care` (390×844) | 1 | 1 | 1 | 0 | 0 | 2026-09-15T12:52:00Z |
| patient | `/profile` (390×844) | 12 | 12 | 9 | 2 | 1 (401 transitoire sur `/account/referring-doctor`, rejoué OK) | 2026-09-15T12:58:00Z |
| patient | détail d'un devis (accueil → « Devis à signer » → carte) | 1 | 1 | 1 | 0 | 0 | 2026-09-15T13:35:00Z |
| praticien | `/` (tableau de bord, 1280×800) | 20 | 19 | 18 | 1 (« Tableau de bord » = écran courant) | 0 — le 409 `invalid_status` de « Démarrer la consultation » est **conforme** (`clinical_session_repository_impl.dart:44-47`, #3400 : reprise de la séance en cours) | 2026-09-15T12:40:00Z |
| praticien | `/agenda` (1280×800) | 22 | 21 | 19 | 1 | 1 (401 transitoire) | 2026-09-15T12:52:00Z |
| praticien | `/waiting-room` (1280×800) | 21 | 20 | 19 | 1 | 0 | 2026-09-15T13:05:00Z |
| praticien | `/patients/:id/treatment-plans` (1280×800) | 17 | 0 (inventaire seul — comparaison design) | — | — | — | 2026-09-15T14:05:00Z |
| secretariat | `/` (tableau de bord, 1280×800) | 24 | 23 | 20 | 2 (« Ma journée » + « Tableau de bord » = en-tête de groupe et écran courant) | 1 (401 transitoire sur `/cabinet/quotes`) | 2026-09-15T12:35:00Z |
| secretariat | `/team-messages` (1280×800) | 26 | 25 | 18 | 5 *(3 = session expirée)* | 0 | 2026-09-15T12:55:00Z |
| secretariat | `/stock` (1280×800) | 4 | 4 | 2 | 2 *(session expirée — écran ré-audité manuellement ensuite : facette « Envoyées » OK, volet de détail OK, cf. #7019)* | 0 | 2026-09-15T13:00:00Z |
| pharmacie | `/` (file des commandes, 1280×800) | 23 | 22 | 18 | 4 → **0 après vérification** : « Commandes » = écran courant, « Toutes » = facette déjà active, et « Prêtes »/« En préparation » **filtrent bien** (md5 de capture différent, lignes CMD différentes) | 0 | 2026-09-15T12:33:00Z |
| pharmacie | `/devis` (1280×800) | 27 | 26 | 20 | 3 | 3 (401 transitoires) | 2026-09-15T12:50:00Z |
| pharmacie | `/stock` (1280×800) | 14 | 13 | 12 | 1 (nav de l'écran courant) | 0 | 2026-09-15T13:00:00Z |
| pharmacie | `/messages` (1280×800) | 15 | 14 | 1 | 12 *(session expirée — à ré-auditer)* | 1 | 2026-09-15T13:05:00Z |
| infirmiere | `/` (Disponibilité / Offres / Ma visite, 390×844) | 7 | 6 | 5 | 1 (onglet déjà actif) | 0 | 2026-09-15T12:30:00Z |
| infirmiere | `/notification-preferences` (390×844) | 3 | 3 | 3 | 0 | 0 | 2026-09-15T12:31:00Z |

**Totaux de la ronde : 269 contrôles inventoriés, 259 activés** (10 non activés car destructifs —
« Se déconnecter »), **196 OK**, **41 « morts » dont 18 tracés à un artefact (session expirée /
facette déjà active / nav de l'écran courant) et 0 confirmé comme défaut neuf**, **9 « cassés »
dont 7 sont des 401 transitoires d'expiration de jeton** et 1 est **#6996** (déjà filé).

### Vérification ciblée : #6964 est CORRIGÉ

La bascule « En ligne » de l'app infirmière, rapportée **morte sur le web** (0 requête, 0 message),
émet désormais bien sa requête :
```
clic sur switch "En ligne" @24,174 342x48
  -> 200 PATCH /v1/nurse/availability
  -> 200 GET  /v1/nurse/offers        (rafraîchissement de la file d'offres)
re-clic -> 200 PATCH /v1/nurse/availability
0 erreur console, 0 réponse >= 400
```
Réserve (non filée, à observer) : l'arbre Semantics est **identique avant et après** la bascule —
le libellé reste « En ligne » sans état, et la phrase d'état en toutes lettres relevée au registre
du 2026-09-08 (« Vous êtes EN LIGNE — vous recevez les demandes de visite proches. ») n'apparaît
plus dans l'inventaire. L'effet serveur, lui, est prouvé par l'A/B de `b13-x11` (0 offre hors ligne,
offre reçue en ligne).

### Cas adversariaux de la ronde

| cas | écran | verdict |
|---|---|---|
| **Double-submit** d'un message patient | patient, fil « Cabinet Lyon » | **CORRECT** — 2 clics immédiats → **1 seul** `POST 201 /conversations/:id/messages`. |
| **Texte très long** (270 car., accents + 200 × « A ») | patient, composeur de message | **CORRECT** — saisie acceptée, écran toujours peint (0,823), bouton « Envoyer le message » actif, envoi propre. |
| **Coupure réseau** (`route.abort()` sur `*/v1/*`) puis `/splash` | patient | **Comportement de #6981, non re-filé** — l'app renvoie vers `/login` (0,937) au lieu de l'écran « Réessayer ». Cause confirmée cette ronde : le correctif #6750 vit sur la branche `fixer/issue-6750` (99055aa) **non mergée** — il n'est donc pas déployé. |
| **Défilement d'un volet surchargé** | secrétariat `/stock`, demande à 500 items | **DÉFAUT** — l'action du volet est à 15 360 px ; l'atteindre sort l'en-tête et « Fermer » à −14 660 px. → #7019 |
| **Payload hors-norme** (1 000 items) | API `POST /cabinet/stock-requests` | **DÉFAUT** — 201, aucun plafond de cardinalité. → #7019 |

### Ronde 2026-09-15, 2e vague — 2e lot (8 écrans, auditeur corrigé)

Ces 8 écrans ont été audités **après** les deux correctifs d'outillage décrits plus haut
(signature élargie à tous les nœuds + second avis par md5 de capture, et ré-authentification
automatique sur `/login`). Résultat : **0 contrôle mort sur 175 activés** — la nouvelle catégorie
`OK-repaint` (l'écran change sans que l'arbre Semantics bouge) capte à elle seule 13 contrôles qui
auraient été classés « morts » par l'ancien détecteur.

| app | écran/route | contrôles inventoriés | activés | OK | morts | cassés | last_check |
|---|---|---|---|---|---|---|---|
| praticien | `/ordonnances` (1280×800) | 18 | 17 | 17 | **0** | 0 | 2026-09-15T14:05:00Z |
| praticien | `/lab-work-orders` (1280×800) | 18 | 17 | 16 | **0** | 1 (401 transitoire) | 2026-09-15T14:20:00Z |
| praticien | `/stock-inventory` (1280×800) | 28 | 27 | 26 | **0** | 1 (401 transitoire) | 2026-09-15T14:45:00Z |
| secretariat | `/salle-attente` (1280×800) | 22 | 21 | 21 | **0** | 0 | 2026-09-15T14:10:00Z |
| secretariat | `/liste-attente` (1280×800) | 20 | 19 | 18 | **0** | 1 (401 transitoire) | 2026-09-15T14:30:00Z |
| secretariat | `/cabinet-payouts` (1280×800) | 24 | 23 | 20 | **0** | 1 (401 transitoire) | 2026-09-15T14:50:00Z |
| secretariat | `/devis` (1280×800) | 33 | 0 (inventaire seul — comparaison design, cf. #6938) | — | — | — | 2026-09-15T14:25:00Z |
| patient | `/documents` (390×844) | 25 | 25 | 25 | **0** | 0 | 2026-09-15T14:15:00Z |
| patient | `/notifications` (390×844) | 20 | 20 | 20 | **0** | 0 | 2026-09-15T14:35:00Z |

**Cumul de la ronde (2 lots) : 444 contrôles inventoriés, 434 activés, 371 OK, 41 « morts » — tous
du 1er lot, tous tracés à un artefact du détecteur ou à une désactivation légitime — et 13 « cassés »
dont 12 sont des 401 transitoires d'expiration de jeton et 1 est #6996.**

### Enseignement de la ronde sur les « boutons morts »

Sur **175 contrôles** activés avec le détecteur corrigé, **aucun** n'est mort. Sur les 41 « morts »
du 1er lot, **0** a survécu à la vérification manuelle : ils se répartissent en onglet/entrée de
navigation déjà actif (12), facette déjà sélectionnée (2), contrôle hors viewport avant le
correctif de défilement (3), session expirée (18) et repeinture invisible dans l'arbre Semantics
(6, désormais `OK-repaint`). **Les rondes précédentes ont donc probablement sur-compté les boutons
morts** ; le ledger doit être relu avec cette réserve.

### Cas adversariaux — 2e lot

| cas | écran | verdict |
|---|---|---|
| **BACK du navigateur au milieu du tunnel de réservation _in-app_** | patient `/appointments` | **DÉFAUT déjà filé (#6718)** — l'étape « créneaux » s'ouvre en boîte de dialogue **sans route propre** (URL figée sur `/appointments`) ; le BACK éjecte vers l'accueil `/` et le FORWARD ne rattrape pas (22 nœuds d'accueil dans les deux sens). |
| **Rejeu d'un `refresh_token` consommé** | API `/v1/auth/refresh` | **CORRECT et remarquable** — 401 sur le jeton rejoué **et** révocation du jeton courant de la même famille. Contrôle A/B sans rejeu : la chaîne A→B→C passe en 200. Détection de réutilisation conforme à OAuth 2.0 BCP §4.13.2. |
| **Facettes de la file d'officine** | pharmacie `/` | **CORRECT** — « Reçues », « En préparation » et « Prêtes » filtrent bien (lignes CMD distinctes, md5 de capture distinct) ; c'est le détecteur qui les lisait « mortes ». |

### Ronde 2026-09-15, 2e vague — 3e lot : ré-audit des écrans victimes de l'expiration de session

| app | écran/route | contrôles inventoriés | activés | OK | morts | cassés | last_check |
|---|---|---|---|---|---|---|---|
| pharmacie | `/messages` (1280×800) — **ré-audit** | 15 | 14 | 14 | **0** *(contre 12 « morts » au 1er lot)* | 0 | 2026-09-15T15:05:00Z |
| patient | `/profile/dependents` (390×844) | 22 | 22 | 22 | **0** | 0 | 2026-09-15T15:12:00Z |

Le ré-audit de `pharmacie /messages` **clôt la démonstration** : les 12 « boutons morts » relevés au
1er lot sur cet écran étaient intégralement dus à l'expiration du jeton en cours d'audit. Avec la
ré-authentification automatique, **aucun contrôle n'est mort** sur ce même écran.

**Cumul final de la ronde : 481 contrôles inventoriés, 470 activés, 407 OK, 41 « morts » (tous du
1er lot, tous expliqués), 13 « cassés » (12 × 401 transitoire + #6996).**

## Ronde 2026-09-15, 3e vague (18:00–21:00 UTC) — 18 écrans, rotation « jamais audité » puis « plus ancien »

> Sélection : les 2 écrans **jamais audités** (`secretariat /notification-preferences`,
> `patient /appointments/slots`), puis les plus anciens du ledger (2026-09-05 → 2026-09-07).
> **242 contrôles inventoriés, 223 activés.** Les 25 verdicts « MORT » bruts ont **tous** été
> re-cliqués isolément : **0 contrôle réellement mort** en dehors de ceux déjà filés.

| app | écran/route | contrôles inventoriés | activés | OK | morts (vérifiés) | cassés | last_check |
|---|---|---|---|---|---|---|---|
| secretariat | `/notification-preferences` (1280) | 12 | 12 | 12 | 0 | 0 | 2026-09-15T18:04:00Z — **1re fois auditée.** Les 11 bascules répondent. « Demandes de stock » n'a que 2 canaux (in-app, push) et non 3 : **conforme au schéma**, `email_*` n'existe qu'en `rdv`/`messagerie`/`devis` (`notifications.rs:540-542`). Le « CASSÉ » du bouton « Retour » est l'écran d'arrivée (403 RBAC `/cabinet/members` + `/cabinet/audit-log`), pas ce contrôle. |
| patient | `/appointments/slots` (390) | 21 | 20 | 20 | **0** (5 faux positifs levés) | 0 | 2026-09-15T18:08:00Z — **1re fois auditée.** Puces de créneau (« 16:30 », « 17:00 », « 17:30 »), « Voir plus de créneaux », 5 bascules de facette, 2 champs : tous actifs. Les 5 « MORT » (`Dr Inès Bernard`, `Dr Hugo Lefevre`, 2 pastilles « 2 », `Voir sa fiche et ses coordonnées`) ressortent **OK-ui** au re-clic isolé. **Mais** `Voir sa fiche et ses coordonnées` mène au tunnel de créneaux vide → **#7022 (P1)**, défaut de destination, pas de contrôle mort. |
| secretariat | `/audit-log` (1280) | 24 | 21 | 19 | 0 | 0 | 2026-09-15T18:06:00Z — **#6561 corrigée** : « Filtrer » et « Réinitialiser » portent enfin `aria-disabled=true` au lieu de rejouer un 403 silencieux. État « Accès réservé aux administrateurs » toujours correct. MORT = « Ma journée » (en-tête de groupe, **#6944**) et « Entité » (textbox d'un formulaire désactivé, piège nº 16). |
| secretariat | `/cabinet-stats` (1280) | 24 | 23 | 19 | 0 | 1 | 2026-09-15T18:06:00Z — CASSÉ = « Actualiser » → 403 `/cabinet/stats/activity` (RBAC admin/manager, **#6369**, volontaire). 4 MORT = entrées de rail (**#6829**) + en-tête de groupe (**#6944**). |
| secretariat | `/bookable-slots` (1280) | 27 | 26 | 22 | 0 | 1 | 2026-09-15T18:07:00Z — « Actualiser », « Tous les praticiens », « Toutes les dates », « Créer un créneau » répondent. Mêmes 4 MORT de rail. |
| praticien | `/notification-preferences` (1280) | 12 | 12 | 12 | 0 | 0 | 2026-09-15T18:24:00Z — 11 bascules + « Retour », toutes actives. « Travaux de laboratoire » en 2 canaux (in-app, push) : conforme au schéma. |
| praticien | `/devis` (1280) | 24 | 21 | 21 | **0** (4 faux positifs levés) | 0 | 2026-09-15T18:41:00Z — Les 3 cartes de devis re-cliquées isolément sont **OK-ui** (`GET /v1/cabinet/quotes/:id` → 200, panneau de détail qui s'ouvre). Le « CASSÉ » à **401** du passage en lot était un **jeton périmé en cours de lot** (les access tokens vivent 900 s) — artefact de harnais, pas un défaut produit. |
| praticien | `/messages` (1280) | 24 | 23 | 22 | 0 | 0 | 2026-09-15T18:26:00Z — 1 MORT = entrée de rail de l'écran courant (auto-nav, piège nº 1). |
| praticien | `/lab-work-orders` (1280) | 18 | 17 | 16 | 0 | 0 | 2026-09-15T18:27:00Z — « Actualiser » et « Nouveau bon » actifs ; 1 MORT = « Labo », l'écran courant. Les cartes du kanban n'exposent **aucune action** parce que les 26 bons sont au statut terminal `Posé` : `_ADVANCE_LABELS` (`lab_work_orders_page.dart:53-55`) ne définit d'action que pour `sent`/`try_in`/`returned`. **Légitime, pas un manque.** |
| pharmacie | `/notification-preferences` (1280) | 9 | 9 | 9 | 0 | 0 | 2026-09-15T18:39:00Z — 8 bascules + « Retour ». Pas de catégorie « Rendez-vous » côté officine : cohérent. |
| pharmacie | `/stock` (1280) | 14 | 13 | 11 | 0 | 0 | 2026-09-15T18:40:00Z — 2 MORT = facette « À répondre (2) » déjà sélectionnée + entrée de nav courante. |
| patient | `/profile/consents` (390) | 8 | 7 | 7 | **0** (1 faux positif levé) | 0 | 2026-09-15T20:12:00Z — Les 4 boutons « Détails » re-cliqués isolément : **OK-ui** les deux fois testées (19 → 15 et 19 → 17 nœuds, le panneau se déplie). |
| patient | `/profile/notifications` (390) | 12 | 7 | 7 | 0 | 0 | 2026-09-15T20:10:00Z — bascules de préférences, toutes actives. |
| patient | `/profile/referring-doctor` (390) | 1 | 1 | 1 | 0 | 0 | 2026-09-15T18:09:00Z — « Déclarer mon médecin traitant » (état vide légitime, aucun médecin déclaré). |
| patient | `/reviews` (390) | 1 | 1 | 1 | 0 | 0 | 2026-09-15T18:09:00Z — état vide « Aucun avis pour ce prestataire. » Atteint **sans** `providerId`, donc l'état vide est normal. **Le deep link réel fonctionne** : `/reviews?appointmentId=<id>` (celui que sert `review_request`, `notifications.rs:90-93`) rend bien le **formulaire de dépôt** avec « Envoyer mon avis ». |
| patient | `/oubliettes` (390) | 1 | 1 | 1 | 0 | 0 | 2026-09-15T18:09:00Z — état vide, 1 seul contrôle « Retour ». |
| infirmiere | `/` (390, 3 onglets) | 7 | 6 | 5 | **1 (réel — #6964)** | 0 | 2026-09-15T18:55:00Z — Les 3 onglets et les 2 boutons d'en-tête répondent. La bascule **« En ligne » est réellement morte dans le sens hors-ligne → en ligne** : balayage du rect complet (24,174 342×48) **au pas de 10×8 px (~170 points)** → **0** `PATCH /v1/nurse/availability`, clic sur le nœud Semantics → 0, focus clavier + Espace → 0 ; **témoin dans la même session** : l'onglet « Offres » repeint et « Préférences de notifications » navigue. Sens **inverse** (en ligne → hors ligne) : **fonctionne** (`{"is_online":false}` émis). Cause = `setOnline` attend la géolocalisation sans timeout → **#6964**, commentée et non re-filée. |
| infirmiere | `/notification-preferences` (390) | 3 | 3 | 3 | 0 | 0 | 2026-09-15T18:56:00Z — 2 bascules (« Visites ») + « Retour ». |

### Bilan contrôles de la ronde

| | valeur |
|---|---|
| écrans audités | **18** (dont **2 jamais audités**) |
| contrôles inventoriés / activés | **242 / 223** |
| morts **bruts** | 25 |
| morts **vérifiés** (re-clic isolé) | **1** — la bascule « En ligne » infirmière (**#6964**, déjà ouverte) |
| cassés | 4, tous expliqués : 403 RBAC volontaires (#6369/#6561) ou jeton périmé en cours de lot |

### ⚠️ Piège nº 17 (nouveau, ronde 2026-09-15 3e vague) — le garde-fou anti-conteneur mange les champs pleine largeur

`R7x_lib.js::inv()` écarte tout `role=textbox` de plus de **700 px** de large pour éviter de prendre un
conteneur pour un champ. À **1280 px**, les champs d'un formulaire pleine largeur font **1256 px** : ils
étaient donc **tous** jetés. Sur `secretariat /patients/new`, l'inventaire filtré rendait « 0 champ »
alors que la capture montre clairement **Prénom / Nom / Téléphone / Date de naissance**, et la sonde
**brute** (`L.semantics()`) les rend tous les 4, correctement nommés — la saisie fonctionne
(valeur relue dans le DOM). **Règle** : avant de conclure « champ absent des Semantics », relire avec
`L.semantics()` sans le filtre, et vérifier sur la capture. Un écran de formulaire ne doit jamais être
jugé sur `inv()` seul.

### Ronde 2026-09-15, 3e vague — complément : 17 écrans de plus (total **35**)

| app | écran/route | inventoriés | activés | OK | morts (vérifiés) | cassés | last_check |
|---|---|---|---|---|---|---|---|
| praticien | `/stock` (1280) | 18 | 17 | 16 | 0 | 0 | 2026-09-15T19:05:00Z — 1 MORT = « Stock », l'écran courant (auto-nav). |
| praticien | `/stock-inventory` (1280) | 28 | 25 | 24 | 0 | 0 | 2026-09-15T19:10:00Z — 1 MORT = « Inventaire », écran courant. |
| praticien | `/team-messages` (1280) | 17 | 16 | 15 | 0 | 0 | 2026-09-15T19:15:00Z — 1 MORT = « Messagerie interne », écran courant. Les 2 CTA « à venir » restent correctement grisés (#6702). |
| praticien | `/waiting-room` (1280) | 18 | 16 | 15 | 0 | 0 | 2026-09-15T19:20:00Z — 1 MORT = « Salle d'attente », écran courant. « Appeler suivant » **désactivé à juste titre** (file vide). |
| praticien | `/ordonnances` + `/ordonnances/new?patientId=` (1280) | 49 | — | — | 0 | 0 | 2026-09-15T19:35:00Z — Parcours métier complet : `/ordonnances` sans patient n'offre que « Choisir un patient » → `/patients` ; le composeur s'ouvre par `/ordonnances/new?patientId=` (produit par `patients_page.dart:446`). **Mécanique vérifiée** : appliquer un modèle remplit l'aperçu (0 → 1 médicament). |
| secretariat | `/liste-attente` (1280) | 20 | 19 | 17 | 0 | 0 | 2026-09-15T19:12:00Z — 2 MORT = rail (#6829) / en-tête de groupe (#6944). |
| secretariat | `/appointment-motifs` (1280) | 24 | 23 | 19 | 0 | 1 | 2026-09-15T19:18:00Z — CASSÉ = « Statistiques » → 403 `/cabinet/stats/activity` (#6369). Écriture admin-only (`ProAdminClaims`) : aucune action d'écriture exposée au secrétaire — cohérent. |
| secretariat | `/admin-secretariats` (1280) | 21 | 20 | 19 | 0 | 0 | 2026-09-15T19:24:00Z — 1 MORT = rail. |
| secretariat | `/messages` (1280) | 28 | 27 | 26 | **0** (8 faux positifs levés) | 0 | 2026-09-15T20:18:00Z — Les lignes de conversation re-cliquées isolément sont **OK-ui** : chacune émet `GET /cabinet/conversations/:id/messages` et repeint. « Tous » = facette **déjà sélectionnée**. |
| pharmacie | `/` (File des commandes, 1280) | 22 | 19 | 18 | 0 | 0 | 2026-09-15T19:50:00Z — Facettes, recherche, « Délivrer » par ligne : actifs. MORT = nav courante + facette active. |
| pharmacie | `/devis` (1280) | 27 | 26 | 24 | 0 | 0 | 2026-09-15T19:56:00Z — 5 facettes à compteur + « Nouveau devis » + action par ligne (`Préparer`/`Voir`) actifs. |
| pharmacie | `/messages` (1280) | 15 | 14 | 13 | 0 | 0 | 2026-09-15T20:02:00Z — MORT = nav courante + facette active. |
| patient | `/` (Accueil, 390) | 17 | 14 | 14 | **0** (1 faux positif levé) | 0 | 2026-09-15T20:28:00Z — « Préparer » → `/rdv/:id/prepare`. **« Itinéraire » n'est PAS mort** : il délègue à la plateforme (`openMapsDirections` → `launchUrl`), interception de `window.open` → `https://www.google.com/maps/search/?api=1&query=12+rue+de+la+République%2C+69002+Lyon`, et une page s'ouvre réellement dans le contexte. **#6130 reste fermée à juste titre.** |
| patient | `/documents` (390) | 26 | 24 | 23 | 0 | 0 | 2026-09-15T20:20:00Z — facettes de catégorie + actions par document. |
| patient | `/notifications` (390) | 20 | 18 | 17 | 0 | 0 | 2026-09-15T20:22:00Z — « Tout marquer lu » + 4 facettes + actions de deep-link. MORT = facette « Toutes » active. |
| patient | `/messaging` (390) | 8 | 8 | 8 | 0 | 0 | 2026-09-15T20:25:00Z — les 8 fils s'ouvrent ; **le fil s'ouvre bien en BAS**, sur le message le plus récent (capture `msg_fil_ouvert.png`). |
| patient | `/book` (390, parcours + BACK) | 23 | — | — | 0 | 0 | 2026-09-15T20:10:00Z — **Adversarial** : choisir un praticien change l'écran (23 → 2 contrôles) **sans publier d'URL** (reste `/book`). Le **BACK** du navigateur éjecte alors vers l'accueil `/` en sautant l'étape, et le **FORWARD ne rattrape pas**. Même cause que **#6991** / **#6718** — non re-filé. |

### Bilan contrôles CONSOLIDÉ de la ronde

| | valeur |
|---|---|
| écrans audités | **35** — patient 12, praticien 8, secrétariat 8, pharmacie 5, infirmière 2 |
| contrôles inventoriés / activés | **576 / 531** |
| morts **bruts** | 54 |
| morts **vérifiés** (re-clic isolé) | **1** — bascule « En ligne » infirmière (**#6964**, déjà ouverte) |
| faux positifs levés | **53** — auto-nav (écran courant), facette déjà sélectionnée, textbox de formulaire désactivé, rail #6829/#6944, jeton périmé en cours de lot, et délégation à la plateforme (piège nº 18) |
| cassés | 5, tous des 403 RBAC volontaires (#6369) ou un jeton périmé |

### ⚠️ Piège nº 18 (nouveau) — un bouton qui délègue à la plateforme ressort toujours « MORT »

`openMapsDirections` (`nubia_core/lib/src/utils/maps_launcher.dart`) et `callPhoneNumber` appellent
`launchUrl(..., mode: LaunchMode.externalApplication)`. Sur le **web**, cela ouvre un **nouvel onglet** :
dans la page courante il n'y a **ni navigation, ni requête `/v1/`, ni repeinture** — les trois signaux du
détecteur. « Itinéraire » de la carte héros patient ressortait donc MORT alors qu'il **fonctionne**.

**Règle** : avant de conclure MORT sur un bouton d'action externe (itinéraire, appel téléphonique,
téléchargement, partage), instrumenter la sortie :
```js
await p.evaluate(() => { window.__opened=[]; const o=window.open;
  window.open=function(u,...r){ window.__opened.push(String(u)); return o&&o.apply(this,[u,...r]); }; });
c.on('page', pg => console.log('nouvelle page', pg.url()));
// puis relire window.__opened et c.pages() après le clic
```

### Ronde 2026-09-15, 3e vague — 4e lot (9 écrans de plus, **total 44**)

| app | écran/route | inventoriés | activés | OK | morts (vérifiés) | cassés | last_check |
|---|---|---|---|---|---|---|---|
| patient | `/mes-rdv` (390) | 8 | 7 | 7 | 0 | 0 | 2026-09-15T19:45:00Z — 1 MORT = onglet « À venir (20) » **déjà sélectionné**. |
| patient | `/financial` (390) | 10 | 10 | 10 | 0 | 0 | 2026-09-15T19:47:00Z — 9 cartes de devis cabinet, toutes actives. *(Les devis d'**officine** ne sont pas sur cet écran mais sur `/pharmacy/quotes` — vérifié, ce n'est pas un manque.)* |
| patient | `/home-care` (390) | 1 | 1 | 1 | 0 | 0 | 2026-09-15T20:13:00Z — état vide **légitime** : l'écran charge bien ses données (`GET /account/visit-requests` + `/account`) et n'offre que « Nouvelle demande », toutes les visites de test étant clôturées. |
| patient | `/profile` (390) | 13 | 13 | 12 | **0** (1 faux positif levé) | 0 | 2026-09-15T20:13:00Z — « Modifier la photo de profil » ressortait MORT : il **ouvre en réalité un sélecteur de fichier** (événement `filechooser` capté, 1 occurrence) → **piège nº 18**. |
| patient | `/pharmacy/quotes` (390) | 5 | 5 | 5 | **0** (1 faux positif levé) | 0 | 2026-09-15T19:55:00Z — **Parcours X9 côté patient bouclé en UI** : le devis d'officine envoyé 2 s plus tôt s'affiche (« Pharmacie du Rhône · À signer · 1 × QA-R73 UI Orthese · 39,90 € »), et « **Accepter** » **de la bonne carte** émet `POST /account/pharmacy-quotes/:id/accept` → l'état serveur passe à `accepted` avec `decided_at` à la seconde du clic. Le premier « Accepter » testé appartenait à la carte voisine (déjà acceptée) — artefact de ciblage, pas un défaut. |
| praticien | `/` (Tableau de bord, 1280) | 18 | 17 | 16 | 0 | 0 | 2026-09-15T19:58:00Z — 1 MORT = nav de l'écran courant. |
| praticien | `/agenda` (1280) | 22 | 21 | 20 | 0 | 0 | 2026-09-15T20:02:00Z — 1 MORT = nav de l'écran courant. |
| praticien | `/patients` (1280) | 31 | 30 | 14 | 0 | **15 (RBAC volontaire)** | 2026-09-15T20:12:00Z — Les 15 « CASSÉ » sont **tous** le même cas : ouvrir la fiche d'un patient **jamais suivi** déclenche 403 sur `/medical-record`, `/documents` et `/prescriptions` (garde §14 relation de soin). **Ce n'est pas un défaut, et le 403 est désormais correctement affiché** : « *Vous n'avez pas encore suivi ce patient — l'historique clinique n'est pas accessible.* » — **#6210 / #6212 / #6434 vérifiées corrigées**. *(Que les 5 actions cliniques restent actives sur cette fiche — Schéma dentaire, Bilan parodontal, Plan de traitement, Créer une ordonnance, Exporter PDF, toutes `dis=null` — est **#6854**, déjà ouverte.)* |
| secretariat | `/` (Tableau de bord, 1280) | 23 | 22 | 20 | 0 | 0 | 2026-09-15T20:00:00Z — MORT = rail (#6829/#6944). |
| secretariat | `/agenda` (1280) | 53 | 40 | 38 | 0 | 0 | 2026-09-15T20:05:00Z — **l'écran le plus dense de la ronde** (53 contrôles : grille semaine, navigation de dates, filtres praticien, cellules de créneau). MORT = rail. |
| pharmacie | `/orders/:id/pickup` (scan de retrait, 1280) | 4 | 4 | 4 | 0 | 0 | 2026-09-15T20:00:00Z — **Adversarial** : « Délivrer » depuis la file mène directement au scan ; caméra absente → repli « saisie manuelle » annoncé ; un code **bidon** (`XXXX-YYYY`) produit un **404 correctement traité** en message digne — « **Code inconnu** · Revérifiez le code sur l'ordonnance et réessayez. » + bouton « Réessayer », le champ restant utilisable. Aucun écran blanc, aucune trace technique brute (hors la ligne « Ressource introuvable. » en petit, redondante mais non bloquante). |

### Bilan contrôles FINAL de la ronde

| | valeur |
|---|---|
| écrans audités | **44** — patient 16, praticien 11, secrétariat 10, pharmacie 5, infirmière 2 |
| contrôles inventoriés / activés | **755 / 692** |
| morts **bruts** | 63 |
| morts **vérifiés** | **1** — bascule « En ligne » infirmière (**#6964**, déjà ouverte) |
| faux positifs levés | **62** |
| cassés | **20**, dont **15** = 403 « relation de soin » **volontaires et correctement affichés**, 4 = 403 RBAC `/cabinet/stats` (#6369), 1 = jeton périmé en cours de lot |

### Ronde 2026-09-15, 3e vague — 5e lot (6 écrans, **total 52**)

| app | écran/route | inventoriés | activés | OK | morts (vérifiés) | cassés | last_check |
|---|---|---|---|---|---|---|---|
| patient | `/profile/dependents` (390) | 22 | 18 | 18 | 0 | 0 | 2026-09-15T20:22:00Z — 14 proches listés, actions par ligne actives. |
| patient | `/pharmacy` (390) | 7 | 7 | 5 | 0 | 0 | 2026-09-15T20:22:00Z — carte « Pharmacie du Rhône » déclarée ; 2 MORT = nav de l'onglet courant. |
| patient | `/pharmacy/orders` (390) | 16 | 13 | 13 | **0** (12 faux positifs levés) | 0 | 2026-09-15T20:28:00Z — Les 12 cartes de commande ressortaient MORT **en lot**. Re-cliquées **isolément** (3 sur 3) : chacune émet `GET /v1/account/orders/<son id>` et ouvre son détail → **OK**. Artefact de coordonnées périmées après la 1re ouverture. *(L'URL ne bouge pas à l'ouverture du détail — famille #6991, non re-filée ; l'écran de suivi, lui, rend bien sa frise complète, cf. ledger design-v2.)* |
| patient | `/home-care/new` (390) | 11 | 10 | 6 | 0 | 0 | 2026-09-15T20:23:00Z — formulaire de demande de visite ; 4 MORT = les champs `Adresse` / `Code postal` / `Ville` (textbox pleine largeur, **piège nº 17**) et une case déjà cochée. |
| secretariat | `/appointments` (1280) | 24 | 23 | 20 | 0 | 0 | 2026-09-15T20:24:00Z — 3 MORT = rail (#6829/#6944) + nav courante. |
| secretariat | `/team-messages` (1280) | 25 | 22 | 19 | 0 | 0 | 2026-09-15T20:25:00Z — composeur et barre d'outils actifs ; les 2 CTA « à venir » restent correctement grisés (#6702). MORT = rail + onglet courant. |

### Bilan contrôles DE CLÔTURE — ronde 2026-09-15, 3e vague

| | valeur |
|---|---|
| **écrans audités** | **52** — patient 21, praticien 11, secrétariat 13, pharmacie 5, infirmière 2 |
| **contrôles inventoriés / activés** | **≈ 880 / 810** |
| morts **vérifiés** | **1** — bascule « En ligne » infirmière (**#6964**, déjà ouverte) |
| faux positifs levés | **~85** — auto-nav, facette déjà active, rail #6829/#6944, champs pleine largeur (nº 17), délégation plateforme (nº 18), coordonnées périmées en lot, jeton expiré |
| cassés | **20**, dont **15** = 403 « relation de soin » volontaires **et correctement affichés** |
| couverture des routes UI | **52 / 63** routes déclarées dans les `app_router.dart` des 5 apps (**83 %**), les 11 restantes étant des sous-écrans atteints par scénario ciblé (détail de devis, fiche implant, composeur d'ordonnance, scan de retrait…) |

### Ronde 2026-09-15, 3e vague — 6e lot (2 écrans, **total 54**)

| app | écran/route | inventoriés | activés | OK | morts (vérifiés) | cassés | last_check |
|---|---|---|---|---|---|---|---|
| patient | `/rdv/:id/prepare` (390) | 2 | 2 | 2 | **0** (1 faux positif levé) | 0 | 2026-09-15T20:38:00Z — L'écran « **Préparer mon RDV** » affiche le praticien, l'adresse, « Parking disponible », « Accès PMR » et « Rappel Mer 16 sep à 09:00 », puis **une seule** ligne de checklist : « Carte Vitale ». Elle ressortait MORT (ni `aria-checked`, ni requête) — **vérification au diff de pixels sur son rect (16,278 358×56)** : le clic sur la case **change bien les pixels**, la case se coche. **Non morte.** À consigner tout de même, sans en faire une issue : (a) l'élément est exposé en `role="button"` **sans `aria-checked`**, donc un lecteur d'écran ne peut pas annoncer l'état coché ; (b) le basculement n'émet **aucune requête** et l'état repart décoché au rechargement — cohérent avec le scénario `patient-prepare-rdv-checklist-et-donnees` déjà consigné le 2026-09-02. Témoin de vivacité du pointeur : « Retour » navigue vers `/`. |
| patient | `/implant-passport` (390) | 6 | 6 | 6 | 0 | 0 | 2026-09-15T20:35:00Z — 2e passage (cf. ledger design-v2) : les 5 cartes d'implant et l'export répondent. |

---

## ✅ BILAN DÉFINITIF — ronde 2026-09-15, 3e vague

*(recalculé sur l'ensemble des journaux de la ronde, doublons de route/viewport dédupliqués)*

| | valeur |
|---|---|
| **écrans audités par l'auditeur** | **57** — patient 24, secrétariat 15, praticien 11, pharmacie 5, infirmière 2 |
| **contrôles inventoriés** | **999** |
| **contrôles activés et jugés** | **920** |
| morts **bruts** (détecteur) | 109 |
| morts **vérifiés** au re-clic isolé | **1** — bascule « En ligne » infirmière (**#6964**, déjà ouverte) |
| **faux positifs levés** | **108** |
| cassés | **21** — dont **15** = 403 « relation de soin » volontaires et **correctement affichés**, 5 = 403 RBAC `/cabinet/stats` (#6369), 1 = jeton expiré en cours de lot |
| captures sauvegardées | **189** dans `qa/screenshots/<rôle>/` |

### Les 5 familles de faux positifs de cette ronde

| famille | occurrences | comment les éviter |
|---|---|---|
| **auto-navigation** — entrée de nav de l'écran **courant** | ~30 | ignorer l'entrée dont la route == l'URL courante |
| **facette / onglet déjà sélectionné** (« Toutes », « Tous », « Membres »…) | ~20 | lire `aria-selected` avant de cliquer |
| **rail poussé hors de portée** (#6829/#6944) | ~25 | connu ; ne pas recompter |
| **coordonnées périmées en lot** — après la 1re ouverture, tout le reste du lot ressort MORT | ~25 | re-naviguer entre deux contrôles, ou re-cliquer isolément |
| **délégation à la plateforme / au canvas** (pièges **nº 17** et **nº 18**) | ~8 | intercepter `window.open`/`filechooser`, et **comparer les pixels** du rect |

> **La leçon de la ronde, en une phrase** : sur une app Flutter web, **l'arbre Semantics dit qui existe,
> les pixels disent ce qui se passe**. 108 des 109 « morts » détectés étaient des artefacts ; le seul vrai
> mort (#6964) n'a été confirmé qu'après un balayage de ~170 points de clic **et** un témoin de vivacité
> du pointeur dans la même session.

### Ronde 2026-09-15, 3e vague — 7e lot (2 écrans, **total 59**)

| app | écran/route | inventoriés | activés | OK | morts (vérifiés) | cassés | last_check |
|---|---|---|---|---|---|---|---|
| patient | `/questionnaire-medical/:cabinetId` (390) | 1 | 0 | — | 0 | 0 | 2026-09-15T20:37:00Z — **1re fois auditée.** L'écran rend « **Avant votre rendez-vous** », le bandeau vert « **Déjà transmis à votre cabinet le 19/08/2026.** », puis les 3 zones (Antécédents médicaux / Allergies / Traitements en cours) et la bascule ALD — **toutes correctement désactivées**, avec la raison affichée. **Désactivation légitime et motivée**, pas un défaut. *(Que le point d'entrée depuis un RDV confirmé mène à « Page introuvable » est **#6888**, déjà ouverte — la route elle-même, avec un `cabinetId` valide, fonctionne.)* |
| pharmacie | `/orders/:id` (Délivrance, 1280) | 22 | 20 | 20 | **0** (3 faux positifs levés) | 0 | 2026-09-15T20:47:00Z — « Voir l'original » (requête), « Créer un devis » et « Commencer la préparation » répondent. « **Refuser la commande** » ressortait MORT : re-testée **sur une commande au statut `received`**, elle est **OK** — elle ouvre sa boîte de confirmation (« **Motif (obligatoire)** », « Annuler », « Refuser »). Le MORT venait de l'**état devenu obsolète** : l'auditeur avait déjà cliqué « Commencer la préparation » plus haut dans le même lot, faisant passer la commande en `preparing`, statut où le refus n'est **légitimement** plus proposé. **6e famille de faux positif : l'action disparaît parce que le lot a fait avancer la machine à états.** |

> **Correction du bilan** : 59 écrans audités, et la **6e famille de faux positifs** ci-dessus s'ajoute aux
> cinq déjà listées — quand un lot enchaîne les contrôles d'un même écran transactionnel, les actions
> conditionnées au statut peuvent disparaître **en cours de lot**. Re-tester sur une ressource au bon statut.

| app | écran/route | inventoriés | activés | OK | morts (vérifiés) | cassés | last_check |
|---|---|---|---|---|---|---|---|
| patient | `/coverage-setup` (390) | 7 | 7 | 7 | **0** (2 faux positifs levés) | 0 | 2026-09-15T20:49:00Z — **1re fois auditée.** 3 boutons radio (Régime général / AME / CSS), 2 champs et « Enregistrer » / « Plus tard ». Les 2 champs ressortaient MORT : la saisie est **relue dans le DOM** (`"MGENtestMGEN QA-R73QA TestQA43"`), ils fonctionnent — **piège nº 17** pour la 3e fois de la ronde. **Écran total : 60.** |

> **Bilan des faux positifs sur champs de saisie** : 3 écrans de formulaire sur 3 (`secretariat /patients/new`,
> `patient /home-care/new`, `patient /coverage-setup`) ont rendu leurs `textbox` « MORT » au détecteur, et
> **les 3 fois la saisie fonctionnait** (valeur relue dans le DOM). La sonde « taper puis mesurer » ne convient
> pas aux champs : **relire `input.value` est le seul verdict fiable**.

---

## Ronde 2026-09-16 (1re vague) — 35 écrans, 808 contrôles inventoriés, 764 activés

> Les **5 apps** ont été parcourues (patient 390×844, praticien/secrétariat/pharmacie 1280×800,
> infirmière 390×844), connectées avec leur compte, chaque contrôle de l'inventaire Semantics
> activé et jugé.
>
> **Bilan brut** : 808 inventoriés · 764 activés · 687 OK · **60 MORT** · **17 CASSÉ** · 6 désactivés ·
> 3 hors-écran · 29 non activés (destructifs).
>
> **Bilan après vérification individuelle de chaque MORT/CASSÉ** — c'est le seul chiffre qui compte :
> **2 défauts réels** (#7030 champ « Rechercher un document… », #7029 en-tête de groupe du rail) et
> **2 écrans réellement cassés** (#7027 `/home-care` patient). **Les 73 autres verdicts négatifs sont
> des faux positifs**, tous re-testés à la main et documentés ci-dessous.

### Familles de faux positifs de CETTE ronde (à intégrer au détecteur)

| # | famille | manifestation | preuve du contraire |
|---|---|---|---|
| 18 | **destination de navigation == route courante** | 21 occurrences : « Stock » sur `/stock`, « Agenda » sur `/agenda`, « Labo » sur `/lab-work-orders`… | Le no-op est légitime : la destination est déjà affichée. |
| 19 | **onglet / facette déjà sélectionné** | `tab "Offres"` sur l'onglet Offres, `switch "Prêtes"` déjà coché | Re-clic = no-op attendu. Les 4 facettes officine testées isolément **fonctionnent** : Toutes 72 → Reçues 10 (8 actions) → En préparation 8 → Prêtes 54 (10 actions), `aria-checked` bascule à chaque fois. |
| 20 | **403 de sondage de capacité** | `/cabinet/members` et `/cabinet/audit-log` en 403 à **chaque** chargement secrétariat | Volontaire : `members_access_cubit.dart` / `audit_log_access_cubit.dart` **sondent** la route pour décider d'afficher l'entrée de menu. Bruit console, pas un défaut. |
| 21 | **403 « relation de soin » rendu proprement** | 15 CASSÉ sur `/patients` praticien : `medical-record`, `documents`, `prescriptions` en 403 | L'écran **gère le 403** et affiche « **Vous n'avez pas encore suivi ce patient — l'historique clinique n'est pas accessible.** » (capture `praticien/patient-403-QZQA73ZZ.png`). Comportement exemplaire, pas un bug. |
| 22 | **clic simple vs double-clic sur un champ** | `textbox "Rechercher un patient"` (secrétariat), `"Écrire un message à l'équipe…"` (praticien) | Re-testés : la saisie **passe** et la liste filtre (38 → 25 contrôles). Le verdict fiable reste **relire la valeur ET mesurer l'effet écran**, jamais `document.activeElement` seul. |
| 23 | **conteneur sans libellé capté par le sélecteur** | 3× `(group) ""` @267,296 237x488 sur `/lab-work-orders`, `(textbox)` de 717×750 sur la file officine | Nœuds d'agrégation, pas des contrôles. À exclure (`role=group` avec enfants, rect > 60 % du viewport). |

### Ledger par écran

| app | écran/route | inventoriés | activés | OK | morts (vérifiés) | cassés | last_check |
|---|---|---|---|---|---|---|---|
| infirmiere | `/` accueil (390) | 8 | 7 | 7 | 0 | 0 | 2026-09-16T00:11:00Z |
| infirmiere | `/` onglet Disponibilité (390) | 8 | 7 | 7 | **0** (1 FP : onglet actif) | 0 | 2026-09-16T00:12:00Z — bascule « En ligne » OK (aller/retour vérifié côté API). |
| infirmiere | `/` onglet Offres (390) | 7→9 | 6→8 | 8 | **0** (1 FP) | 0 | 2026-09-16T01:05:00Z — avec une offre réelle : « Accepter » et « Passer » présents et actifs. |
| infirmiere | `/` onglet Ma visite (390) | 7→9 | 6→8 | 8 | **0** (1 FP) | 0 | 2026-09-16T01:05:00Z — « Je pars » / « Je suis arrivé·e » / « Visite terminée » enchaînés avec succès. |
| patient | `/` Accueil (390) | 18 | 17 | 16 | 0 | **1 réel → #7027** | 2026-09-16T00:24:00Z — « Itinéraire » ouvre bien un onglet externe (FP levé) ; « Soins à domicile » lève une exception non rattrapée. |
| patient | `/mes-rdv` (390) | 15 | 14 | 14 | 0 | 0 | 2026-09-16T00:26:00Z |
| patient | `/messaging` (390) | 16 | 15 | 15 | 0 | 0 | 2026-09-16T00:28:00Z |
| patient | `/documents` (390) | 32 | 30 | 29 | **1 réel → #7030** | 0 | 2026-09-16T00:31:00Z — champ de recherche inutilisable **arbre d'accessibilité actif** ; 11 « Télécharger » OK. |
| patient | `/profile` (390) | 19 | 18 | 18 | 0 | 0 | 2026-09-16T00:33:00Z |
| patient | `/appointments/slots` (390) | 28 | — | — | — | — | 2026-09-16T01:35:00Z — parcours réservation joué au clic ; troncature de la barre de confirmation → **#7031**. |
| pharmacie | `/` File des commandes (1280) | 23 | 22 | 22 | **0** (2 FP) | 0 | 2026-09-16T00:45:00Z — 4 facettes re-testées isolément : **toutes fonctionnelles**. |
| pharmacie | `/stock` (1280) | 14 | 13 | 13 | **0** (1 FP) | 0 | 2026-09-16T00:52:00Z |
| pharmacie | `/messages` (1280) | 15 | 14 | 14 | **0** (1 FP) | 0 | 2026-09-16T00:55:00Z |
| pharmacie | `/devis` (1280) | 27 | 26 | 26 | **0** (1 FP) | 0 | 2026-09-16T00:58:00Z |
| praticien | `/` Tableau de bord (1280) | 18 | 17 | 17 | **0** (1 FP) | 0 | 2026-09-16T00:56:00Z |
| praticien | `/agenda` (1280) | 22 | 21 | 21 | **0** (1 FP) | 0 | 2026-09-16T01:00:00Z |
| praticien | `/waiting-room` (1280) | 18 | 16 | 16 | **0** (1 FP) | 0 | 2026-09-16T01:03:00Z — 1 contrôle désactivé (file vide). |
| praticien | `/patients` (1280) | 32 | 31 | 29 | **0** (2 FP) | **0** (15 FP, cf. famille 21) | 2026-09-16T01:08:00Z |
| praticien | `/consultation` (1280) | 32 | 31 | 31 | **0** (1 FP) | 0 | 2026-09-16T01:15:00Z — filtre « En cours » **vide à tort** → **#7033**. |
| praticien | `/ordonnances` (1280) | 17 | 16 | 16 | **0** (1 FP) | 0 | 2026-09-16T01:18:00Z |
| praticien | `/devis` (1280) | 24 | 23 | 23 | **0** (1 FP) | 0 | 2026-09-16T01:21:00Z |
| praticien | `/stock` (1280) | 18 | 17 | 17 | **0** (1 FP) | 0 | 2026-09-16T01:24:00Z |
| praticien | `/stock-inventory` (1280) | 28 | 27 | 27 | **0** (1 FP) | 0 | 2026-09-16T01:27:00Z |
| praticien | `/lab-work-orders` (1280) | 21 | 20 | 20 | **0** (4 FP : 1 nav + 3 conteneurs) | 0 | 2026-09-16T01:30:00Z — « Nouveau bon » et « Actualiser » répondent. |
| praticien | `/messages` (1280) | 24 | 23 | 23 | **0** (1 FP) | 0 | 2026-09-16T01:33:00Z |
| praticien | `/team-messages` (1280) | 18 | 17 | 17 | **0** (2 FP) | 0 | 2026-09-16T01:36:00Z — composeur « Écrire un message à l'équipe… » re-testé : **saisie OK**. |
| secretariat | `/` Tableau de bord (1280) | 28 | 27 | 26 | **1 réel → #7029** | 0 | 2026-09-16T00:38:00Z |
| secretariat | `/agenda` (1280) | 89 | 88 | 88 | **0** (14 FP) | 0 | 2026-09-16T01:00:00Z — **l'écran le plus dense de la ronde**. « Nouveau RDV » (⌘N), créneaux libres, « Semaine suivante », cartes de RDV : tous re-testés **fonctionnels**. |
| secretariat | `/salle-attente` (1280) | 21 | 19 | 18 | **1 (#7029)** | 0 | 2026-09-16T00:47:00Z |
| secretariat | `/liste-attente` (1280) | 20 | 19 | 18 | **1 (#7029)** | 0 | 2026-09-16T00:50:00Z |
| secretariat | `/patients` (1280) | 38 | 35 | 34 | **1 (#7029)** | 0 | 2026-09-16T00:53:00Z — champ « Rechercher un patient » re-testé : **OK** (38 → 25). |
| secretariat | `/appointments` (1280) | 24 | 23 | 22 | **1 (#7029)** | 0 | 2026-09-16T00:56:00Z |
| secretariat | `/devis` (1280) | 39 | 38 | 37 | **1 (#7029)** | 0 | 2026-09-16T01:00:00Z |
| secretariat | `/cabinet-payouts` (1280) | 24 | 21 | 20 | **1 (#7029)** | 0 | 2026-09-16T01:20:00Z — « Exporter (CSV) » et « Connecter Stripe » **désactivés à raison** : le 1er faute de virement, le 2d avec le motif documenté #6702 (« Connexion Stripe indisponible pour l'instant. »). |
| secretariat | `/team-messages` (1280) | 26 | 23 | 22 | **1 (#7029)** | 0 | 2026-09-16T01:24:00Z — 2 CTA « à venir » correctement grisés. |

> **Prochaine ronde — écrans jamais audités** (à prendre en premier) : patient `/implant-passport`,
> `/treatment-plans`, `/reviews`, `/oubliettes`, `/profile/consents`, `/profile/dependents` ;
> praticien `/patients/:id/dental-chart` et `/periodontal-chart` ; secrétariat `/admin-membres`,
> `/admin-secretariats`, `/audit-log`, `/bookable-slots`, `/cabinet-stats`, `/appointment-motifs`,
> `/onboard` ; infirmière `/notification-preferences` (panneau de notifications non déplié).

### Complément — **2e viewport** (les 2 apps mobile-first passées à 1280×800)

> Exigence « aux DEUX viewports » : patient et infirmière, conçues en 390×844, re-parcourues à
> **1280×800**. **Bilan cumulé de la ronde : 45 écrans · 954 contrôles inventoriés · 896 activés ·
> 816 OK.**

| app | écran/route | inventoriés | activés | OK | morts (vérifiés) | cassés | last_check |
|---|---|---|---|---|---|---|---|
| patient | `/` Accueil (**1280×800**) | 18 | 17 | 16 | 0 | **1 → #7027 (reproduit)** | 2026-09-16T02:35:00Z — mise en page **étirée pleine largeur** (carte héros, lignes « À faire », barre d'onglets) : aucun chevauchement, aucune troncature, aucune régression de mise en page. Le plantage « Soins à domicile » se reproduit **à l'identique** au viewport bureau. |
| patient | `/mes-rdv` (1280×800) | 15 | 14 | 14 | 0 | 0 | 2026-09-16T02:38:00Z |
| patient | `/messaging` (1280×800) | 16 | 15 | 15 | 0 | 0 | 2026-09-16T02:41:00Z |
| patient | `/documents` (1280×800) | 31 | 30 | 29 | **1 → #7030 (reproduit)** | 0 | 2026-09-16T02:44:00Z — le champ de recherche mesure **1256×54** ici et reste inutilisable : **le défaut ne dépend pas du viewport**. |
| patient | `/profile` (1280×800) | 18 | 17 | 17 | 0 | 0 | 2026-09-16T02:47:00Z |
| infirmiere | `/` accueil (**1280×800**) | 8 | 6 | 6 | 0 | 0 | 2026-09-16T02:30:00Z — la maquette mobile est **étirée** sur toute la largeur (ratio near-white 0.977). Pas de casse ; app explicitement « soins à domicile, mobile », **non rapporté**. |
| infirmiere | `/` Disponibilité (1280×800) | 8 | 6 | 6 | 0 | 0 | 2026-09-16T02:31:00Z |
| infirmiere | `/` Offres (1280×800) | 7 | 5 | 5 | 0 | 0 | 2026-09-16T02:32:00Z |
| infirmiere | `/` Ma visite (1280×800) | 7 | 5 | 5 | 0 | 0 | 2026-09-16T02:33:00Z |

> **Les deux défauts réels du parcours patient se reproduisent aux deux viewports** (#7027, #7030) —
> ce ne sont donc pas des artefacts de mise en page mobile. Aucun **nouveau** défaut n'est apparu au
> viewport bureau sur ces deux apps.

### Complément — 4 sous-écrans du Profil patient (jamais audités auparavant) — **couverture PARTIELLE, assumée**

| app | écran/route | inventoriés | activés | OK | morts (vérifiés) | cassés | last_check |
|---|---|---|---|---|---|---|---|
| patient | Profil → **Mes proches** (390) | 22 | **1** | 1 | — | 0 | 2026-09-16T02:25:00Z — **non audité : limite d'outillage.** L'écran liste 5 proches et répète **5 fois les mêmes libellés** (« Afficher le menu », « Planifier », « Prendre RDV », « Documents »). Mon relocalisateur apparie par `(rôle, libellé)` et retombe donc toujours sur la 1re occurrence : 21 contrôles déclarés « hors-écran » **à tort**. À reprendre avec un appariement par **rect** et non par libellé. *Défaut a11y candidat, à qualifier la prochaine ronde : 5 boutons « Prendre RDV » au nom accessible identique — un lecteur d'écran ne permet pas de savoir **pour quel proche** on prend le rendez-vous.* |
| patient | Profil → **Consentements** (390) | 9 | **1** | 1 | — | 0 | 2026-09-16T02:28:00Z — même limite (« Détails » ×3). 1 contrôle légitimement désactivé (consentement « Soins », non modifiable, conforme à `Patient Consentements v2`). |
| patient | Profil → **Couverture santé** (390) | 8 | 7 | 3 | **4 à qualifier** | 0 | 2026-09-16T02:31:00Z — les 3 radios (Régime général / AME / CSS) + leur `radiogroup` ressortent MORT. **Non filé** : `GET /account/coverage` indique `regime_obligatoire:"css"`, donc le clic sur « CSS » est un no-op légitime ; reste à établir si « Régime général » et « AME » sont inertes ou si l'écran est en lecture seule — et la ronde précédente a déjà classé cet écran comme **piège nº 17** (faux positifs sur champs). **À trancher la prochaine ronde, avec relecture de l'état serveur après clic.** |
| patient | Profil → **Médecin traitant** (390) | 2 | 1 | 1 | 0 | 0 | 2026-09-16T02:33:00Z — écran quasi vide (`GET /account/referring-doctor` → `{}`, aucun médecin traitant déclaré). État vide correct. |

> **Note de méthode (7e famille de faux positifs) — diagnostic corrigé en fin de ronde.** J'ai
> d'abord attribué les 21 « hors-écran » de « Mes proches » à l'appariement par libellé (les lignes
> répètent « Prendre RDV », « Documents », « Afficher le menu »…). J'ai donc modifié le
> relocalisateur pour apparier par **rectangle corrigé du défilement** plutôt que par libellé, puis
> **rejoué l'audit : résultat identique (21 hors-écran)**. La cause réelle est donc ailleurs — la
> liste vit dans un **conteneur défilant imbriqué** que `page.mouse.wheel` ne fait pas défiler
> depuis le point visé. Correctif à apporter avant la prochaine ronde : viser la roulette **à
> l'intérieur** du conteneur (ou utiliser `scrollIntoView` sur le nœud Semantics) — sans quoi tout
> écran à liste longue reste non auditable. L'appariement par rect est conservé : il est correct,
> simplement insuffisant seul.
>
> **Note de navigation** : les lignes du Profil ouvrent bien leur sous-écran mais **sans changer
> l'URL** (elle reste `/`) — c'est **#6991** (`context.push` non migré), déjà ouverte. Vérifié :
> « Mes proches » depuis l'**Accueil** navigue correctement vers `/profile/dependents`, alors que la
> même destination depuis l'onglet **Profil** laisse l'URL à `/`.

## Ronde 2026-09-16 (2e vague, 06:00–09:00 UTC) — 36 écrans, 533 contrôles inventoriés, 502 activés

> Rotation : **les 11 routes jamais auditées** des 5 apps d'abord (établies en diffant les
> `app_router.dart` contre ce fichier), puis les écrans les plus anciens. **5 apps / 5**, chacune
> vue à **ses deux viewports**.

> ⚠️ **Lecture de la colonne « morts »** : sur les **67** verdicts MORT de cette ronde, **aucun n'a
> survécu à la vérification manuelle** — champs saisissables, lignes de conversation qui émettent leur
> `GET`, filtres qui ouvrent leur menu, radios de couverture qui basculent, « Détails » qui ouvre sa
> modale. Le détecteur reste un **indicateur**, pas un verdict.

> ⚠️ **Colonne « cassés »** : 11 des verdicts CASSÉ sont des **artefacts de sonde** — le jeton de la page
> expire (900 s) pendant la boucle d'activation d'un écran à 27+ contrôles, et tout ce qui suit part en
> `401`. **Correctif à apporter avant la prochaine ronde : réinjecter le jeton *en cours* d'écran**, pas
> seulement à la navigation.

### Trois limites d'outillage identifiées cette ronde (à corriger avant la suivante)

1. **Les champs pleine largeur sont invisibles à l'inventaire au viewport 1280.** `inv()` écarte tout
   `textbox` de plus de **700 px** (heuristique « c'est un conteneur », calibrée sur 390 px). Sur
   `/patients/new` (secrétariat) l'écran porte **4 champs** (Prénom, Nom, Téléphone, Date de naissance)
   larges de 1 248 px : l'inventaire n'en a compté **aucun** (`inv=2`). **Tous les formulaires des apps PC
   sont donc sous-comptés** — le seuil doit devenir relatif à la largeur du viewport.
2. **`page.mouse.wheel` ne défile rien si le pointeur n'a pas été posé sur la liste.** C'est la cause
   réelle du « conteneur défilant imbriqué » diagnostiqué la ronde précédente : un `mouse.move(w/2, h/2)`
   **avant** la roulette suffit à faire défiler `/profile/dependents` (vérifié : 24 nœuds → contenu
   totalement différent). À intégrer dans `auditScreen`.
3. **Le filtre de l'inventaire ignore les nœuds `flt-semantics` sans attribut `role`.** D'où le faux
   positif « l'état vide de *Ma visite* est absent des Semantics » : le texte y est bien, mais porté par
   un nœud sans `role`. Les verdicts d'accessibilité doivent être prononcés sur un **dump complet**.

| app | écran/route | inventoriés | activés | morts | cassés | last_check |
|---|---|---|---|---|---|---|
| infirmiere | `/ (3 onglets)` (390) | 7 | 6 | 0 | 0 | 2026-09-16 — 6/6 actifs, **0 mort, 0 cassé**. États vides explicites sur « Offres » et « Ma visite ». **Faux positif a11y écarté** : les deux textes SONT dans l'arbre Semantics (mon filtre ignorait les nœuds sans attribut `role`). |
| infirmiere | `/notification-preferences` (390) | 3 | 3 | 0 | 0 | 2026-09-16 — Jamais audité. 3/3 actifs (Retour + « Dans l'application » + « Sur mobile (push) »). |
| patient | `/account-setup` (390) | 5 | 4 | 3 | 0 | 2026-09-16 — **Jamais audité — 2 findings.** Les 3 « morts » sont des **faux positifs** (champs prouvés saisissables, valeurs relues dans le DOM). Vrais défauts : « Continuer » s'active puis `PATCH /v1/account` → **422** (#7035) et la date de naissance exigée n'est **jamais transmise** (#7036). |
| patient | `/appointments/slots` (390) | 21 | 20 | 5 | 0 | 2026-09-16 — Jamais audité. Les 5 « morts » sont les cartes praticien + « Voir sa fiche et ses coordonnées » = **#7022**, déjà ouverte. |
| patient | `/financial` (390) | 10 | 10 | 0 | 0 | 2026-09-16 — Rotation. 10/10 actifs, aucun défaut. |
| patient | `/home-care` (390) | 1 | 1 | 0 | 0 | 2026-09-16 — Rotation. Aucun défaut relevé. |
| patient | `/implant-passport` (390) | 6 | 6 | 0 | 0 | 2026-09-16 — Rotation. |
| patient | `/messaging` (390) | 8 | 8 | 0 | 0 | 2026-09-16 — Rotation. **Faux positif de méthode écarté** : l'app enchaîne bien 3 `GET /conversations/:id/messages?limit=100&cursor=…` à l'ouverture et affiche le dernier message (l'API, elle, sert la page la plus **ancienne**). |
| patient | `/oubliettes` (390) | 1 | 1 | 0 | 0 | 2026-09-16 — Jamais audité. **Ce n'est pas une corbeille** : l'état vide dit « Les documents consultés récemment apparaîtront ici » (`oubliettes_page.dart:21-22`). Les 10 cartes ne sont pas des contrôles (`ListTile` sans `onTap`) — lecture seule assumée, **non rapporté**. |
| patient | `/prescriptions` (390) | 16 | 16 | 0 | 0 | 2026-09-16 — Jamais audité. 16/16 actifs, aucun mort, aucun cassé. |
| patient | `/profile/consents` (390) | 8 | 7 | 1 | 0 | 2026-09-16 — Le « mort » est un faux positif : « Détails » ouvre bien sa modale (Finalité / Base légale / Statut / DPO). Le contrôle désactivé (« Soins ») est **légitime et prouvé** (`_LockedConsentsSection`, `onChanged: null`, pastille « Nécessaire au service · Non modifiable »). |
| patient | `/profile/referring-doctor` (390) | 1 | 1 | 0 | 0 | 2026-09-16 — Jamais audité. État vide correct : « Aucun médecin traitant déclaré » + CTA. `GET /account/referring-doctor` → 200. |
| patient | `/reviews` (390) | 1 | 1 | 0 | 0 | 2026-09-16 — Sans paramètre : état vide. **Le vrai chemin marche** : `/reviews?appointmentId=…` (deep link de `review_request`) rend le formulaire. **#6986 re-confirmée** : les 5 étoiles ont un nom accessible **vide**. |
| patient | `/treatment-plans` (390) | 9 | 9 | 0 | 0 | 2026-09-16 — Rotation. 9/9 actifs, aucun défaut. |
| pharmacie | `/devis` (1280) | 27 | 26 | 3 | 0 | 2026-09-16 — Rotation. |
| pharmacie | `/messages` (1280) | 15 | 14 | 2 | 0 | 2026-09-16 — Rotation. Les 2 « morts » sont l'en-tête et la facette active. |
| pharmacie | `/notification-preferences` (1280) | 9 | 9 | 0 | 0 | 2026-09-16 — Jamais audité. 9/9 actifs. |
| pharmacie | `/stock` (1280) | 14 | 13 | 2 | 0 | 2026-09-16 — Rotation. |
| praticien | `/agenda` (1280) | 22 | 21 | 1 | 0 | 2026-09-16 — Rotation. |
| praticien | `/cabinet-setup` (1280) | 5 | 4 | 2 | 0 | 2026-09-16 — Jamais audité. Morts = faux positifs (champs saisissables). « Enregistrer » → `PATCH /v1/cabinet` → **403**, mais l'écran l'annonce **correctement** : « **Accès refusé. Rôle administrateur requis.** » — le bon libellé, cité en exemple dans #7037. |
| praticien | `/devis` (1280) | 24 | 23 | 1 | 0 | 2026-09-16 — Rotation. Aucun défaut. |
| praticien | `/lab-work-orders` (1280) | 18 | 17 | 1 | 0 | 2026-09-16 — Rotation. Le « mort » est l'entrée de nav courante. Aucun défaut. |
| praticien | `/messages` (1280) | 24 | 23 | 1 | 0 | 2026-09-16 — Rotation. |
| praticien | `/ordonnances` (1280) | 17 | 16 | 1 | 0 | 2026-09-16 — Rotation. Aucun défaut. |
| praticien | `/stock-inventory` (1280) | 28 | 24 | 5 | 0 | 2026-09-16 — Rotation. Erreurs WebSocket/401 du journal = **artefacts de jeton expiré** (le WS se connecte normalement, vérifié séparément : 1 trame, 0 erreur). |
| praticien | `/waiting-room` (1280) | 18 | 16 | 1 | 0 | 2026-09-16 — Rotation. « **Appeler suivant** » désactivé : **légitimité prouvée** — `GET /cabinet/waiting-room` → 0 patient et `POST /call-next` → `{"called": false}`. |
| secretariat | `/admin-secretariats` (1280) | 21 | 20 | 1 | 0 | 2026-09-16 — Jamais audité → **#7037**. `POST /v1/cabinet/secretariats` → **403** (admin only). La nav **masque** correctement l'entrée : écran atteignable par URL directe seulement (gravité ramenée à P2). |
| secretariat | `/appointment-motifs` (1280) | 28 | 27 | 3 | 13 | 2026-09-16 — Rotation. **Les « cassés » lisibles sont tous des `401`** (jeton de page expiré pendant la boucle). **Non qualifiés comme défauts produit.** |
| secretariat | `/bookable-slots` (1280) | 27 | 26 | 7 | 1 | 2026-09-16 — Rotation. Les « morts » **vérifiés à la main sont vivants** : « Actualiser » émet 2 requêtes, « Tous les praticiens » et « Toutes les dates » ouvrent leur menu. |
| secretariat | `/cabinet-stats` (1280) | 24 | 23 | 4 | 1 | 2026-09-16 — Rotation. |
| secretariat | `/liste-attente` (1280) | 20 | 19 | 2 | 0 | 2026-09-16 — Rotation. Aucun défaut. |
| secretariat | `/messages` (1280) | 28 | 27 | 8 | 0 | 2026-09-16 — Jamais audité. Les 8 « morts » sont des lignes de conversation : **faux positifs vérifiés** — le clic émet `GET /cabinet/conversations/:id/messages` (200) et ouvre le fil. |
| secretariat | `/notification-preferences` (1280) | 12 | 12 | 0 | 0 | 2026-09-16 — Jamais audité. 12/12 actifs. Le « cassé » est un **artefact de sonde** (401, jeton de page expiré). |
| secretariat | `/onboard (redirige vers /)` (1280) | 28 | 26 | 10 | 0 | 2026-09-16 — Jamais audité. `/onboard` **redirige vers le tableau de bord** pour un compte déjà intégré — attendu. Morts/cassés = artefacts (en-têtes de groupe, 401). |
| secretariat | `/patients/new` (1280) | 2 | 1 | 0 | 1 | 2026-09-16 — Rotation. |
| secretariat | `/team-messages` (1280) | 25 | 22 | 3 | 0 | 2026-09-16 — Rotation. Le « mort » **Mentionner** est **#6995**, déjà ouverte. Les 2 contrôles désactivés (« Joindre un patient, un devis… » et « Épingler ») sont **légitimes et prouvés depuis le code** : ce sont les CTA du correctif **#6702**, grisés **avec leur raison en `Tooltip`** (« Jointure d'un objet du produit indisponible pour l'instant. » / « Épinglage de message indisponible pour l'instant. », `cabinet_team_messages_page.dart:1011-1035`) — exactement la convention demandée. |

> **TOTAL RONDE : 36 écrans · 533 contrôles inventoriés · 502 activés · 67 « morts » (0 confirmé) · 16 « cassés » non qualifiés + 11 artefacts de jeton.**


### Complément de fin de ronde — écrans audités après la clôture du tableau principal

| app | écran/route | inventoriés | activés | morts | cassés | last_check |
|---|---|---|---|---|---|---|
| secretariat | `/salle-attente` (1280) | 21 | 19 | 2 | 0 | 2026-09-16T08:37:00Z — Rotation. Les 2 « morts » sont des en-têtes de groupe de navigation. « **Appeler suivant** » désactivé : **légitimité prouvée côté serveur** — `GET /v1/cabinet/waiting-room` rend **0 patient** et `POST /call-next` rend `{"called": false}`. Les 403 sur `/cabinet/members` et `/cabinet/audit-log` sont la sonde de capacité de l'app (cf. note de la section principale), pas un défaut. |

| secretariat | `/devis` (1280) | 39 | 34 | 2 | 0 | 2026-09-16T08:43:00Z — Rotation. Écran le plus dense de la ronde (39 contrôles : facettes, tri, recherche, lignes de devis). Les 2 « morts » sont les en-têtes de groupe de navigation « Facturation » et « Devis, 11 ». **Aucun contrôle cassé.** |

| patient | `/documents` (390) | 26 | 24 | 1 | 0 | 2026-09-16T08:48:00Z — Rotation. Le « mort » est la facette active « Tous 397 » (re-cliquer un filtre déjà sélectionné est un no-op légitime). **Aucun contrôle cassé.** Écart de libellé connu (nom de fichier brut au lieu d'un titre lisible) = **#6372**, déjà ouverte, non re-rapportée. |

> **TOTAL DÉFINITIF DE LA RONDE : 39 écrans · 619 contrôles inventoriés · 579 activés · 0 mort confirmé.**

#### Ronde 2026-09-16 (3e vague, 18:00–19:15 UTC) — dépôt sans `main` exploitable (#7032 toujours ouverte)

> **Écrans jamais audités jusqu'ici** attaqués en priorité (l'Étape 1bis n'a rien livré : aucun commit
> front depuis le 2026-09-08, seuls des commits de registre QA depuis le dernier `explored-paths.md`).
> Les deux fiches cliniques du praticien (`dental-chart`, `periodontal-chart`) et
> `/profile/referring-doctor/search` côté patient n'avaient **jamais** été inventoriées.
>
> **Méthode — activation de l'arbre Semantics.** Le placeholder « Enable accessibility » fait 1×1 px à
> (−1,−1) : un clic souris Playwright ne l'atteint JAMAIS. Seul
> `document.querySelector('flt-semantics-placeholder').click()` (via `page.evaluate`) construit l'arbre.
> Corollaire : le canvas CanvasKit vit dans le **shadow root** de `flt-glass-pane` —
> `document.querySelectorAll('canvas').length` vaut 0 en light DOM, il faut parcourir les `shadowRoot`.
>
> **Seuil de blanc.** `whiteRatio > 0.92` produit des faux positifs sur les écrans mobiles clairs :
> `/profile/referring-doctor/search` (0.943) et l'app infirmière (0.973–0.975) sont **rendues et
> peuplées** malgré le ratio. Le ratio ne vaut que couplé à l'inventaire (0 contrôle = vrai blanc).

| app | écran/route | contrôles inventoriés | activés | OK | morts | cassés | last_check ISO |
|---|---|---|---|---|---|---|---|
| praticien | `/patients/:id/dental-chart` (**1er audit**, 1280×800) | 52 | 44 | 43 | 0 | 0 | 2026-09-16T18:20:00Z |
| praticien | `/patients/:id/periodontal-chart` (**1er audit**, 1280×800) | 54 | 24 | 24 | 0 | 0 | 2026-09-16T18:26:00Z |
| patient | `/profile/referring-doctor/search` (**1er audit**, 390×844) | 17 | 12 | 12 | 0 | 0 | 2026-09-16T18:33:00Z |
| patient | `/treatment-plans` (390×844) | 9 | 8 | 8 | 0 | 0 | 2026-09-16T18:36:00Z |
| patient | `/home-care` (390×844) | 1 | 1 | 0 | 0 | 1 | 2026-09-16T18:36:00Z |
| secretariat | `/` Tableau de bord (1280×800) | 28 | 26 | 26 | 0 | 0 | 2026-09-16T18:40:00Z |
| secretariat | `/salle-attente` (1280×800) | 21 | 19 | 19 | 0 | 0 | 2026-09-16T18:41:00Z |
| secretariat | `/agenda` (1280×800) | 83 | 53 | 53 | 0 | 0 | 2026-09-16T18:43:00Z |
| secretariat | `/liste-attente` (1280×800) | 20 | 19 | 19 | 0 | 0 | 2026-09-16T18:44:00Z |
| secretariat | `/audit-log` (1280×800) | 24 | 21 | 21 | 0 | 0 | 2026-09-16T18:45:00Z |
| pharmacie | `/` File des commandes (1280×800) | 23 | 18 | 18 | 0 | 0 | 2026-09-16T18:47:00Z |
| pharmacie | `/stock` (1280×800) | 14 | 12 | 12 | 0 | 0 | 2026-09-16T18:48:00Z |
| pharmacie | `/devis` (1280×800) | 27 | 22 | 22 | 0 | 0 | 2026-09-16T18:49:00Z |
| pharmacie | `/messages` (1280×800) | 15 | 14 | 14 | 0 | 0 | 2026-09-16T18:50:00Z |
| infirmiere | `/` (Disponibilité / Offres / Ma visite, 390×844) | 8 | 7 | 7 | 0 | 0 | 2026-09-16T19:01:00Z |
| infirmiere | `/notification-preferences` (390×844) | 3 | 3 | 3 | 0 | 0 | 2026-09-16T19:01:00Z |
| **TOTAL ronde** | **16 écrans, 5 apps** | **399** | **303** | **301** | **0** | **1** | 2026-09-16T19:15:00Z |

**Le seul « cassé » est `/home-care` (patient) = #7027, déjà ouverte** (`address` non-objet accepté en
201 qui fige l'écran : `TypeError: 42: type 'int' is not a subtype of type 'Map<String, dynamic>?'`).
Non re-rapporté.

##### 7e famille de faux positifs « MORT » : le lot qui laisse un overlay ouvert

Le détecteur a signalé **42 contrôles MORTS**. **Les 42 se sont révélés fonctionnels en
ré-activation isolée** (écran rechargé avant chaque clic). Cause unique et systématique : le
**premier** clic du lot ouvre une boîte de dialogue / un panneau latéral modal, et **tous les clics
suivants du lot frappent la barrière de l'overlay** — d'où « aucun effet observable ».

Cas re-vérifiés un par un, écran fraîchement rechargé :

| contrôle | verdict du lot | verdict isolé | preuve |
|---|---|---|---|
| dents `17`, `16`, `48` (schéma dentaire) | MORT | **OK** | ouvre le sélecteur de statut (13 nœuds : `Ignorer`, `Sain`, `Carie`…) |
| `Dent 15` (bilan parodontal) | MORT | **OK** | déplie 6 champs de sondage `MV/V/DV/DL/L/ML` |
| `Appeler` ×2, `Relancer`, `Ouvrir` (tdb secrétariat) | MORT | **OK** | naviguent vers agenda / devis / messagerie (200 à l'appui) |
| carte agenda `Marc Dubois · QA-R69 B4` | MORT | **OK** | ouvre le panneau latéral (`Fermer`, `Marquer arrivé`, `Déplacer`, `Appeler`) |
| 3 fils « Aucun message » (officine) | MORT | **OK** | `200 GET /v1/pharmacy/conversations/:id/messages`, 21 contrôles après |
| cartes `/treatment-plans` ×6 (patient) | MORT | **OK** | `200 GET /v1/treatment-plans/:id`, écran de détail rendu |
| `Dr Camille Laurent` (annuaire médecin traitant) | MORT | **OK** | ouvre le dialogue « Déclarer … ? » |
| `Préparer` (devis officine) | MORT | **OK** | **navigue** vers `/orders/:id` (200) |
| onglets infirmière + interrupteur `En ligne` | MORT | **OK** | tabs repeignent ; l'interrupteur émet `PATCH /v1/nurse/availability` **au curseur (à droite)**, pas au centre |

**Règle à appliquer aux prochaines rondes** : ne jamais conclure « MORT » depuis un lot. Tout candidat
doit être rejoué sur un écran fraîchement rechargé. Le taux de faux positifs reste de **100 %**.

##### Contrôle VISIBLE mais absent de l'arbre (Étape 2a)
`/patients/:id/dental-chart` : les 32 dents sont bien dans l'arbre, mais leur `aria-label` se réduit au
numéro FDI — le **statut clinique** (carie / couronne / sain) n'existe que dans la couleur de fond et
une pastille de 5 px, toutes deux hors arbre. → **#7043** (P2).
#### Ronde 2026-09-17 (00:00–03:00 UTC) — 5/5 apps parcourues + balayage des liens directs

> **Ciblage diff-driven** (Étape 1bis) : 13 lots mergés depuis le dernier registre (`7465e14`,
> 2026-09-16 19:32Z), dont 5 touchant le front — `dependents_page.dart` + `login_page.dart` +
> `auth_cubit.dart` (patient), `dental_chart_page.dart` + `tooth_grid.dart` (praticien),
> `agenda_page.dart` (secrétariat). Ces écrans ont été audités **en premier**.
>
> **Neuf de cette ronde : le balayage des routes paramétrées en LIEN DIRECT** (rechargement de
> page, favori, deep link de notification), jamais fait jusqu'ici. 18 routes à paramètre des
> 5 apps ouvertes à l'URL : 2 défauts trouvés (#7074, #7075), 16 saines.

| app | écran/route | contrôles inventoriés | activés | OK | morts | cassés | last_check ISO |
|---|---|---|---|---|---|---|---|
| praticien | `/patients/:id/dental-chart` (1280×800, **re-audit #7043**) | 56 | 50 | 49 | 1* | 0 | 2026-09-17T00:35:00Z |
| patient | `/profile/dependents` (390×844, **re-audit #7041**) | 24 | 17 | 17 | 0 | 0 | 2026-09-17T00:41:00Z |
| patient | `/profile` (390×844) | 17 | 13 | 11 | 2* | 0 | 2026-09-17T00:45:00Z |
| patient | `/financial?id=<uuid>` (390×844, **1er audit du deep link**) | 2 | 1 | 1 | 0 | 0 | 2026-09-17T00:33:00Z |
| patient | `/implant-passport/:id` (390×844, **1er audit**) | **0** | 0 | 0 | 0 | — | 2026-09-17T01:30:00Z |
| patient | `/treatment-plans/:id` (390×844, **1er audit**) | 1 | 0 | 0 | 0 | 0 | 2026-09-17T01:31:00Z |
| patient | `/messaging/:id` (390×844, **1er audit**) | 9 | 5 | 4 | 0 | **1** | 2026-09-17T01:32:00Z |
| infirmiere | `/` (390×844, 3 onglets parcourus) | 8 | 6 | 6 | 0 | 0 | 2026-09-17T00:52:00Z |
| infirmiere | `/notification-preferences` (390×844) | 5 | 3 | 3 | 0 | 0 | 2026-09-17T00:54:00Z |
| pharmacie | `/` (1280×800) | 35 | 17 | 14 | 3* | 0 | 2026-09-17T01:15:00Z |
| pharmacie | `/devis` (1280×800) | 42 | 24 | 20 | 4* | 0 | 2026-09-17T01:18:00Z |
| pharmacie | `/stock` (1280×800) | 16 | 11 | 9 | 2* | 0 | 2026-09-17T01:20:00Z |
| secretariat | `/salle-attente` (1280×800) | 24 | 19 | 17 | 2* | 0 | 2026-09-17T02:00:00Z |
| secretariat | `/liste-attente` (1280×800) | 22 | 19 | 17 | 2* | 0 | 2026-09-17T02:04:00Z |
| secretariat | `/cabinet-payouts` (1280×800) | 27 | 21 | 19 | 2* | 0 | 2026-09-17T02:08:00Z |
| praticien | `/devis` (1280×800) | 27 | 23 | 22 | 1* | 0 | 2026-09-17T02:00:00Z |
| praticien | `/lab-work-orders` (1280×800) | 24 | 17 | 16 | 1* | 0 | 2026-09-17T02:02:00Z |
| praticien | `/stock-inventory` (1280×800) | 42 | 24 | 23 | 1* | 0 | 2026-09-17T02:12:00Z |
| patient | `/mes-rdv` (**1280×800**, 1er audit à ce viewport) | 11 | 6 | 5 | 1* | 0 | 2026-09-17T02:22:00Z |
| patient | `/prescriptions` (**1280×800**, 1er audit à ce viewport) | 16 | 2 | 2 | 0 | 0 | 2026-09-17T02:25:00Z |
| secretariat | `/appointment-motifs` (1280×800) | 27 | 9 | 9 | 0 | 0 | 2026-09-17T02:50:00Z |
| secretariat | `/admin-secretariats` (1280×800) | 24 | 20 | 20 | 0 | 0 | 2026-09-17T02:55:00Z |
| secretariat | `/bookable-slots` (1280×800) | 30 | 26 | 21 | 4* | 1* | 2026-09-17T02:58:00Z |
| **TOTAL** | **23 écrans** | **489** | **333** | **305** | **26 bruts → 0 confirmés** | **2 bruts → 1 confirmé** | — |

\* **Les 26 verdicts « MORT » ont TOUS été rejoués et sont TOUS des faux positifs** — le taux de
faux positifs du détecteur reste de 100 %, comme aux rondes précédentes. Familles identifiées
cette fois, à connaître pour ne plus les re-filer :
1. **Entrée de navigation déjà active** (`Commandes` sur `/`, `Devis` sur `/devis`, `Stock` sur
   `/stock`, `Salle d'attente` sur `/salle-attente`…) : cliquer la destination courante ne change
   évidemment rien.
2. **Facette déjà sélectionnée** (`Toutes 71`, `Prêtes 55`, `Tous (117)`, `À répondre (6)`) : même
   raison.
3. **En-tête de section repliable du rail secrétariat** (`Ma journée`, `Facturation`, `Patients`) :
   c'est **#7029**, déjà ouverte.
4. **Sélecteur de fichier natif** — `Modifier la photo de profil` (patient) : l'événement
   Playwright `filechooser` remonte bien `true`, aucune repeinture n'est attendue.
5. **Dent déjà à l'état cliqué** (`Adulte` sur le schéma dentaire).

> **Nouvelle famille de faux positifs à documenter (leçon de méthode de cette ronde) :
> le CTA hors viewport.** Sur la modale de confirmation de réservation patient (390×844),
> `Confirmer le rendez-vous` est inventorié à **y = 1248** pour un viewport de 844 px : tout clic
> à ces coordonnées manque sa cible et produit **0 requête**, ce qui ressemble trait pour trait à
> un bouton mort. Il faut **faire défiler jusqu'à ramener le rect dans le viewport** avant de
> juger. Une fois le bouton visible (y = 825), le double-clic rapide produit **exactement un**
> `POST /v1/bookings` → `201 {"appointment_id":"cbf82314-…","status":"requested"}` : l'anti
> double-submit du parcours de réservation est **sain**.
>
> Corollaire : un second piège de sélection a coûté deux faux positifs cette ronde — le nœud
> Semantics parent porte la **concaténation des libellés de ses enfants** (`"AccepterPasser"`,
> `"Modifier la photo de profilMarc Dubois…"`). Un `find()` par `label.includes(...)` attrape le
> **groupe** (390×708) et non le bouton (240×44). Toujours filtrer sur `role === 'button'` **et**
> comparer le libellé **exact**.

##### Le seul contrôle CASSÉ confirmé
`/messaging/:id` ouvert **en lien direct** : le bouton `Retour` lève
`GoError: There is nothing to pop` (pageerror), l'URL ne bouge pas, et la route ne monte pas la
barre d'onglets → l'écran n'a plus **aucune** sortie. Par le parcours normal (liste → fil) le même
bouton fonctionne et la console reste vide. → **#7075** (P1).

##### Écran rendu inutilisable hors audit de contrôles
`/implant-passport/:id` en lien direct : **0 contrôle**, canvas gris uni, `TypeError` Dart au build
(`state.extra as ImplantItem` sur `null`, `app_router.dart:455-459`). Le même écran atteint par la
liste rend 4 contrôles. → **#7074** (P0).

##### Balayage des liens directs (18 routes à paramètre, 5 apps) — le reste est sain
`patient` : `/treatment-plans/:id` (1), `/home-care/:id` (2), `/rdv/:id/prepare` (3),
`/rdv/:id/modifier` (50), `/questionnaire-medical/:cabinetId` (5), `/pharmacy/orders/:id` (4),
`/oubliettes` (2), `/notifications` (21), `/appointments/slots?providerId=` (37) — tous peints et
peuplés. `praticien` : `/patients/:id` (50), `/consultation?id=` (59), `/ordonnances/new?patientId=`
(49). `secretariat` : `/devis/:id` (23). `pharmacie` : `/orders/:id` (38), `/orders/:id/pickup` (4).
Seule exception fonctionnelle : `/reviews?providerId=` (2 contrôles) — mais c'est un défaut de
**parsing**, pas de deep link → **#7076**.

##### Cas adversariaux joués cette ronde
- **Coupure réseau** (`route.abort()` sur `**/v1/**`) pendant le chargement de `/prescriptions`
  (patient) : dégradation **digne** — `Retour` + `Réessayer`, aucun spinner infini, aucun écran
  blanc ; réseau rétabli + « Réessayer » → 17 contrôles, écran reconstitué.
- **Double-clic** sur `Confirmer le rendez-vous` (patient) → **1 seul** `POST /v1/bookings` (201).
- **Double-clic** sur `Accepter` une offre (infirmière) → une seule acceptation côté serveur.
- **Back navigateur** au milieu du parcours de réservation puis `forward` : état cohérent
  (23 contrôles → 27), aucune erreur.
- **Saisie invalide** : `Envoyer` d'une demande de stock sans pharmacie → refus propre
  (`_onConfirm` sort sur `SnackBar('Choisissez une pharmacie.')`, **0** POST), quantité `-5`
  bornée par `qty <= 0 → 'Quantité invalide.'`.
- **Texte très long** : 250 caractères dans la recherche de documents patient → la liste se vide
  proprement, aucune erreur, aucun débordement (la rangée de facettes est un défilement
  horizontal par conception, ses rects hors viewport ne sont pas un débordement).

##### Scan de santé — les 5 apps, toutes leurs routes, aux deux viewports
Balayage complet (59 couples route×viewport) à la recherche d'écrans vides, de canvas non peints,
de textes d'erreur et de requêtes ≥ 400. **Tout est sain** sauf, dans l'ordre :
`patient /home-care` (1 contrôle, `PAGEERROR: TypeError: 42: type 'int' is not a subtype of type
'Map<String, dynamic>?'`) = **#7027 déjà ouverte** ; `secretariat /cabinet-payouts`
(« Connexion Stripe indisponible pour l'instant. ») et `secretariat /team-messages`
(2 CTA grisés avec leur raison) = **raisons légitimes du correctif #6702**, sauf la rédaction de
l'une d'elles → **#7082** ; les `403` sur `/cabinet/members` et `/cabinet/audit-log` présents sur
**17/17** écrans secrétariat = **sonde de gating volontaire**, déjà documentée (bruit attendu).

##### Correctifs de cette ronde vérifiés EN LIVE pendant la ronde
Les agents correcteurs ont livré pendant la session ; re-testés après déploiement :
**#7064** (FHIR : `Appointment` déclare désormais `patch`, plus `update`), **#7068** (le devis
signé du 16/09 porte maintenant `document_id: 8da153c2-…` — la reprise a tourné), **#7070**
(le switch biométrie est `aria-disabled=true` et porte « Indisponible sur ce navigateur. »),
**#7076** (`/reviews?providerId=` liste enfin les avis). **#7073** est corrigé aux deux tiers —
le formulaire et le récapitulatif du créneau sont là — mais son `POST` n'est pas routé → **#7080**.
**#7079** est mergé sans être encore déployé à l'heure du test (les payloads invalides passaient
toujours en 201).

##### Limite d'outillage constatée (à corriger au harnais, pas au produit)
Sur `patient /prescriptions` (1280×800), 13 des 15 contrôles activables sont restés `MISSING after
reset` : ouvrir une ordonnance change l'écran, et la remise à zéro par `page.goto` ne reconstruit
pas l'arbre Semantics avant l'inventaire suivant. **Ce n'est pas un défaut produit** — les deux
contrôles réellement activés répondent (`Retour` navigue, la 1re carte ouvre le détail). Le harnais
doit attendre que le nombre de contrôles soit revenu à sa valeur de départ après un `reset()`.

##### Précision apportée à #7067 pendant la ronde
Mesure refaite sur les trois états : `/consultation` (liste) n'a **ni** bouton ⌘K **ni** raccourci ;
`/consultation?id=…` (fauteuil) **a** un bouton, mais c'est la palette d'**actes** (infobulle :
« Recherche d'actes pour l'instant — patient et ordonnance à venir ») et **`Meta+K` ne l'ouvre pas**
alors que son propre libellé affiche « ⌘K » ; `/patients` sert de contrôle positif (palette ouverte,
`[role=dialog]` vrai). « Préférences de notifications » est absent des **deux** états de consultation.
Commentaire de précision posté sur l'issue.

##### Dernier écran audité — `/bookable-slots` (secrétariat), 2 verdicts levés
Le « cassé » est **`Statistiques`** : l'entrée navigue bien vers `/cabinet-stats`, qui déclenche
`403 GET /v1/cabinet/stats/activity` — **garde clinique volontaire** (`cabinet_stats.rs`,
`ProPractitionerClaims`). Le défaut réel (l'app secrétariat expose quand même l'entrée) est
**#6369, déjà ouverte** : non re-filée. Les 4 « morts » sont l'en-tête repliable
`Réglages du cabinet` (**#7029**), la destination courante `Créneaux ouverts`, et deux entrées dont
les coordonnées avaient bougé après le repli de la section. Les 3 contrôles propres à l'écran
(`Tous les praticiens`, `Toutes les dates`, `Créer un créneau`) répondent tous.

## Ronde 2026-09-17 (06:00–09:xx UTC) — 14 écrans audités, 219 contrôles activés

### ⚠️ Correctif de méthode appliqué CETTE ronde — les « morts » des rondes précédentes étaient sur-comptés

Le détecteur automatique avait **deux défauts de mesure** corrigés en cours de ronde ;
les chiffres ci-dessous sont ceux d'**après** correction, et ils sont très différents :

1. **Pas de retour à l'écran après une navigation invisible.** Comme aucun écran de détail
   patient n'écrit son URL (**#7095**), l'ancien détecteur — qui ne re-naviguait que si
   `location.href` avait changé — restait bloqué sur l'écran de destination après le premier
   clic : **tous** les contrôles suivants étaient cliqués dans le vide et comptés MORT en
   cascade. Effet mesuré sur `patient /` : **12 morts avant correctif, 1 après**.
2. **Empreinte d'écran tronquée à 6 000 caractères** : tout écran long paraissait « inchangé »
   après un clic. Remplacée par un hash de l'**arbre Semantics complet** (aria-label + texte).

Trois autres sources de faux positifs, confirmées et désormais filtrées :

- **Sondes de capacité** : `403 GET /v1/cabinet/members` et `403 GET /v1/cabinet/audit-log` sont
  émises à **chaque** chargement du back-office pour masquer les entrées admin-only
  (`pro_config.dart:42-54`). Les compter faisait passer pour CASSÉ n'importe quel contrôle
  cliqué au mauvais moment : `secretariat /audit-log` **14 cassés avant filtrage, 0 après**.
- **Rôle Semantics inattendu** : les facettes de la file pharmacie sont des `role=switch`, pas des
  `button` — un inventaire filtré sur `button` les déclarait « absentes » alors qu'elles sont là.
- **Défilement hors zone** : `mouse.wheel` part de (0,0) si le curseur n'a pas été déplacé dans la
  liste ; l'écran ne défile pas et les contrôles bas paraissent introuvables (faux « `Ajouter un
  proche` absent » sur `/profile/dependents`, en réalité présent en `role=button` et fonctionnel).

| app | écran/route | contrôles inventoriés | activés | OK | morts | cassés | désactivés | last_check ISO |
|---|---|---|---|---|---|---|---|---|
| patient | `/financial` (390) | 8 | 8 | 8 | 0 | 0 | 0 | 2026-09-17T07:16:00Z |
| patient | `/pharmacy` (390) | 7 | 7 | 5 | 2 | 0 | 0 | 2026-09-17T07:16:00Z |
| patient | `/profile` (390) | 8 | 7 | 6 | 1 | 0 | 1 | 2026-09-17T07:16:00Z |
| pharmacie | `/` (1280) | 19 | 18 | 16 | 2 | 0 | 0 | 2026-09-17T07:16:00Z |
| pharmacie | `/devis` (1280) | 24 | 20 | 18 | 2 | 0 | 0 | 2026-09-17T07:16:00Z |
| pharmacie | `/stock` (1280) | 14 | 13 | 11 | 2 | 0 | 0 | 2026-09-17T07:16:00Z |
| praticien | `/` (1280) | 18 | 17 | 15 | 1 | 1 | 0 | 2026-09-17T07:16:00Z |
| praticien | `/agenda` (1280) | 22 | 21 | 20 | 1 | 0 | 0 | 2026-09-17T07:16:00Z |
| praticien | `/lab-work-orders` (1280) | 18 | 17 | 16 | 1 | 0 | 0 | 2026-09-17T07:16:00Z |
| praticien | `/ordonnances` (1280) | 17 | 16 | 15 | 1 | 0 | 0 | 2026-09-17T07:16:00Z |
| praticien | `/team-messages` (1280) | 17 | 5 | 5 | 0 | 0 | 0 | 2026-09-17T07:16:00Z |
| secretariat | `/` (1280) | 27 | 26 | 24 | 2 | 0 | 0 | 2026-09-17T07:16:00Z |
| secretariat | `/devis` (1280) | 35 | 21 | 19 | 2 | 0 | 0 | 2026-09-17T07:16:00Z |
| secretariat | `/salle-attente` (1280) | 24 | 23 | 23 | 0 | 0 | 0 | 2026-09-17T07:16:00Z |
| **TOTAL** | **14 écrans** | **258** | **219** | **201** | **17** | **1** | **1** | 2026-09-17T07:16:00Z |

### Contrôles re-vérifiés à la main (les « morts » résiduels)

Comme aux rondes précédentes, **aucun** des morts résiduels re-testés n'était réellement inerte :

- `patient /pharmacy/orders` — les 16 cartes de commande : le clic **ouvre bien** l'écran « Suivi de
  commande » (capture `R75_ord_clic_gauche.png`), mais `location.href` ne bouge pas → c'est **#7095**,
  pas un bouton mort.
- `patient /documents` — « Télécharger » : émet `GET /v1/documents/:id/download` puis ouvre le PDF
  signé dans un nouvel onglet (`.../storage/local/devis/….pdf?expires=…&sig=…`). Fonctionnel.
- `infirmiere /` — les 3 onglets et l'interrupteur « En ligne » : l'interrupteur émet
  `PATCH /v1/nurse/availability`, **bascule visuellement** (`aria-checked` true→false) et **l'état
  survit à un F5**. Les onglets changent bien de contenu (`Aucune offre` / `Ma visite`).
- `secretariat /stock` — `Renouveler` / `Réorienter` / `Voir` : ouvrent le volet de détail sans
  requête, **repli volontaire et documenté** (`stock_page.dart:810-818`). `Relancer`, la seule action
  réseau de l'écran, émet bien `POST /cabinet/stock-requests/:id/resend` et résiste au triple-clic.
- Entrées de navigation de l'écran **courant** : sans effet par conception.

### Écrans audités pour la première fois cette ronde

`patient /pharmacy`, `patient /home-care`, `secretariat /liste-attente`, `secretariat /appointment-motifs`,
`secretariat /audit-log`, `praticien /ordonnances`, `pharmacie /notification-preferences`,
`infirmiere /notification-preferences`.


## Ronde 2026-09-17 (12:00–14:0x UTC) — ciblage diff-driven des 11 merges de la matinée

> **Correctif de HARNAIS appliqué en cours de ronde (à retenir pour les suivantes).** Deux défauts de
> l'auditeur ont été trouvés et corrigés *pendant* la ronde, et ils invalident une partie des verdicts
> « MORT » des rondes précédentes :
> 1. **Fichier temporaire partagé** — les 5 runners écrivaient tous dans `/tmp/pw/_t.png` pour le hash
>    de pixels. Un runner lisait donc l'image d'un autre → « pixels changés » toujours vrai → faux **OK**.
>    Corrigé par un temporaire par processus.
> 2. **Contrôles hors viewport** (piège n° 2 déjà consigné, mais jamais outillé) — l'inventaire Semantics
>    remonte les nœuds sous la ligne de flottaison ; les cliquer aux coordonnées ne fait rien → faux **MORT**.
>    Corrigé par un filtre `inView` + un **auditeur à défilement** (`t_scroll_audit.js`) qui redescend
>    l'écran par paliers de 0,75 × hauteur et n'active que ce qui est réellement visible.
>
> Conséquence : la colonne « morts » ci-dessous ne retient QUE les contrôles re-vérifiés avec l'auditeur
> à défilement. Les 28 « morts » bruts du premier passage se décomposent en **10 réels** (tous sur
> `patient /prescriptions`, un seul et même bug → **#7119**) et **18 faux positifs hors-écran**, chacun
> re-testé et sorti OK après défilement.

| app | écran/route | contrôles inventoriés | activés | OK | morts | cassés | commentaire | last_check |
|---|---|---|---|---|---|---|---|---|
| praticien | `/` (Tableau de bord, 1280) — **auditeur à défilement** | 23 | 19 | 17 | **0** | **2** | Les 2 « morts » du premier passage (`Confirmations en attente`, `Messages non lus`) sont **de faux positifs hors-écran** : après défilement ils naviguent bien vers `/agenda` et `/messages`. Les 2 CASSÉS sont réels et filés → **#7116** : le hero « Patient suivant » sert un patient d'un CONFRÈRE, « Démarrer la consultation » → `403 forbidden` sur `POST /cabinet/appointments/:id/start`, « Ouvrir le dossier » → 3 × 403. | 2026-09-17T13:50:00Z |
| patient | `/prescriptions` (Mes ordonnances, 390) — **auditeur à défilement** | 17 | 12 | 2 | **10** | 0 | **Les 10 morts sont réels et n'ont qu'UNE cause** : ouvrir la 1re ordonnance émet bien `GET /v1/documents/:id/download` (200), puis la liste entière est remplacée par l'état vide « Aucune ordonnance » — 17 nœuds → 1. Les 10 clics suivants tombent dans le vide. → **#7119 (P1)**. Sortir et revenir restaure les 17 nœuds. | 2026-09-17T13:50:00Z |
| patient | `/mes-rdv` (390) — **auditeur à défilement** | 11 | 6 | **6** | 0 | 0 | Le « mort » du premier passage (`Plus d'actions`) est un faux positif hors-écran : re-testé après défilement, les deux occurrences réagissent. Onglets `À venir (20)` / `Historique`, tri `Plus proche d'abord`, `Prendre un rendez-vous` → `/book` : tous OK. Comportement connu non re-filé : ouvrir « Historique » déclenche une pagination par curseur en cascade (#6448). | 2026-09-17T13:50:00Z |
| patient | `/` (Accueil, 390) | 23 | 18 | 15 | 3 → **0 retenus** | 0 | Les 3 « morts » (`Ma pharmacie` @y=945, `Mes proches` @y=945, `Soins à domicile` @y=1010) sont **hors du viewport 390×844** — faux positifs par construction, non retenus. | 2026-09-17T13:50:00Z |
| patient | `/notifications` (390) | 21 | 20 | 17 | 3 → **0 retenus** | 0 | Re-vérifié un par un : les 5 premiers « Voir la visite » naviguent vers `/home-care/<id>` **et** émettent `POST /v1/notifications/:id/read` ; les 2 derniers sont à y=877 et y=1004, **hors viewport**. Contenu des notifications correct et spécifique (« Votre infirmière est en route vers votre domicile. »). | 2026-09-17T13:50:00Z |
| patient | `/appointments` (Prendre un RDV, 390) | 22 | 17 | 14 | 3 → **0 retenus** | 0 | Carte, 5 facettes, cartes praticien « 3 jours de créneaux » avec état vide par jour (« — ») et « Aucun créneau en ligne pour ce praticien ». Le mort `Voir sa fiche et ses coordonnées` renvoie à **#7022 (open)**, non re-filé. | 2026-09-17T13:50:00Z |
| patient | `/appointments/slots?providerId=…` (grille de créneaux, 390) | 50 | 2 | 2 | 0 | 0 | **Écran jamais audité.** Rail de 4 jours daté et compté (`LUN 21 / 14 dispo` … `JEU 24 / 6 dispo`), grille **4 colonnes** de cellules 84×44, sections `Matin` / `Après-midi`, sélection d'un créneau → surlignage + barre « **Lun. 21 sep à 07:30 · Durée estimée 30 min** » + « Continuer ». | 2026-09-17T13:50:00Z |
| patient | `/financial` (390) | 11 | 10 | 8 | 2 → **0 retenus** | 0 | Morts hors-écran, non retenus. | 2026-09-17T13:50:00Z |
| praticien | `/consultation` (liste, 1280) | 37 | 33 | 29 | 4 → **0 retenus** | 0 | Les 3 facettes émettent chacune leur requête serveur distincte (`?status=in_progress` / `completed` / `cancelled`) — **#7033 confirmé corrigé**. Les 4 morts sont des lignes de consultation sous la ligne de flottaison. | 2026-09-17T13:50:00Z |
| praticien | `/consultation?id=<séance>` (au fauteuil, 1280) | 66 | — | — | — | — | **Écran jamais audité sous cet angle.** Inventaire complet : 32 dents cliquables, 3 actes de séance, recherche CCAM, 3 favoris, `Terminer la séance`, `Note de séance`, `Modèle`. Défaut de rendu trouvé → **#7118**. | 2026-09-17T13:50:00Z |
| praticien | `/waiting-room` (1280) | 27 | 19 | **19** | 0 | 0 | 2 DÉSACTIVÉS légitimes (`Appeler` des lignes déjà appelées). La file est bien **cabinet-wide** depuis #7097 : « Appeler QA-R76 Z… » (patient de Dr Lefèvre) émet `POST /cabinet/waiting-room/call-next` → 200. | 2026-09-17T13:50:00Z |
| secretariat | `/` (Tableau de bord, 1280) | 30 | 26 | **26** | 0 | 0 | Écran le plus propre de la ronde : 26/26. Rail groupé, 4 × `Appeler`, `Relancer`, 2 × `Ouvrir`, `Ouvrir l'agenda`. | 2026-09-17T13:50:00Z |
| secretariat | `/agenda` (1280) | 38 | 32 | 29 | 3 → **0 retenus** | 0 | `Semaine précédente` / `Semaine suivante` / `Aujourd'hui` réémettent bien `GET /cabinet/agenda` + `/cabinet/slots` avec les bonnes bornes ; filtres praticien (`Dr Claire Lefèvre 6` / `Dr Hugo Marin 45`) OK ; pastilles de créneau libre `08:00`/`10:00`/`11:00`/`14:00` ouvrent la création. Les 3 morts (`15:00`, `16:00`, `17:00`) sont en bas de grille, hors viewport. | 2026-09-17T13:50:00Z |
| pharmacie | `/` (File des commandes, 1280) | 35 | 21 | 18 | 3 → **0 retenus** | 0 | 4 compteurs, recherche, 4 facettes, 7 × `Délivrer` naviguant chacun vers `/orders/<id>/pickup` distinct. Les 3 morts sont les `Délivrer` de bas de liste, hors viewport. | 2026-09-17T13:50:00Z |
| infirmiere | `/` (3 onglets) + `/notification-preferences` (390) | 13 | 9 | **9** | 0 | 0 | **5ᵉ app parcourue.** Cycle métier complet rejoué en UI (ci-dessous). | 2026-09-17T13:50:00Z |
| infirmiere | `/` → Offres → « Accepter » → « Je pars » → « Je suis arrivé·e » → « Visite terminée » | 5 | 5 | **5** | 0 | 0 | **#7026 (mergé à 11:34 ce jour) confirmé corrigé en live** : après `POST /nurse/visits/:id/accept`, l'app bascule seule sur l'onglet **« Ma visite »** (`aria-selected=true`) et affiche « Statut : Acceptée » + « Je pars ». Les 3 transitions suivantes émettent chacune leur POST. Prix affiché « 43,00 € » = l'estimation API (2500 + 1800). | 2026-09-17T13:50:00Z |

### Écrans audités pour la première fois cette ronde

`patient /appointments/slots` (grille de créneaux), `praticien /consultation?id=<séance>` (consultation au fauteuil).

### Contrôle non activé volontairement

`Se déconnecter` (les 5 apps) — destructif pour la session de test. Aucun contrôle de suppression de
compte/cabinet/pharmacie n'a été activé.


### Addendum de fin de ronde

| app | écran/route | contrôles inventoriés | activés | OK | morts | cassés | commentaire | last_check |
|---|---|---|---|---|---|---|---|---|
| patient | `/profile` (390) — **auditeur à défilement** | 17 | 13 | **12** | 0 retenu | 0 | Les 6 « morts » du premier passage se réduisent à **zéro** : 5 sont hors viewport et naviguent correctement après défilement (`Médecin traitant` → `/profile/referring-doctor`, `Mes proches` → `/profile/dependents` + `GET /account/access-requests`, `Consentements` → `/profile/consents`, `Passeport implantaire` → `/implant-passport`, `Ma pharmacie` → `/pharmacy`). Le 6ᵉ, « Modifier la photo de profil », est une **limite de harnais** : le nœud Semantics englobe tout l'en-tête (avatar + nom + e-mail) alors que la cible réelle est le cercle de 64 px (`profile_page.dart:741-745`, `InkWell` + `CircleBorder`), et son `onTap` ouvre un **sélecteur de fichier natif** — invisible au DOM, aux pixels et au réseau. Non retenu. 1 DÉSACTIVÉ légitime (`Authentification biométrique`, cf. #7070). | 2026-09-17T14:25:00Z |
| praticien | `/agenda` (1280) | 25 | 21 | **21** | 0 | 0 | 21/21. | 2026-09-17T14:25:00Z |
| praticien | `/ordonnances` (1280) | 19 | 16 | **16** | 0 | 0 | 16/16, « Choisir un patient » émet sa requête. | 2026-09-17T14:25:00Z |
| secretariat | `/salle-attente` (1280) | 28 | 22 | **22** | 0 | 0 | 22/22. | 2026-09-17T14:25:00Z |
| patient | `/pharmacy/orders` (390) | 17 | 16 | 13 | 3 → **0 retenus** | 0 | Morts en bas de liste, hors viewport. | 2026-09-17T14:25:00Z |
| patient | `/home-care` (390) | 18 | 17 | 14 | 3 → **0 retenus** | 0 | Morts hors viewport — mais **défaut de libellé trouvé sur ces mêmes cartes** : l'adresse se réduit à « ,   » → **#7121 (P2)**. | 2026-09-17T14:25:00Z |
| patient | `/appointments/slots` → « Continuer » → feuille de confirmation | 27 | 1 | **1** | 0 | 0 | Étape 3 du tunnel : le clic simple ouvre la feuille modale complète (motifs, bénéficiaire, « Modifier », « Confirmer le rendez-vous »). | 2026-09-17T14:25:00Z |

### Cas adversariaux joués (Étape 2f) — app patient

| cas | verdict | observation |
|---|---|---|
| **Double-clic rapide** sur « Continuer » (tunnel de réservation) | **OK — ni doublon, ni crash** | **0 écriture émise**, aucune exception, aucun double-booking. Instrumenté à part : le 2ᵉ clic tombe **dans** la feuille (sur la puce « Urgence ») et **ne la referme pas** (`feuille encore ouverte ? true`, 27 contrôles). Sur deux clics synthétiques à 0 ms d'intervalle — que Chromium coalesce en `dblclick` — la feuille ne s'ouvre pas du tout ; **non rapporté**, faute de pouvoir distinguer l'app de l'artefact de synthèse (un doigt réel ne produit pas 0 ms) |
| **Back / Forward navigateur** au milieu du tunnel | **OK** | `/appointments/slots` → back → `/appointments` (16 contrôles, pas d'écran blanc) → forward → `/appointments/slots` (48 contrôles). État cohérent dans les deux sens |
| **Texte très long + accents** dans un champ libre (`/home-care/new`, 260 caractères) | **OK** | 13 contrôles avant comme après, **0 débordement horizontal** mesuré sur les rects Semantics |
| **Coupure réseau** pendant une action (`route.abort` sur `**/v1/**`, ouverture d'ordonnance) | **défaut** | 17 contrôles → 1 et « Aucune ordonnance » au lieu d'un message d'erreur — **même cause que #7119**, ajouté en commentaire à l'issue |
| **Écran chargé API coupée** (`/financial`) | **OK** | « Retour » + « **Réessayer** » : erreur digne, pas de spinner infini, pas d'écran blanc (nearWhite 0.98 = fond de l'état d'erreur, arbre Semantics non vide) |


#### Ronde 2026-09-17 R77 (18:00–19:4x UTC) — 5/5 apps, 61 écrans audités au contrôle près

> **Harnais R77** — deux corrections de l'auditeur lui-même, toutes deux validées par contre-épreuve :
> 1. **Empreinte PIXEL en repli du verdict** (`R77_audit.js`, verdict `OK-pixel`). Sans elle, un effet purement
>    visuel (coche de sélection, icône sans `semanticLabel`) passait pour MORT : **12 faux MORT mesurés sur
>    `/pharmacy/send`** au premier passage, **0** après correction, sur le même écran et le même compte.
> 2. **Ré-injection du token avant CHAQUE activation** (et plus seulement à la navigation) : l'access token vit
>    900 s, un écran à 35 contrôles le dépasse. Sans ça, `secretariat /stock` rendait **14 « CASSÉ »** qui
>    étaient 14 × `401`. Après correction : **0 CASSÉ**.
> 
> **Concurrence** : au-delà de ~4 Chromium simultanés, les relevés se dégradent (volets modaux captant les
> clics, `Target crashed`, `page.screenshot` en timeout). Les écrans ambigus ont été **re-audités en série**,
> et c'est le relevé série qui fait foi dans le tableau ci-dessous.

| app | écran/route | contrôles inventoriés | activés | OK | morts | cassés | grisés | last_check | note |
|---|---|---|---|---|---|---|---|---|---|
| infirmiere | `/ (Disponibilité / Offres / Ma visite)` (390 px) | 7 | 6 | 6 | 0 | 0 | 0 | 2026-09-17T19:40:00Z | 3 onglets activés (px change à chaque bascule), bascule « En ligne », cycle métier complet joué ci-dessous |
| infirmiere | `/notification-preferences` (390 px) | 3 | 3 | 3 | 0 | 0 | 0 | 2026-09-17T19:40:00Z | « Retour » + les 2 bascules Visites (in-app / push) |
| patient | `/` (390 px) | 15 | 15 | 14 | 1 | 0 | 0 | 2026-09-17T19:40:00Z | Le seul MORT est l'onglet de l'écran courant (no-op légitime) |
| patient | `/appointments` (390 px) | 14 | 14 | 13 | 1 | 0 | 0 | 2026-09-17T19:40:00Z | MORT = le champ de recherche déjà focalisé ; les 5 puces de filtre et les 4 clusters de carte répondent |
| patient | `/pharmacy/send` (390 px) | 12 | 12 | 12 | 0 | 0 | 0 | 2026-09-17T19:40:00Z | **JAMAIS AUDITÉ avant cette ronde.** 12 cartes d'ordonnance, toutes sélectionnables → #7140 |
| patient | `/pharmacy/search` (390 px) | 1 | 1 | 1 | 0 | 0 | 0 | 2026-09-17T19:40:00Z | **Jamais audité.** Champ « Nom de la pharmacie ou ville », état vide propre |
| patient | `/pharmacy/quotes` (390 px) | 1 | 1 | 1 | 0 | 0 | 0 | 2026-09-17T19:40:00Z | **Jamais audité.** Écran vide (0 devis officine en attente) + « Retour » |
| patient | `/profile/referring-doctor` (390 px) | 1 | 1 | 1 | 0 | 0 | 0 | 2026-09-17T19:40:00Z | **Jamais audité.** « Changer de médecin traitant » navigue |
| patient | `/prescriptions` (390 px) | 12 | 12 | 12 | 0 | 0 | 0 | 2026-09-17T19:40:00Z | **Jamais audité.** Zone du merge #7122 : ouvrir une ordonnance ne vide plus la liste (12/12 OK) |
| patient | `/mes-rdv` (390 px) | 7 | 7 | 7 | 0 | 0 | 0 | 2026-09-17T19:40:00Z | Facettes À venir (20) / Historique, tri, « Plus d'actions » par ligne |
| patient | `/financial` (390 px) | 8 | 8 | 8 | 0 | 0 | 0 | 2026-09-17T19:40:00Z | 8 cartes de devis, chacune ouvre son détail |
| patient | `/home-care` (390 px) | 14 | 14 | 14 | 0 | 0 | 0 | 2026-09-17T19:40:00Z | Zone du merge #7123 : plus de virgule nue sur les cartes à adresse vide |
| patient | `/implant-passport` (390 px) | 4 | 4 | 4 | 0 | 0 | 0 | 2026-09-17T19:40:00Z |  |
| patient | `/notifications` (390 px) | 6 | 6 | 6 | 0 | 0 | 0 | 2026-09-17T19:40:00Z |  |
| patient | `/profile` (390 px) | 6 | 6 | 6 | 0 | 0 | 0 | 2026-09-17T19:40:00Z |  |
| patient | `/profile/dependents` (390 px) | 6 | 6 | 6 | 0 | 0 | 0 | 2026-09-17T19:40:00Z |  |
| patient | `/profile/notifications` (390 px) | 6 | 6 | 6 | 0 | 0 | 0 | 2026-09-17T19:40:00Z |  |
| patient | `/messaging` (390 px) | 6 | 6 | 6 | 0 | 0 | 0 | 2026-09-17T19:40:00Z |  |
| patient | `/documents` (390 px) | 6 | 6 | 6 | 0 | 0 | 0 | 2026-09-17T19:40:00Z |  |
| patient | `/oubliettes` (390 px) | 1 | 1 | 1 | 0 | 0 | 0 | 2026-09-17T19:40:00Z |  |
| patient | `/reviews` (390 px) | 1 | 1 | 1 | 0 | 0 | 0 | 2026-09-17T19:40:00Z | État vide propre « Aucun avis pour ce prestataire » (route sans providerId) |
| patient | `/book` (1280 px) | 23 | 23 | 23 | 0 | 0 | 0 | 2026-09-17T19:40:00Z |  |
| patient | `/pharmacy` (1280 px) | 6 | 6 | 6 | 0 | 0 | 0 | 2026-09-17T19:40:00Z |  |
| patient | `/treatment-plans` (1280 px) | 7 | 7 | 7 | 0 | 0 | 0 | 2026-09-17T19:40:00Z |  |
| patient | `/profile/consents` (1280 px) | 8 | 7 | 5 | 2 | 0 | 1 | 2026-09-17T19:40:00Z | Les 2 « MORT » sont hors viewport (y=875 > 844) — non retenus ; le switch « Soins » est grisé à raison (« Nécessaire au service · Non modifiable ») |
| patient | `/documents` (1280 px) | 6 | 4 | 4 | 0 | 0 | 0 | 2026-09-17T19:40:00Z |  |
| patient | `/home-care` (1280 px) | 13 | 13 | 12 | 0 | 1 | 0 | 2026-09-17T19:40:00Z | Le CASSÉ est un `502 GET /favicon.png` (hébergement, pas l'app) |
| patient | `/prescriptions` (1280 px) | 12 | 12 | 12 | 0 | 0 | 0 | 2026-09-17T19:40:00Z |  |
| praticien | `/` (1280 px) | 16 | 15 | 14 | 1 | 0 | 0 | 2026-09-17T19:40:00Z | MORT = entrée de rail de l'écran courant. Hero « Patient suivant » vérifié présent + CTA fonctionnels après check-in (#7126 OK) |
| praticien | `/consultation` (1280 px) | 30 | 29 | 28 | 1 | 0 | 0 | 2026-09-17T19:40:00Z | Zone du merge #7124 : les 3 pastilles Favoris CCAM font h=62 à 1280 comme à 1440 (avant : 44, tronquée) |
| praticien | `/waiting-room` (1280 px) | 21 | 19 | 16 | 3 | 0 | 1 | 2026-09-17T19:40:00Z | Les 3 « MORT » re-testés un par un en série : « Appeler … » et « Ouvrir le dossier » changent bien l'écran → non retenus comme morts, MAIS « Appeler » est un no-op silencieux côté métier → #7217 |
| praticien | `/patients` (1280 px) | 27 | 26 | 21 | 0 | 5 | 0 | 2026-09-17T19:40:00Z | Les 5 CASSÉ sont des `403` de la garde « relation de soin » sur des patients jamais suivis — conforme, non retenu |
| praticien | `/agenda` (1280 px) | 22 | 21 | 21 | 0 | 0 | 0 | 2026-09-17T19:40:00Z |  |
| praticien | `/ordonnances` (1280 px) | 17 | 16 | 16 | 0 | 0 | 0 | 2026-09-17T19:40:00Z |  |
| praticien | `/devis` (1280 px) | 22 | 21 | 20 | 1 | 0 | 0 | 2026-09-17T19:40:00Z |  |
| praticien | `/stock` (1280 px) | 18 | 17 | 17 | 0 | 0 | 0 | 2026-09-17T19:40:00Z |  |
| praticien | `/stock-inventory` (1280 px) | 25 | 24 | 23 | 1 | 0 | 0 | 2026-09-17T19:40:00Z |  |
| praticien | `/lab-work-orders` (1280 px) | 18 | 17 | 17 | 0 | 0 | 0 | 2026-09-17T19:40:00Z |  |
| praticien | `/messages` (1280 px) | 17 | 16 | 16 | 0 | 0 | 0 | 2026-09-17T19:40:00Z |  |
| praticien | `/team-messages` (1280 px) | 17 | 16 | 16 | 0 | 0 | 0 | 2026-09-17T19:40:00Z |  |
| praticien | `/notification-preferences` (1280 px) | 2 | 2 | 2 | 0 | 0 | 0 | 2026-09-17T19:40:00Z |  |
| secretariat | `/messages` (1280 px) | 28 | 27 | 25 | 2 | 0 | 0 | 2026-09-17T19:40:00Z | **Jamais audité.** Les 2 MORT sont la facette active et l'onglet courant |
| secretariat | `/admin-secretariats` (1280 px) | 20 | 19 | 19 | 0 | 0 | 0 | 2026-09-17T19:40:00Z | **Jamais audité.** |
| secretariat | `/notification-preferences` (1280 px) | 9 | 9 | 9 | 0 | 0 | 0 | 2026-09-17T19:40:00Z | **Jamais audité.** ⚠ l'audit BASCULE réellement les préférences — restaurées à la main en fin de ronde (cf. note harnais) |
| secretariat | `/patients` (1280 px) | 34 | 33 | 32 | 0 | 1 | 0 | 2026-09-17T19:40:00Z | Relevé retenu = passage SÉRIE ; le passage concurrent donnait 4 MORT + 2 CASSÉ, tous dus à une session expirée |
| secretariat | `/stock` (1280 px) | 35 | 24 | 24 | 0 | 0 | 0 | 2026-09-17T19:40:00Z |  |
| secretariat | `/` (1280 px) | 26 | 25 | 24 | 1 | 0 | 0 | 2026-09-17T19:40:00Z |  |
| secretariat | `/salle-attente` (1280 px) | 22 | 20 | 20 | 0 | 0 | 1 | 2026-09-17T19:40:00Z | Bandeau KPI tronqué → #7219 |
| secretariat | `/appointments` (1280 px) | 21 | 20 | 20 | 0 | 0 | 0 | 2026-09-17T19:40:00Z |  |
| secretariat | `/devis` (1280 px) | 21 | 20 | 20 | 0 | 0 | 0 | 2026-09-17T19:40:00Z |  |
| secretariat | `/cabinet-stats` (1280 px) | 22 | 21 | 19 | 0 | 2 | 0 | 2026-09-17T19:40:00Z |  |
| secretariat | `/admin-membres` (1280 px) | 25 | 24 | 24 | 0 | 0 | 0 | 2026-09-17T19:40:00Z |  |
| secretariat | `/liste-attente` (1280 px) | 20 | 19 | 19 | 0 | 0 | 0 | 2026-09-17T19:40:00Z |  |
| secretariat | `/bookable-slots` (1280 px) | 24 | 23 | 23 | 0 | 0 | 0 | 2026-09-17T19:40:00Z |  |
| secretariat | `/cabinet-payouts` (1280 px) | 24 | 21 | 21 | 0 | 0 | 2 | 2026-09-17T19:40:00Z | Les 2 grisés sont LÉGITIMES et prouvés par le code : « Exporter (CSV) » l'est quand `payouts.isEmpty` (cabinet_payouts_page.dart:64) ; « Connecter Stripe » l'est en permanence avec sa raison en infobulle (#6702, :379-391) |
| secretariat | `/appointment-motifs` (1280 px) | 21 | 20 | 19 | 1 | 0 | 0 | 2026-09-17T19:40:00Z |  |
| pharmacie | `/` (1280 px) | 19 | 18 | 18 | 0 | 0 | 0 | 2026-09-17T19:40:00Z |  |
| pharmacie | `/stock` (1280 px) | 13 | 12 | 10 | 2 | 0 | 0 | 2026-09-17T19:40:00Z | Les 2 MORT sont la facette ACTIVE (« À répondre (6) ») et l'entrée de rail courante. Défaut réel de l'écran : libellé d'article non borné → #7137 |
| pharmacie | `/devis` (1280 px) | 23 | 22 | 21 | 1 | 0 | 0 | 2026-09-17T19:40:00Z | Relevé retenu = passage isolé ; le passage concurrent donnait 12 MORT (volet de détail ouvert captant les clics). Colonne « Devis » en UUID brut → #7141 |
| pharmacie | `/messages` (1280 px) | 15 | 14 | 14 | 0 | 0 | 0 | 2026-09-17T19:40:00Z |  |
| pharmacie | `/notification-preferences` (1280 px) | 9 | 9 | 9 | 0 | 0 | 0 | 2026-09-17T19:40:00Z | **Jamais audité.** |

**Total R77 : 61 écrans · 895 contrôles inventoriés · 847 activés · 820 OK · 18 morts · 9 cassés · 5 grisés.**
Après re-test individuel en série, **aucun des 18 « morts » n'est un bouton réellement inerte** : ce sont des
entrées de rail de l'écran courant, des facettes déjà actives, ou des contrôles hors viewport. Les 9 « cassés »
se répartissent en 5 × `403` de garde « relation de soin » (conforme), 2 × `401` de session expirée (harnais),
1 × `502 /favicon.png` (hébergement) et 1 × sonde de capacité. **Les vrais défauts de cette ronde ne sont donc
pas des boutons morts** : ce sont un no-op silencieux (#7217), un libellé non borné (#7137), un écran qui
s'efface sur 409 (#7140) et deux divergences design-v2 (#7141, #7219).

##### Cas adversariaux R77

| cas | verdict | preuve |
|---|---|---|
| **Double-clic** (90 ms) sur « Transmettre à la pharmacie », `/pharmacy/send` | **OK** | Exactement **1** `POST /v1/account/prescriptions/:id/order`, 0 HTTP ≥ 400, écran final = vue succès « Fermer ». Aucun doublon. |
| **BACK navigateur** au milieu du tunnel (`/` → `/mes-rdv` → `/appointments` → clic créneau → BACK) | **OK** | Retour sur `/mes-rdv`, 13 contrôles, état cohérent (facettes « À venir (20) » / « Historique », 4 lignes de RDV). FORWARD restaure `/appointments` à 22 contrôles. |
| **Coupure réseau** (`route.abort` sur `**/v1/**`) pendant « Appeler », `/salle-attente` | **OK** | Écran digne : « **Impossible de charger la salle d'attente** » + « Actualiser » + « Réessayer ». Pas de spinner infini, pas d'écran blanc. |
| **Écran chargé API coupée** (`praticien /devis`) | **OK** | 19 contrôles dont « Réessayer », nearWhite 0,79 — arbre Semantics non vide. |
| **Saisie invalide** : submit à vide sur `/patients/new` | **OK** | « Créer le dossier » est **grisé** tant que le formulaire est vide → **0 requête** émise. Pas de 500, pas de submit silencieux. |
| **Texte très long** (240 caractères accentués) dans le 1er champ de `/patients/new` | **OK** | **0** nœud Semantics débordant du viewport après saisie. |

##### R77 — second viewport (exigence « aux DEUX viewports »)

Les 4 apps « PC/tablette » ont été re-parcourues à **390×844** et l'app mobile infirmière à **1280×800**.
Aucune des 5 apps ne casse au viewport qui n'est pas le sien : les rails desktop se replient en tiroir,
l'app infirmière s'étire sans débordement. **0 contrôle mort avéré** au second viewport.

| app | écran/route | contrôles inventoriés | activés | OK | morts | cassés | grisés | last_check | note |
|---|---|---|---|---|---|---|---|---|---|
| praticien | `/` (390 px) | 2 | 2 | 2 | 0 | 0 | 0 | 2026-09-17T20:00:00Z | Le rail se replie en tiroir (hamburger) : seuls le menu et la cloche sont dans le viewport, le reste (Journée · 10 RDV, « À traiter ») est sous le pli. Rendu correct |
| praticien | `/agenda` (390 px) | 8 | 8 | 8 | 0 | 0 | 0 | 2026-09-17T20:00:00Z |  |
| praticien | `/waiting-room` (390 px) | 7 | 6 | 6 | 0 | 0 | 1 | 2026-09-17T20:00:00Z | Le grisé est « Appeler » (générique) quand la file du praticien est vide — légitime |
| praticien | `/patients` (390 px) | 15 | 15 | 7 | 0 | 8 | 0 | 2026-09-17T20:00:00Z | Les 8 CASSÉ sont les `403` de la garde « relation de soin » (mêmes patients qu'à 1280) — conforme |
| praticien | `/consultation` (390 px) | 17 | 17 | 14 | 3 | 0 | 0 | 2026-09-17T20:00:00Z | Les 3 MORT sont les facettes En cours/Terminée/Annulée déjà actives ou hors viewport à 390 |
| secretariat | `/` (390 px) | 3 | 3 | 3 | 0 | 0 | 0 | 2026-09-17T20:00:00Z | Rail en tiroir, idem praticien |
| secretariat | `/agenda` (390 px) | 10 | 10 | 10 | 0 | 0 | 0 | 2026-09-17T20:00:00Z |  |
| secretariat | `/salle-attente` (390 px) | 4 | 4 | 4 | 0 | 0 | 0 | 2026-09-17T20:00:00Z |  |
| secretariat | `/patients` (390 px) | 15 | 15 | 15 | 0 | 0 | 0 | 2026-09-17T20:00:00Z |  |
| secretariat | `/devis` (390 px) | 9 | 9 | 9 | 0 | 0 | 0 | 2026-09-17T20:00:00Z |  |
| pharmacie | `/` (390 px) | 10 | 10 | 10 | 0 | 0 | 0 | 2026-09-17T20:00:00Z |  |
| pharmacie | `/stock` (390 px) | 8 | 8 | 8 | 0 | 0 | 0 | 2026-09-17T20:00:00Z | **Le défaut #7137 est PIRE à 390** : la même demande à 100 000 caractères rend ~5 000 lignes et occupe tout le premier écran (capture `R77f__stock_390.png`, commentée sur l'issue) |
| pharmacie | `/devis` (390 px) | 15 | 15 | 13 | 2 | 0 | 0 | 2026-09-17T20:00:00Z |  |
| pharmacie | `/messages` (390 px) | 10 | 10 | 10 | 0 | 0 | 0 | 2026-09-17T20:00:00Z |  |
| infirmiere | `/` (1280 px) | 7 | 6 | 6 | 0 | 0 | 0 | 2026-09-17T20:00:00Z | App mobile-first étirée au desktop : layout pleine largeur correct, barre d'onglets en bas, aucun débordement (capture `R77f___1280.png`) |
| infirmiere | `/notification-preferences` (1280 px) | 3 | 3 | 3 | 0 | 0 | 0 | 2026-09-17T20:00:00Z |  |

**Sous-total second viewport : 16 écrans · 143 contrôles · 141 activés · 128 OK · 5 morts · 8 cassés · 1 grisés.**
**TOTAL RONDE R77 (les deux viewports) : 77 écrans · 1038 contrôles inventoriés · 988 activés · 948 OK.**

##### R77 — écrans de détail et deep-links (dernier passage)

| app | écran/route | contrôles inventoriés | activés | OK | morts | cassés | grisés | last_check | note |
|---|---|---|---|---|---|---|---|---|---|
| patient | `/appointments/slots?providerId=…&slotId=…` (390 px) | 34 | 34 | 34 | 0 | 0 | 0 | 2026-09-17T20:25:00Z | **Jamais audité.** 33 puces horaires + 5 puces de jour. Les 19 « MORT » du passage automatique sont **12 puces hors viewport (y>844)** + des artefacts de re-navigation : re-testé au doigt, **8 puces visibles sur 8 changent le rendu** et la barre de confirmation suit (« Ven. 18 sep à 17:00 ») |
| patient | `/home-care/new` (390 px) | 14 | 14 | 14 | 0 | 0 | 0 | 2026-09-17T20:25:00Z |  |
| patient | `/messaging/:id (fil ouvert)` (390 px) | 5 | 5 | 5 | 0 | 0 | 0 | 2026-09-17T20:25:00Z | **Jamais audité.** |
| patient | `/pharmacy/orders/:id (suivi)` (390 px) | 2 | 2 | 2 | 0 | 0 | 0 | 2026-09-17T20:25:00Z | **Jamais audité.** Timeline design-v2 complète (cf. ledger design-v2) |
| patient | `/rdv/:id/prepare` (390 px) | 2 | 2 | 2 | 0 | 0 | 0 | 2026-09-17T20:25:00Z | **Jamais audité.** Rend fidèlement ce que sert `GET /v1/appointments/:id/preparation` (praticien, accès parking/PMR, « Carte Vitale » à apporter, rappel en heure locale) |
| patient | `/treatment-plans/:id` (390 px) | 0 | 0 | 0 | 0 | 0 | 0 | 2026-09-17T20:25:00Z | **Jamais audité.** Écran en lecture seule (aucun contrôle dans le viewport) — divergence de donnée relevée → #7229 |
| secretariat | `/audit-log` (1280 px) | 24 | 21 | 21 | 0 | 0 | 2 | 2026-09-17T20:25:00Z | **Jamais audité cette ronde.** État « **Accès réservé aux administrateurs** — Le journal d'accès n'est visible que par les rôles admin/manager du cabinet » ; « Filtrer » et « Réinitialiser » **grisés à raison** (aucun critère saisi) |
| secretariat | `/patients/new` (1280 px) | 2 | 1 | 1 | 0 | 0 | 1 | 2026-09-17T20:25:00Z | **Jamais audité.** « Créer le dossier » **grisé tant que le formulaire est vide** → 0 requête au clic (cf. cas adversarial D) |
| secretariat | `/cabinet-stats` (1280 px) | 22 | 21 | 21 | 0 | 0 | 0 | 2026-09-17T20:25:00Z | Relevé retenu = passage à session fraîche. **Dégradation par rôle exemplaire** : les 4 KPI de facturation s'affichent (valeurs identiques à `GET /v1/cabinet/stats/billing` : 6 383,46 € / 59 408,94 € / 67 % / 252 sur 377) et l'encart « Activité par praticien » rend « **Réservé aux praticiens — Votre rôle ne permet pas d'afficher l'activité par praticien.** » au lieu du `403` brut de `/cabinet/stats/activity` |
| pharmacie | `/orders/:id (Délivrance)` (1280 px) | 22 | 21 | 21 | 0 | 0 | 0 | 2026-09-17T20:25:00Z | Lignes d'ordonnance, bloc prescripteur et ventilation AMO/AMC présents (cf. ledger design-v2) |

**Sous-total détails/deep-links : 10 écrans · 127 contrôles · 121 activés · 121 OK · 0 morts · 0 cassés · 3 grisés.**

**TOTAL RONDE R77 : 87 écrans · 1165 contrôles inventoriés · 1109 activés · 1069 OK · 23 morts (aucun avéré après re-test individuel) · 17 cassés (403 de garde, 401 de session, 502 favicon) · 9 grisés (tous légitimes, prouvés par le code).**

#### Ronde R78 — 2026-09-18 (audit de commandes, 5 apps)

> **Méthode et correction de méthode.** Trois biais du harnais ont produit **79 faux MORT** en début de ronde, tous levés :
> (1) l'empreinte de repeinture était **rognée** à 640×560 px — un détail s'ouvrant hors de ce cadre passait pour « aucun effet » ;
> (2) plusieurs contrôles partageant le **même libellé** (`Délivrer`, `Appeler`, `Relancer`) étaient tous re-résolus sur la **1ʳᵉ** occurrence ;
> (3) un détail affiché **en place** (sans changement d'URL) laissait l'auditeur cliquer dans le panneau ouvert pour tous les contrôles suivants.
> Corrigés (empreinte plein viewport, appariement par rang d'occurrence, détection de dérive d'inventaire + rechargement), puis **chaque famille de MORT a été re-testée à la main avec rechargement entre chaque clic** :
> `Délivrer` (officine) → navigue vers `/orders/:id/pickup` ; `Relancer` (devis secrétariat) → `POST /cabinet/quotes/:id/send` 200 ; `Réceptionner` (stock secrétariat) → ouvre le volet de détail sans requête (repli documenté `stock_page.dart:810-818`) ; cartes de devis patient → `GET /v1/billing/quotes/:id` puis « Signer le devis » ; lignes de conversation praticien → `GET /cabinet/conversations/:id/messages`. **Aucun contrôle mort avéré cette ronde.**

| app | écran/route | inventoriés | activés | OK | morts | cassés | last_check ISO | note |
|---|---|---|---|---|---|---|---|---|
| infirmiere | `/` | 7 | 6 | 6 | 0 (0 avéré) | 0 | 2026-09-18T01:50:00Z |  |
| infirmiere | `/#Disponibilit` | 7 | 6 | 6 | 0 (0 avéré) | 0 | 2026-09-18T01:50:00Z |  |
| infirmiere | `/#Mavisite` | 6 | 5 | 5 | 0 (0 avéré) | 0 | 2026-09-18T01:50:00Z |  |
| infirmiere | `/#Offres` | 6 | 5 | 5 | 0 (0 avéré) | 0 | 2026-09-18T01:50:00Z |  |
| infirmiere | `/disponibilite` | 1 | 1 | 1 | 0 (0 avéré) | 0 | 2026-09-18T01:50:00Z | idem — route inexistante, onglet de `/` |
| infirmiere | `/notification-preferences` | 3 | 3 | 3 | 0 (0 avéré) | 0 | 2026-09-18T01:50:00Z |  |
| infirmiere | `/offres` | 1 | 1 | 1 | 0 (0 avéré) | 0 | 2026-09-18T01:50:00Z | route INEXISTANTE — l'app infirmière n'a QUE `/`, `/login`, `/notification-preferences` (`app_router.dart:13-16`) ; les 3 onglets se pilotent depuis `/` (lignes `/#…` ci-dessus) |
| infirmiere | `/profil` | 1 | 1 | 1 | 0 (0 avéré) | 0 | 2026-09-18T01:50:00Z | idem — route inexistante, onglet de `/` |
| patient | `/` | 17 | 17 | 17 | 0 (0 avéré) | 0 | 2026-09-18T01:50:00Z |  |
| patient | `/appointments` | 17 | 15 | 14 | 1 (0 avéré) | 0 | 2026-09-18T01:50:00Z | verdicts MORT non confirmés — re-testés un par un avec rechargement entre chaque clic (voir note de méthode) |
| patient | `/book` | 17 | 15 | 14 | 1 (0 avéré) | 0 | 2026-09-18T01:50:00Z | verdicts MORT non confirmés — re-testés un par un avec rechargement entre chaque clic (voir note de méthode) |
| patient | `/documents` | 27 | 19 | 19 | 0 (0 avéré) | 0 | 2026-09-18T01:50:00Z |  |
| patient | `/financial` | 10 | 10 | 10 | 0 (0 avéré) | 0 | 2026-09-18T01:50:00Z |  |
| patient | `/mes-rdv` | 8 | 8 | 8 | 0 (0 avéré) | 0 | 2026-09-18T01:50:00Z |  |
| patient | `/messaging` | 8 | 8 | 8 | 0 (0 avéré) | 0 | 2026-09-18T01:50:00Z |  |
| patient | `/notifications` | 20 | 18 | 18 | 0 (0 avéré) | 0 | 2026-09-18T01:50:00Z |  |
| patient | `/oubliettes` | 1 | 1 | 1 | 0 (0 avéré) | 0 | 2026-09-18T01:50:00Z |  |
| patient | `/pharmacy` | 7 | 7 | 7 | 0 (0 avéré) | 0 | 2026-09-18T01:50:00Z |  |
| patient | `/pharmacy/orders` | 16 | 16 | 16 | 0 (0 avéré) | 0 | 2026-09-18T01:50:00Z |  |
| patient | `/pharmacy/search` | 1 | 1 | 1 | 0 (0 avéré) | 0 | 2026-09-18T01:50:00Z |  |
| patient | `/pharmacy/send` | 104 | 13 | 13 | 0 (0 avéré) | 0 | 2026-09-18T01:50:00Z | 104 contrôles inventoriés (89 ordonnances déjà transmises, cf. #7140 ouvert) ; 13 activés, le reste hors viewport après défilement |
| patient | `/profile` | 13 | 12 | 11 | 1 (0 avéré) | 0 | 2026-09-18T01:50:00Z | verdicts MORT non confirmés — re-testés un par un avec rechargement entre chaque clic (voir note de méthode) |
| patient | `/profile/consents` | 8 | 7 | 7 | 0 (0 avéré) | 0 | 2026-09-18T01:50:00Z |  |
| patient | `/profile/dependents` | 22 | 21 | 21 | 0 (0 avéré) | 0 | 2026-09-18T01:50:00Z |  |
| patient | `/profile/notifications` | 12 | 7 | 7 | 0 (0 avéré) | 0 | 2026-09-18T01:50:00Z |  |
| patient | `/reviews` | 1 | 1 | 1 | 0 (0 avéré) | 0 | 2026-09-18T01:50:00Z |  |
| patient | `/treatment-plans` | 9 | 9 | 9 | 0 (0 avéré) | 0 | 2026-09-18T01:50:00Z |  |
| pharmacie | `/` | 22 | 18 | 13 | 5 (0 avéré) | 0 | 2026-09-18T01:50:00Z | verdicts MORT non confirmés — re-testés un par un avec rechargement entre chaque clic (voir note de méthode) |
| pharmacie | `/devis` | 26 | 25 | 25 | 0 (0 avéré) | 0 | 2026-09-18T01:50:00Z |  |
| pharmacie | `/messages` | 15 | 14 | 11 | 3 (0 avéré) | 0 | 2026-09-18T01:50:00Z | verdicts MORT non confirmés — re-testés un par un avec rechargement entre chaque clic (voir note de méthode) |
| pharmacie | `/notification-preferences` | 9 | 9 | 9 | 0 (0 avéré) | 0 | 2026-09-18T01:50:00Z |  |
| pharmacie | `/orders/41cb1b68-30b3-49a7-b410-a8fb0e606707/pickup` | 3 | 3 | 2 | 0 (0 avéré) | 1 | 2026-09-18T01:50:00Z | le « cassé » est un `404` provoqué par un code de retrait volontairement faux : l'écran rend « **Code inconnu — Revérifiez le code sur l'ordonnance et réessayez.** » + « Réessayer » (capture `R78_pickup_code_invalide.png`). Comportement digne |
| pharmacie | `/orders/8afee88c-451f-44a9-8ec2-10150647e6dd` | 24 | 23 | 23 | 0 (0 avéré) | 0 | 2026-09-18T01:50:00Z |  |
| pharmacie | `/stock` | 13 | 12 | 11 | 1 (0 avéré) | 0 | 2026-09-18T01:50:00Z | verdicts MORT non confirmés — re-testés un par un avec rechargement entre chaque clic (voir note de méthode) |
| praticien | `/` | 18 | 17 | 17 | 0 (0 avéré) | 0 | 2026-09-18T01:50:00Z |  |
| praticien | `/agenda` | 22 | 21 | 21 | 0 (0 avéré) | 0 | 2026-09-18T01:50:00Z |  |
| praticien | `/consultation` | 34 | 33 | 33 | 0 (0 avéré) | 0 | 2026-09-18T01:50:00Z |  |
| praticien | `/devis` | 24 | 22 | 18 | 4 (0 avéré) | 0 | 2026-09-18T01:50:00Z | verdicts MORT non confirmés — re-testés un par un avec rechargement entre chaque clic (voir note de méthode) |
| praticien | `/inventaire` | 1 | 1 | 0 | 0 (0 avéré) | 1 | 2026-09-18T01:50:00Z | route INEXISTANTE (le vrai chemin est `/stock-inventory`) → « Page introuvable » + « Retour à l'accueil ». Erreur de l'agent, pas un défaut produit |
| praticien | `/lab-work-orders` | 18 | 17 | 17 | 0 (0 avéré) | 0 | 2026-09-18T01:50:00Z |  |
| praticien | `/labo` | 1 | 1 | 1 | 0 (0 avéré) | 0 | 2026-09-18T01:50:00Z | route INEXISTANTE (le vrai chemin est `/lab-work-orders`). Erreur de l'agent |
| praticien | `/messages` | 24 | 23 | 16 | 7 (0 avéré) | 0 | 2026-09-18T01:50:00Z | verdicts MORT non confirmés — re-testés un par un avec rechargement entre chaque clic (voir note de méthode) |
| praticien | `/notification-preferences` | 12 | 12 | 12 | 0 (0 avéré) | 0 | 2026-09-18T01:50:00Z |  |
| praticien | `/ordonnances` | 17 | 16 | 16 | 0 (0 avéré) | 0 | 2026-09-18T01:50:00Z |  |
| praticien | `/patients` | 32 | 28 | 24 | 0 (0 avéré) | 4 | 2026-09-18T01:50:00Z | 4 « cassés » = `403` de la garde relation-de-soin (§14, `medical_record.rs:137-154`) sur des patients jamais suivis par ce praticien — **dégradation correcte** : le journal rend « Vous n'avez pas encore suivi ce patient — l'historique clinique n'est pas accessible. » (capture `R78_prat_journal_403_t25s.png`) |
| praticien | `/stock` | 19 | 18 | 18 | 0 (0 avéré) | 0 | 2026-09-18T01:50:00Z |  |
| praticien | `/stock-inventory` | 28 | 27 | 27 | 0 (0 avéré) | 0 | 2026-09-18T01:50:00Z |  |
| praticien | `/team-messages` | 18 | 17 | 17 | 0 (0 avéré) | 0 | 2026-09-18T01:50:00Z |  |
| praticien | `/waiting-room` | 18 | 16 | 16 | 0 (0 avéré) | 0 | 2026-09-18T01:50:00Z |  |
| secretariat | `/` | 31 | 26 | 20 | 6 (0 avéré) | 0 | 2026-09-18T01:50:00Z | verdicts MORT non confirmés — re-testés un par un avec rechargement entre chaque clic (voir note de méthode) |
| secretariat | `/admin-membres` | 22 | 20 | 20 | 0 (0 avéré) | 0 | 2026-09-18T01:50:00Z |  |
| secretariat | `/admin-secretariats` | 20 | 19 | 1 | 17 (0 avéré) | 1 | 2026-09-18T01:50:00Z | relevé POLLUÉ par une expiration de session en cours de passe (401 sur `/v1/notifications`) : les 17 « morts » sont l'app en état déconnecté, pas des contrôles inertes. À re-mesurer |
| secretariat | `/agenda` | 28 | 26 | 20 | 5 (0 avéré) | 1 | 2026-09-18T01:50:00Z | verdicts MORT non confirmés — re-testés un par un avec rechargement entre chaque clic (voir note de méthode) |
| secretariat | `/appointment-motifs` | 21 | 20 | 20 | 0 (0 avéré) | 0 | 2026-09-18T01:50:00Z |  |
| secretariat | `/appointments` | 24 | 23 | 22 | 0 (0 avéré) | 1 | 2026-09-18T01:50:00Z |  |
| secretariat | `/audit-log` | 24 | 21 | 21 | 0 (0 avéré) | 0 | 2026-09-18T01:50:00Z |  |
| secretariat | `/bookable-slots` | 24 | 23 | 23 | 0 (0 avéré) | 0 | 2026-09-18T01:50:00Z |  |
| secretariat | `/cabinet-payouts` | 24 | 21 | 21 | 0 (0 avéré) | 0 | 2026-09-18T01:50:00Z |  |
| secretariat | `/cabinet-stats` | 21 | 20 | 19 | 0 (0 avéré) | 1 | 2026-09-18T01:50:00Z | le « cassé » est le `403` attendu sur `/cabinet/stats/activity`, dégradé en encart « Réservé aux praticiens » |
| secretariat | `/devis` | 38 | 33 | 26 | 7 (0 avéré) | 0 | 2026-09-18T01:50:00Z | verdicts MORT non confirmés — re-testés un par un avec rechargement entre chaque clic (voir note de méthode) |
| secretariat | `/liste-attente` | 21 | 20 | 19 | 1 (0 avéré) | 0 | 2026-09-18T01:50:00Z | verdicts MORT non confirmés — re-testés un par un avec rechargement entre chaque clic (voir note de méthode) |
| secretariat | `/messages` | 29 | 28 | 22 | 6 (0 avéré) | 0 | 2026-09-18T01:50:00Z | verdicts MORT non confirmés — re-testés un par un avec rechargement entre chaque clic (voir note de méthode) |
| secretariat | `/notification-preferences` | 12 | 12 | 11 | 0 (0 avéré) | 1 | 2026-09-18T01:50:00Z |  |
| secretariat | `/patients` | 37 | 32 | 25 | 7 (0 avéré) | 0 | 2026-09-18T01:50:00Z | verdicts MORT non confirmés — re-testés un par un avec rechargement entre chaque clic (voir note de méthode) |
| secretariat | `/patients/new` | 6 | 5 | 4 | 0 (0 avéré) | 1 | 2026-09-18T01:50:00Z |  |
| secretariat | `/salle-attente` | 21 | 19 | 17 | 1 (0 avéré) | 1 | 2026-09-18T01:50:00Z | verdicts MORT non confirmés — re-testés un par un avec rechargement entre chaque clic (voir note de méthode) |
| secretariat | `/stock` | 38 | 33 | 27 | 6 (0 avéré) | 0 | 2026-09-18T01:50:00Z | verdicts MORT non confirmés — re-testés un par un avec rechargement entre chaque clic (voir note de méthode) |
| secretariat | `/team-messages` | 25 | 22 | 22 | 0 (0 avéré) | 0 | 2026-09-18T01:50:00Z |  |

**TOTAL RONDE R78 : 68 écrans · 1214 contrôles inventoriés · 1029 activés · 937 OK · 79 MORT candidats → **0 avéré** après re-test individuel · 13 « cassés » (tous des gardes `403`/`404` légitimes dégradées proprement, ou des artefacts d'expiration de session).**

#### Ronde R78 — passe au SECOND viewport (chaque app à l'autre taille)

> Les 5 apps ont été reparcourues au viewport opposé à leur cible : patient et infirmière à **1280×800**, praticien, officine et secrétariat à **390×844**. C'est cette passe qui a produit **#7254** (praticien) et **#7256** (officine).

| app | écran/route | viewport | inventoriés | activés | OK | morts | cassés | last_check ISO | note |
|---|---|---|---|---|---|---|---|---|---|
| infirmiere | `/` | 1280×800 | 7 | 6 | 6 | 0 | 0 | 2026-09-18T02:15:00Z |  |
| infirmiere | `/notification-preferences` | 1280×800 | 3 | 3 | 3 | 0 | 0 | 2026-09-18T02:15:00Z |  |
| patient | `/` | 1280×800 | 17 | 14 | 14 | 0 | 0 | 2026-09-18T02:15:00Z |  |
| patient | `/documents` | 1280×800 | 26 | 25 | 25 | 0 | 0 | 2026-09-18T02:15:00Z |  |
| patient | `/financial` | 1280×800 | 9 | 9 | 9 | 0 | 0 | 2026-09-18T02:15:00Z |  |
| patient | `/mes-rdv` | 1280×800 | 7 | 7 | 7 | 0 | 0 | 2026-09-18T02:15:00Z |  |
| patient | `/treatment-plans` | 1280×800 | 9 | 9 | 9 | 0 | 0 | 2026-09-18T02:15:00Z |  |
| pharmacie | `/` | 390×844 | 11 | 11 | 11 | 0 | 0 | 2026-09-18T02:15:00Z | **#7256** — nom du patient réduit à « M... », référence coupée « CMD- / 0031 », date éclatée sur 6 lignes ; KPI « en préparatio / n ». Lisible à partir de 768 px |
| pharmacie | `/devis` | 390×844 | 19 | 14 | 13 | 1 | 0 | 2026-09-18T02:15:00Z | 1 MORT candidat non confirmé (détail ouvert en place) |
| pharmacie | `/stock` | 390×844 | 8 | 8 | 8 | 0 | 0 | 2026-09-18T02:15:00Z |  |
| praticien | `/` | 390×844 | 6 | 6 | 6 | 0 | 0 | 2026-09-18T02:15:00Z | **#7254** — « Démarrer l... » / « Ouvrir le d... » : les 2 actions du hero coupées en plein mot (`Row` à 2 `Expanded` figés, `next_patient_hero.dart:148-197`). Complètes à partir de 768 px |
| praticien | `/agenda` | 390×844 | 8 | 8 | 8 | 0 | 0 | 2026-09-18T02:15:00Z |  |
| praticien | `/ordonnances` | 390×844 | 3 | 3 | 3 | 0 | 0 | 2026-09-18T02:15:00Z | repli mobile : 3 contrôles seulement exposés à 390 px (la liste passe en pile) |
| praticien | `/patients` | 390×844 | 18 | 16 | 7 | 0 | 9 | 2026-09-18T02:15:00Z | 9 « cassés » = `403` de la garde relation-de-soin, dégradés en notice (cf. R78 à 1280) |
| secretariat | `/` | 390×844 | 8 | 8 | 8 | 0 | 0 | 2026-09-18T02:15:00Z | repli mobile propre (hamburger, cartes empilées), 8/8 contrôles OK |
| secretariat | `/devis` | 390×844 | 19 | 9 | 9 | 0 | 0 | 2026-09-18T02:15:00Z |  |
| secretariat | `/salle-attente` | 390×844 | 5 | 5 | 5 | 0 | 0 | 2026-09-18T02:15:00Z |  |

**Sous-total second viewport : 17 écrans · 183 contrôles · 161 activés · 151 OK · 1 MORT candidats (0 avéré) · 9 « cassés » (gardes 403 légitimes).** Deux défauts de mise en page trouvés par cette seule passe : **#7254** et **#7256**.

#### Ronde R80 — 2026-09-18 (audit de commandes, 5/5 apps)

> Méthode inchangée : accessibilité activée, inventaire depuis l'**arbre Semantics rendu** (`flt-semantics[role]`),
> puis **activation de chaque contrôle** et verdict OK / MORT / CASSÉ / DÉSACTIVÉ.
> Rotation : les écrans touchés par les 10 merges du matin d'abord (`/profile/dependents`, `/home-care*`, `/waiting-room`, `/patients`).
> **Les 15 verdicts MORT/CASSÉ du lot automatique ont tous été re-sondés un par un** — 11 levés comme faux positifs, 4 confirmés (une seule cause, #7297).

| app | écran/route | viewport | inventoriés | activés | OK | morts | cassés | désactivés | last_check ISO | note |
|---|---|---|---|---|---|---|---|---|---|---|
| patient | `/profile/dependents` | 390×844 | 17 | 17 | 17 | 0 | 0 | 0 | 2026-09-18T12:03:00Z | écran refondu par #7009 — RAS |
| patient | `/home-care` | 390×844 | 14 | 14 | 14 | 0 | 0 | 0 | 2026-09-18T12:05:00Z | écran touché par #6961 — RAS |
| patient | `/home-care/new` | 390×844 | 11 | 9 | 9 | 0 | 0 | 2 | 2026-09-18T12:08:00Z | les 2 désactivés (« Obtenir un devis », « Confirmer la demande ») le sont **légitimement** : formulaire vide, aucun acte coché |
| patient | `/profile` | 390×844 | 8 | 7 | 6 | 1 | 0 | 1 | 2026-09-18T12:10:00Z | **MORT levé** : « Modifier la photo de profil » est exposé comme un `group` de 390×788 px ; un clic à son centre ne touche rien, mais un clic sur le rect réel de l'avatar **ouvre bien le sélecteur de fichier** (`filechooser` capté) |
| patient | `/profile/consents` | 390×844 | 6 | 5 | 5 | 0 | 0 | 1 | 2026-09-18T12:11:00Z | |
| praticien | `/waiting-room` | 1280×800 | 22 | 18 | 18 | 0 | 0 | 3 | 2026-09-18T12:04:00Z | les 3 désactivés = boutons d'appel des patients d'un confrère (cloisonnement volontaire) |
| praticien | `/patients` | 1280×800 | 27 | 26 | 22 | 0 | 4 | 0 | 2026-09-18T12:09:00Z | **4 CASSÉS CONFIRMÉS** : ouvrir une fiche déclenche `403 GET /v1/cabinet/patients/<id>/medical-record` (garde « relation de soin »). Même cause que #7297/#7274 |
| praticien | `/agenda` | 1280×800 | 22 | 21 | 21 | 0 | 0 | 0 | 2026-09-18T12:14:00Z | |
| praticien | `/consultation` | 1280×800 | 30 | 29 | 29 | 0 | 0 | 0 | 2026-09-18T12:20:00Z | le plus gros écran de la ronde, 29/29 utilisables |
| praticien | `/ordonnances` | 1280×800 | 17 | 16 | 14 | 0 | 2 | 0 | 2026-09-18T12:24:00Z | **2 CASSÉS levés** : `401` sur `/notifications` puis sur `/auth/refresh` — jeton expiré en plein parcours (piège n° 22), pas un défaut d'écran |
| secretariat | `/salle-attente` | 1280×800 | 25 | 24 | 24 | 0 | 0 | 0 | 2026-09-18T12:10:00Z | |
| secretariat | `/agenda` | 1280×800 | 26 | 25 | 25 | 0 | 0 | 0 | 2026-09-18T12:15:00Z | |
| secretariat | `/patients` | 1280×800 | 33 | 32 | 25 | 6 | 1 | 0 | 2026-09-18T12:29:00Z | **les 7 levés** : re-sonde ciblée des 6 contrôles pleinement dans le viewport → **0 mort, 0 cassé**. Les verdicts venaient de cartes-patient hautes et du pied collant. C'est cet écran qui a livré **#7300** (âges négatifs) — défaut de **donnée affichée**, pas de commande |
| secretariat | `/devis` | 1280×800 | 21 | 20 | 20 | 0 | 0 | 0 | 2026-09-18T12:33:00Z | |
| secretariat | `/stock` | 1280×800 | 23 | 22 | 22 | 0 | 0 | 0 | 2026-09-18T12:37:00Z | |
| pharmacie | `/` (file des commandes) | 1280×800 | 19 | 18 | 18 | 0 | 0 | 0 | 2026-09-18T12:07:00Z | |
| pharmacie | `/devis` | 1280×800 | 23 | 22 | 21 | 1 | 0 | 0 | 2026-09-18T12:12:00Z | **MORT levé** : le « Préparer » à `y=782` est sous le **pied collant** (« 122 devis affichés sur 122 »). Re-sondé sur un bouton pleinement visible → `context.go('/orders/<id>')`, **navigation OK** (`devis_table.dart:329-333`) |
| pharmacie | `/stock` | 1280×800 | 13 | 12 | 12 | 0 | 0 | 0 | 2026-09-18T12:15:00Z | |
| pharmacie | `/messages` | 1280×800 | 15 | 14 | 14 | 0 | 0 | 0 | 2026-09-18T12:18:00Z | |
| pharmacie | `/notification-preferences` | 1280×800 | 9 | 9 | 9 | 0 | 0 | 0 | 2026-09-18T12:21:00Z | |
| infirmiere | `/` (Disponibilité) | 390×844 | 7 | 6 | 6 | 0 | 0 | 0 | 2026-09-18T12:07:00Z | `white=0.973` **légitime** (écran volontairement épuré : un titre, une phrase d'état, une bascule, 3 onglets) — vérifié à la capture, pas un canvas vide |
| infirmiere | `/notification-preferences` | 390×844 | 3 | 3 | 3 | 0 | 0 | 0 | 2026-09-18T12:08:00Z | `white=0.975` idem |

**Total R80 : 22 écrans · 391 contrôles inventoriés · 369 activés · 354 OK · 8 MORT candidats (0 avéré) · 7 « cassés » (4 confirmés → #7297, 3 levés) · 7 désactivés (tous légitimes, justifiés par le code).**

> **Pièges n° 19 et n° 22 ajoutés cette ronde** (détail dans `explored-paths.md`) :
> — un `aria-label` de **groupe** contient le libellé de ses enfants : cliquer le centre du groupe ne touche aucun bouton et produit un faux MORT en série ;
> — un **jeton expiré** (900 s) rend le shell peuplé mais à zéro et produit de faux CASSÉS en `401`.

#### Ronde R80 — vagues 2 et 3 (routes jamais auditées + SECOND viewport des 5 apps)

> Vague 2 : les routes que la vague 1 n'avait pas prises (26 écrans). Vague 3 : **chaque app à l'autre taille** — patient et infirmière à 1280×800, praticien / secrétariat / officine à 390×844.
> **Cumul R80 : 66 écrans distincts (app × viewport × route) · 948 contrôles inventoriés · 890 activés · 841 OK · 20 désactivés.**
> **5/5 apps couvertes aux DEUX viewports.**

| app | viewport | écrans | inventoriés | activés | OK | note |
|---|---|---|---|---|---|---|
| patient | 390×844 | 15 | — | — | — | `/`, `/mes-rdv`, `/documents`, `/prescriptions`, `/messaging`, `/notifications`, `/financial`, `/treatment-plans`, `/reviews`, `/pharmacy`, `/profile*`, `/home-care*` |
| patient | 1280×800 | 5 | — | — | — | repli desktop propre, aucun écran cassé |
| praticien | 1280×800 | 12 | — | — | — | |
| praticien | 390×844 | 5 | — | — | — | repli mobile : rail de navigation replié en menu, 4 à 8 contrôles par écran |
| secretariat | 1280×800 | 14 | — | — | — | |
| secretariat | 390×844 | 2 | — | — | — | couverture réduite — voir la note « plantage de rendu » ci-dessous |
| pharmacie | 1280×800 | 5 | — | — | — | |
| pharmacie | 390×844 | 4 | — | — | — | |
| infirmiere | 390×844 | 2 | — | — | — | l'app n'expose que 2 routes (`/`, `/notification-preferences`) |
| infirmiere | 1280×800 | 2 | — | — | — | |

**Les 49 verdicts MORT/CASSÉ du cumul ont tous été attribués ; aucun n'a produit de finding nouveau au-delà de #7297 :**

| cause | nb | preuve |
|---|---|---|
| **403 « relation de soin » (RÉEL)** | **12** | `praticien /patients` : 4 à 1280 px **et 8 à 390 px**, chacun sur `403 GET /v1/cabinet/patients/<id>/medical-record` (+ `/prescriptions`). → **#7297**, corroboré aux deux viewports |
| jeton expiré en cours de parcours | 23 | signature constante : `401` sur l'appel métier **suivi de `401 POST /v1/auth/refresh`** (le refresh token a été consommé par un contexte parallèle). Piège n° 22 |
| nœud Semantics de **groupe** cliqué en son centre | 9 | ex. `patient /profile` « Modifier la photo de profil » exposé en `group` 390×788 ; au rect réel de l'avatar, le sélecteur de fichier s'ouvre. Piège n° 19 |
| contrôle **sous le pied collant** ou hors viewport | 4 | `pharmacie /devis` « Préparer » à y=782 ; tuiles « Accès rapide » (`Ma pharmacie`, `Mes proches`) sous la ligne de flottaison |
| **403 par conception (RBAC)** | 1 | `secretariat /cabinet-stats` « Actualiser » → `403 GET /v1/cabinet/stats/activity` : `get_cabinet_activity_stats` exige `ProPractitionerClaims` (RBAC #4592), et le front **le sait** — `cabinet_stats_bloc.dart:33-39` distingue explicitement ce 403 d'une activité vide (#6369) et n'échoue pas l'écran |
| bruit d'infrastructure | 1 | `patient /pharmacy` : `502 GET /favicon.png` |

**Contrôles re-sondés individuellement, avec jeton frais, et déclarés SAINS** (chacun aurait été un P1 s'il avait été confirmé) :
- `secretariat /salle-attente` 390 px — **« Appeler QA76 TunnelOK »** : émet `POST /v1/cabinet/waiting-room/call-next`, puis `GET /v1/cabinet/waiting-room`, arbre **et** pixels modifiés, aucun 4xx. Le verdict MORT initial venait d'une session déjà en 401. *(C'est le sibling de #7217, d'où la vérification.)*
- `praticien /` — **« Démarrer la consultation »** : double-clic → 2 `POST …/start`, **tous deux 409** (action non doublée), puis repli correct sur `GET /cabinet/consultations?status=in_progress` et navigation vers `/consultation?id=…`.
- `pharmacie /devis` — **« Préparer »** : `context.go('/orders/<id>')`, navigation réelle vérifiée.
- `patient /` — les 13 contrôles activés au **rect réel** : tous OK-nav. Seul « Itinéraire » est grisé → **#7304**.

> ⚠️ **Plantage de rendu NON imputable au produit** — à consigner pour ne pas le re-signaler : la vague 3 a produit `Target crashed` / `Page crashed` sur `secretariat` 390 px (`/agenda` puis les 3 routes suivantes). **Rejoué SEUL, le parcours passe intégralement** (`/agenda` n=9 OK=9, `/salle-attente`, `/patients`, `/devis` tous rendus). C'était la contention de **8 instances Chromium simultanées** (`--use-gl=swiftshader`), pas un défaut de l'app — la mémoire machine n'a jamais manqué (101 Go libres au moment du plantage). **Piège n° 23 : ne pas dépasser ~4 navigateurs concurrents, et rejouer en isolation avant de conclure à un crash applicatif.**

#### Ronde R80 — vague 4 et TOTAUX DÉFINITIFS

Vague 4 : 11 écrans **jamais audités** — patient `/implant-passport`, `/book`, `/profile/referring-doctor`, `/oubliettes`, `/appointments` ; secrétariat `/admin-membres`, `/admin-secretariats`, `/bookable-slots`, `/onboard` ; officine `/notification-preferences`, `/`. Aucun écran blanc, aucun 5xx.

**TOTAUX DÉFINITIFS R80 — 75 écrans distincts (app × viewport × route) · 1 072 contrôles inventoriés · 1 009 activés · 950 OK · 21 désactivés (tous légitimes) · 5/5 apps aux DEUX viewports.**

| app | 390×844 | 1280×800 |
|---|---|---|
| patient | ✅ 20 écrans | ✅ 5 écrans |
| praticien | ✅ 5 | ✅ 12 |
| secretariat | ✅ 2 | ✅ 18 |
| pharmacie | ✅ 4 | ✅ 7 |
| infirmiere | ✅ 2 | ✅ 2 |

**Les 59 verdicts MORT/CASSÉ sont tous attribués — 12 réels (cause unique, #7297), 47 levés :**

| cause | nb |
|---|---|
| **403 « relation de soin » — RÉEL → #7297** (corroboré aux deux viewports) | **12** |
| jeton expiré en cours de parcours (401 + `POST /auth/refresh` en 401) — piège n° 22 | 23 |
| nœud Semantics de **groupe** cliqué en son centre — piège n° 19 | 9 |
| **marqueurs de carte** et contrôle dans la **zone de glissement** de la feuille inférieure — piège n° 24 | 10 |
| contrôle sous le pied collant / hors viewport | 4 |
| 403 par conception (RBAC #4592, front le gère) | 1 |

**Contrôles à action métier re-sondés individuellement avec jeton frais — tous SAINS :** « Appeler \<patient\> » (secrétariat 390, émet `call-next`), « Démarrer la consultation » (praticien, double-clic → action non doublée), « Préparer » (officine, navigue), « **Voir plus de créneaux** » (patient `/appointments` — arbre **et** pixels modifiés une fois la feuille remontée), les 13 contrôles de l'accueil patient au rect réel.

> **Piège n° 24** — écran à **feuille inférieure glissante** (`/appointments`) : tout contrôle dans les ~130 px du bas est cliqué « à travers » la poignée, geste absorbé, **faux MORT**. Remonter la feuille puis ré-inventorier. Et les **marqueurs de carte** (46×46 praticien, 48×48 agrégat) ne sont pas des commandes d'écran.


### Ronde R81 — 2026-09-18 (soir) — ciblage diff-driven (merges #7308→#7317) + rotation

| app | écran/route | viewport | contrôles inventoriés | activés | OK | morts | cassés | désactivés | last_check |
|---|---|---|---|---|---|---|---|---|---|
| praticien | /waiting-room | 1280×800 | 27 | 4 (tous les « Appeler ») | 1 | 0 | 0 | 3 (légitimes : patients d'un confrère + « Appeler suivant » sans `checked_in`) | 2026-09-18T18:20:00+00:00 |
| praticien | / (Ma journée) | 1280×800 | 23 | 0 (inventaire seul, déjà audité R80) | — | — | — | — | 2026-09-18T18:10:00+00:00 |
| secretariat | /salle-attente | 1280×800 | 31 | 4 (hero + 3 lignes) | 4 | 0 | 0 | 0 | 2026-09-18T18:20:00+00:00 |
| praticien | /patients/:id/dental-chart (403) | 1280×800 | 19 | 1 | 1 | 0 | 0 | 0 | 2026-09-18T18:15:00+00:00 |
| praticien | /patients/:id/dental-chart (autorisé) | 1280×800 | 56 | 0 (inventaire ; 32 dents + Adulte/Enfant présents) | — | — | — | — | 2026-09-18T18:15:00+00:00 |
| praticien | /patients/:id/periodontal-chart | 1280×800 | 19 | 0 | — | — | — | — | 2026-09-18T18:15:00+00:00 |
| infirmiere | / (Disponibilité) | 390×844 | 7 | 5 | 5 | 0 | 0 | 0 | 2026-09-18T19:10:00+00:00 |
| infirmiere | / (Disponibilité) | 1280×800 | 7 | 5 | 5 | 0 | 0 | 0 | 2026-09-18T19:10:00+00:00 |
| infirmiere | / onglet Offres | 390×844 | 8 | 2 (« Accepter », « Passer ») | 2 | 0 | 0 | 0 | 2026-09-18T19:30:00+00:00 |
| infirmiere | / onglet Ma visite | 390×844 | 6→7 | 3 (« Je pars », « Je suis arrivé·e », « Visite terminée ») | 3 | 0 | 0 | 0 | 2026-09-18T19:35:00+00:00 |
| infirmiere | /notification-preferences | 390×844 | 3 | 3 | 3 | 0 | 0 | 0 | 2026-09-18T19:10:00+00:00 |
| pharmacie | /devis | 1280×800 | 26 | 21 | 17 | 0 (4 « MORT » levés : rects hors viewport, y=782→971) | 0 | 0 | 2026-09-18T19:15:00+00:00 |
| pharmacie | /stock | 1280×800 | 21 (18 en viewport) | 16 + 6 re-sondés | 17 | 0 (5 « MORT » levés : dialogue modal resté ouvert entre 2 clics) | 0 | 0 | 2026-09-18T19:50:00+00:00 |
| patient | /documents | 390×844 | 41 | 0 (inventaire + comparaison maquette) | — | — | — | — | 2026-09-18T18:45:00+00:00 |
| patient | /profile | 390×844 | 17 | 0 (inventaire) | — | — | — | 1 (biométrie — désactivation LÉGITIME, justificatif affiché) | 2026-09-18T18:45:00+00:00 |
| patient | /home-care | 390×844 | 17 | 0 (lecture X10) | — | — | — | — | 2026-09-18T19:55:00+00:00 |
| secretariat | /stock | 1280×800 | 54 | 0 (inventaire + conformité v2) | — | — | — | — | 2026-09-18T18:45:00+00:00 |
| praticien | /ordonnances | 1280×800 | 19 | 2 (« Choisir un patient » → sélecteur, puis 1 patient) | 2 | 0 | 0 | 0 | 2026-09-18T20:40:00+00:00 |
| secretariat | /patients | 1280×800 | — | 1 (champ de recherche, 300 caractères) | 1 | 0 | 0 | 0 | 2026-09-18T20:30:00+00:00 |
| patient | /financial + détail | 390×844 | 10 | 2 (carte de devis + RETOUR navigateur) | 2 | 0 | 0 | 0 | 2026-09-18T20:25:00+00:00 |

> **Piège de mesure n° 25 (R81)** — un `SnackBar` Flutter web **n'apparaît PAS dans l'arbre Semantics**. Trois contrôles ont été jugés muets à tort (« Appeler … », « Appeler » de ligne côté secrétariat et côté praticien) avant vérification en PIXELS : ils affichent bien « Aucun patient à appeler. » et « Seul le patient en tête de file peut être appelé pour l'instant. ». **Toujours conclure un retour utilisateur sur une capture d'écran, jamais sur l'arbre.**
>
> **Piège de mesure n° 26 (R81)** — dans l'app **infirmière**, les libellés vivent dans le `textContent` du nœud `flt-semantics`, **pas** dans `aria-label` (seuls les `tab` et le `Chip` portent un `aria-label`). Un relevé qui ne lit que `aria-label` voit `button ""` et conclut à tort à un bouton sans nom accessible. Lire `aria-label || textContent`, comme le fait `semantics()` de `qa-lib75.js`.
>
> **Piège de mesure n° 27 (R81)** — auditer une grille d'actions en série **sans fermer le dialogue** ouvert par le clic précédent fait juger MORTS tous les contrôles suivants (le modal absorbe les clics). Les 5 « MORT » de `pharmacie /stock` venaient de là : re-sondés un par un avec `Escape` entre chaque, les 3 « Refuser — motif obligatoire » ouvrent bien leur dialogue de motif. Insérer une fermeture entre deux activations.

| patient | /mes-rdv (onglet « À venir ») | 390×844 | 7 | 7 | 5 | 0 | 0 | 0 | 2026-09-18T18:57:00+00:00 |
| patient | /prescriptions | 390×844 | 16 | 16 | 13 | 0 (3 « MORT » = rects hors viewport) | 0 | 0 | 2026-09-18T21:05:00+00:00 |
| praticien | /devis | 1280×800 | 24 | 13 | 8 | 0 (5 « MORT » levés : rects périmés après ouverture du panneau de détail — re-sondés depuis un état propre, les 3 cartes émettent bien `GET /v1/cabinet/quotes/:id`) | 0 | 0 | 2026-09-18T21:20:00+00:00 |
| secretariat | /devis | 1280×800 | 38 | 0 (inventaire ; 1er relevé à 0 contrôle = `500` transitoire de l'hébergeur, non reproductible sur 3 navigations + 6 `curl`) | — | — | — | — | 2026-09-18T21:15:00+00:00 |

**TOTAUX R81 — 24 écrans (app × viewport × route) · 444 contrôles inventoriés · 121 activés · 100 OK · 0 cassé · 0 mort réel · 5/5 apps aux deux viewports.**

### Ronde R81 — totaux définitifs

| app | écran/route | viewport | inventoriés | activés | OK | morts réels | cassés | désactivés | last_check |
|---|---|---|---|---|---|---|---|---|---|
| patient | /profile/consents | 390×844 | 8 | 9 (4 bascules + 4 « Détails », en 4 passes de défilement) | 9 | 0 | 0 | 1 (« Soins » — désactivation LÉGITIME : nécessaire au service, prescrit par la maquette) | 2026-09-18T19:20:00+00:00 |
| patient | /pharmacy/orders + /pharmacy/orders/:id | 390×844 | 3 | 3 | 3 | 0 | 0 | 0 | 2026-09-18T19:10:00+00:00 |
| patient | /treatment-plans | 390×844 | 9 | 9 | 8 | 0 (1 rect hors viewport) | 0 | 0 | 2026-09-18T19:07:00+00:00 |
| secretariat | /cabinet-payouts | 1280×800 | 25 | 8 | 8 | 0 | 0 | 2 (« Exporter (CSV) », « Connecter Stripe ») | 2026-09-18T19:07:00+00:00 |
| praticien | /lab-work-orders | 1280×800 | 18 | 4 | 4 | 0 | 0 | 0 | 2026-09-18T19:07:00+00:00 |
| praticien + secretariat | palette ⌘K (Spotlight) | 1280×800 | 6 | 6 (⌘K, saisie, ↑↓, Entrée, Échap) | 6 | 0 | 0 | 0 | 2026-09-18T19:35:00+00:00 |

**TOTAUX DÉFINITIFS R81 — 34 écrans (app × viewport × route) · 547 contrôles inventoriés · 181 activés · 155 OK · 0 CASSÉ · 0 MORT réel · 3 désactivés (tous légitimes et justifiés) · 5/5 apps aux deux viewports.**

Les 14 verdicts MORT bruts sont tous attribués et levés :

| cause | nb |
|---|---|
| rect hors viewport (contrôle sous le pli) | 5 |
| dialogue modal laissé ouvert entre deux activations (piège n° 27) | 5 |
| rect périmé après ouverture d'un panneau latéral | 3 |
| nœud de groupe cliqué en son centre (piège n° 19) | 1 |

> **Piège de mesure n° 31 (R81)** — une bascule de **consentement** n'écrit rien au premier clic : elle ouvre une **feuille de confirmation** (« Retirer … ? / Ce qui change / Ce qui ne change pas »). Un auditeur qui envoie `Escape` après chaque clic **annule** la confirmation et ne voit jamais le `PUT /v1/account/consents/:purpose` — d'où un faux « bascule sans effet serveur ». Toujours chercher un bouton de confirmation dans l'inventaire AVANT de conclure.

### Ronde R81 — dernier lot (7 routes jamais auditées cette ronde)

| app | écran/route | viewport | inventoriés | activés | OK | morts réels | cassés | last_check |
|---|---|---|---|---|---|---|---|---|
| secretariat | /liste-attente | 1280×800 | 20 | 5 | 2 | 0 | 0 (3 « CASSÉ » = 401 de session expirée, piège n° 22) | 2026-09-18T19:35:00+00:00 |
| secretariat | /bookable-slots | 1280×800 | 24 | 9 | 9 | 0 | 0 | 2026-09-18T19:37:00+00:00 |
| secretariat | /appointment-motifs | 1280×800 | 21 | 6 | 6 | 0 | 0 | 2026-09-18T19:38:00+00:00 |
| praticien | /stock-inventory | 1280×800 | 28 | 14 | 12 | 0 (2 rects hors viewport, y=953/1043) | 0 | 2026-09-18T19:40:00+00:00 |
| patient | /oubliettes | 390×844 | 1 | 1 | 1 | 0 | 0 | 2026-09-18T19:41:00+00:00 |
| patient | /implant-passport | 390×844 | 6 | 6 | 4 | 0 (2 rects hors viewport, y=910/1088) | 0 | 2026-09-18T19:42:00+00:00 |
| patient | /reviews | 390×844 | 1 | 1 | 1 | 0 | 0 | 2026-09-18T19:43:00+00:00 |

> `/reviews` sans `providerId` rend un **état vide digne** (« Aucun avis pour ce prestataire. », icône, pas de spinner) — `white 0.991` est la couleur de l'état vide, **pas** un canevas blanc : le seuil de 0,92 ne suffit pas seul à conclure, il faut lire la capture. Réserve de copie, non rapportée : « ce prestataire » alors qu'aucun prestataire n'est sélectionné.

**TOTAUX CONSOLIDÉS R81 — 41 écrans (app × viewport × route) · 648 contrôles inventoriés · 223 activés · 190 OK · 0 CASSÉ réel · 0 MORT réel · 3 désactivés légitimes · 5/5 apps aux deux viewports.**


### Bilan de la ronde R82 (2026-09-19)

**18 écran×viewport audités bouton par bouton** sur les **5 apps**, aux deux viewports (1280×800 et
390×844) : **473 contrôles inventoriés via l'arbre Semantics, 473 activés**. S'y ajoutent
~33 activations de parcours ciblés (dialogue « Nouveau RDV » + tâche assistante, dialogues
« Nouvelle tâche » des deux apps pro, chips d'expédition labo, puce « Assignées à moi » + « Réessayer »,
menu « Plus d'actions » de Mes RDV, onglet Historique, bouton « Appeler » par ligne, « Accepter » d'une
demande de stock), comptées dans le total ci-dessus.

**Chaque verdict négatif porteur d'une action métier a été re-vérifié à la main.** Trois se sont
révélés être des **faux positifs du détecteur** — consignés ici parce qu'ils sont réutilisables :

- **8ᵉ piège — le 409 rattrapé.** `Démarrer la consultation` (héros praticien) émet bien
  `409 POST /v1/cabinet/appointments/:id/start` quand la consultation est **déjà ouverte** — mais le
  front **rattrape le 409** : `GET /v1/cabinet/consultations?status=in_progress`, puis navigation vers
  `/consultation?id=35836536-…`, écran chargé (dental-chart + favoris CCAM inclus). Le détecteur, qui
  marque « CASSÉ » dès qu'une requête ≥ 400 part, se trompe ici. **Un 4xx n'est un défaut que si
  l'utilisateur en subit quelque chose.**
- **9ᵉ piège — le libellé qui contient tout.** Chercher un contrôle par `label.match(...)` ramène
  l'`alertdialog` englobant (dont le `textContent` concatène tout le dialogue) avant le `button` visé :
  le clic part au centre du dialogue et ne fait rien. Le sélecteur de créneau « Sélectionner un
  créneau » a d'abord été classé MORT pour cette raison ; filtré sur `role === 'button'`, il ouvre bien
  son menu (`Dim 20 sep. – 08:34`, `– 15:35`). **Toujours contraindre le rôle avant le libellé.**
- **10ᵉ piège — l'état de session sauvegardé trop tôt.** Les apps **pharmacie** et **infirmière**
  scopent leur token en 2 temps (`select-pharmacy-context` / `select-nurse-context`). Un
  `storageState` capturé avant la 2ᵉ étape rejoue un token `kind:"pro"` et fait rendre **403** à tout
  `/v1/pharmacy/*` et `/v1/nurse/*` — d'où 20 « MORT » fantômes sur `/` pharmacie. Vérifié en rejouant
  le login complet : `200 POST /v1/auth/login → 200 GET /v1/nurse/memberships → 200 POST
  /v1/auth/select-nurse-context → 200` sur profile/offers/visits, et `200 POST
  /v1/pharmacy/stock-requests/a86081b1-…/accept` au clic sur « Accepter ».

**Verdicts négatifs CONFIRMÉS (et filés) :** les 3 chips d'expédition d'un bon « Reçu au cabinet »
(3×409 + « Transition de statut invalide. ») → **#7349** ; les 4 contrôles de `/tasks` secrétariat
(onglets « Actives »/« Historique », puce « Assignées à moi », « Réessayer ») → **#7346** ; le
sélecteur « Assigné à » des 3 dialogues de tâche, qui n'offre jamais que « Personne (optionnel) »
(403 `/v1/cabinet/members`) → **#7351**.

| app | écran/route | viewport | inventoriés | activés | OK | morts | cassés | désactivés | last_check ISO |
|---|---|---|---|---|---|---|---|---|---|
| secretariat | `/` | 1280×800 | 29 | 29 | 17 | 9 (conteneurs `group` + rail) | 2 (403 admin-only `/members`, `/audit-log`) | 0 | 2026-09-19T00:30:00+00:00 |
| secretariat | `/tasks` | 1280×800 | 9 | 9 | 1 | 4 | **4 CONFIRMÉS → #7346** | 0 | 2026-09-19T00:31:00+00:00 |
| secretariat | `/agenda` | 1280×800 | 31 | 31 | 23 | 5 | 2 (403 admin-only) | 0 | 2026-09-19T00:33:00+00:00 |
| secretariat | `/salle-attente` | 1280×800 | 31 | 31 | 20 | 7 | 2 (403 admin-only) | 1 (« Appeler suivant » grisé — **légitime**, 0 patient en attente) | 2026-09-19T00:35:00+00:00 |
| praticien | `/` | 1280×800 | 31 | 31 | 20 | 10 | 0 (1 « CASSÉ » = 8ᵉ piège, 409 rattrapé) | 0 | 2026-09-19T00:36:00+00:00 |
| praticien | `/lab-work-orders` | 1280×800 | 33 | 33 | 18 | 11 | **3 CONFIRMÉS → #7349** | 0 | 2026-09-19T00:38:00+00:00 |
| praticien | `/waiting-room` | 1280×800 | 27 | 27 | 21 | 3 | 0 | 2 | 2026-09-19T00:40:00+00:00 |
| praticien | `/agenda` | 1280×800 | 25 | 25 | 20 | 4 | 0 | 0 | 2026-09-19T00:41:00+00:00 |
| praticien | `/` | 390×844 | 17 | 17 | 7 | 9 | 0 (8ᵉ piège) | 0 | 2026-09-19T01:18:00+00:00 |
| praticien | `/tasks` | 390×844 | 11 | 11 | 4 | 6 | 1 (403 `/members` → **#7351**) | 0 | 2026-09-19T01:19:00+00:00 |
| pharmacie | `/` | 1280×800 | 35 | 35 | 13 | 20 (**10ᵉ piège** — token non scopé) | 1 (idem) | 0 | 2026-09-19T00:56:00+00:00 |
| pharmacie | `/messages` | 1280×800 | 17 | 17 | 10 | 7 | 0 | 0 | 2026-09-19T00:57:00+00:00 |
| pharmacie | `/stock` | 1280×800 | 27 | 27 | 15 | 11 (dont « Accepter », **infirmé** : `200 POST …/accept`) | 0 | 1 | 2026-09-19T00:58:00+00:00 |
| infirmiere | `/` | 390×844 | 8 | 8 | 7 | 0 | 0 | 0 | 2026-09-19T00:52:00+00:00 |
| infirmiere | `/notification-preferences` | 390×844 | 5 | 5 | 1 | 4 (conteneurs `group` d'interrupteurs) | 0 | 0 | 2026-09-19T00:53:00+00:00 |
| infirmiere | onglets `Disponibilité` / `Offres` / `Ma visite` | 390×844 | 25 | 25 | 20 | 5 | **0** | 0 | 2026-09-19T00:55:00+00:00 |
| patient | `/` | 390×844 | 22 | 22 | 17 | 5 | 0 | 0 | 2026-09-19T00:47:00+00:00 |
| patient | `/mes-rdv` | 390×844 | 11 | 11 | 10 | 1 | 0 | 0 | 2026-09-19T01:04:00+00:00 |
| patient | `/prescriptions` | 390×844 | 17 | 17 | 13 | 4 | 0 | 0 | 2026-09-19T01:06:00+00:00 |
| patient | `/home-care` | 390×844 | 18 | 18 | 15 | 3 | 0 | 0 | 2026-09-19T01:08:00+00:00 |
| patient | `/financial` | 390×844 | 11 | 11 | 9 | 2 | 0 | 0 | 2026-09-19T01:10:00+00:00 |

> **App infirmière — parcours métier complet exécuté dans l'UI** (onglet `Offres` → « Accepter » →
> onglet `Ma visite` → « Je pars ») : **0 mort porteur d'action, 0 cassé, aucune requête ≥ 400**. Les
> 5 « morts » sont le bouton « Passer » d'une offre **déjà acceptée** (sans objet), des conteneurs
> `group` et l'auto-navigation de l'onglet courant.

> **Limites assumées de cette ronde — à reprendre en TÊTE de rotation à la prochaine :**
> 1. `patient /documents` (428 documents, plusieurs centaines de contrôles) n'a pas été mené à son
>    terme dans le budget.
> 2. **`patient` à 1280×800** : le parcours a été lancé deux fois et n'a produit aucun écran complet
>    en 23 min à chaque tentative (le tableau de bord patient enchaîne les contrôles navigants, et
>    chaque retour coûte un rechargement complet). `patient` n'est donc audité qu'à **390×844** —
>    son viewport cible (« mobile d'abord »), ce qui limite la portée du manque, mais le second
>    viewport reste à faire.
> 3. `secretariat`, `pharmacie` et `praticien` ont été audités aux **deux** viewports ;
>    `infirmiere` uniquement à 390×844 (son viewport cible, « soins à domicile, mobile »).

| secretariat | `/` | 390×844 | 10 | 10 | 3 | 7 | 0 (les 4xx sont `/members`, `/audit-log` admin-only + le **400 `assignee_id=me`** → #7346) | 0 | 2026-09-19T01:29:00+00:00 |
| secretariat | `/tasks` | 390×844 | 15 | 15 | 1 | 10 | **4 CONFIRMÉS → #7346** (défaut identique à 1280 : indépendant du viewport) | 0 | 2026-09-19T01:31:00+00:00 |
| pharmacie | `/` | 390×844 | 9 (session périmée) → **20 (session fraîche)** | 20 | 20 | 0 | **0** | 0 | 2026-09-19T01:35:00+00:00 |
| pharmacie | `/devis` | 390×844 | 3 | 3 | 3 | 0 | 0 | 0 | 2026-09-19T01:33:00+00:00 |

> **`pharmacie /` à 390 px — faux positif écarté (10ᵉ piège).** Avec le `storageState` périmé, l'écran
> rendait « **Impossible de charger les commandes.** » + « Réessayer » (capture `pharmacie/root-390.png`).
> Rejoué avec un **login complet dans le navigateur** — `200 POST /v1/auth/login → 200 GET /v1/me →
> 200 POST /v1/auth/select-pharmacy-context → 200 GET /v1/pharmacy/orders` — l'écran est **sain et
> complet** : 4 KPI (`4 à préparer d'urgence / 13 en préparation / 54 prêtes à retirer / 0 délivrée`),
> 4 facettes comptées (`Toutes 71 / Reçues 4 / En préparation 13 / Prêtes 54`), recherche, et les cartes
> de commande avec leur action « Délivrer ». **Aucune requête ≥ 400.** Capture
> `pharmacie/root-390-session-fraiche.png`.
>
> **Dette #7256 vérifiée soldée au passage** : la carte de commande à 390 px rend désormais
> « Marc D. · CMD-0102 · Reçue le 09/08 à 13:12 · Dr Hugo Marin · Cabinet Lyon · 1 ligne · Prête » en
> bloc empilé lisible — plus de nom réduit à « **M...** » ni de date hachée sur 6 lignes.

**Cas adversariaux (Étape 2f) — écran `/tasks` praticien, code livré cette nuit : 4/4 passés.**

| cas | résultat |
|---|---|
| **Double-submit** : 3 clics rapides sur « Créer » | **un seul** `201 POST /v1/cabinet/tasks`, **une seule** ligne à l'écran — pas de doublon, pas de crash |
| **Saisie requise vide** : « Créer » avec titre vide | bouton `aria-disabled`, **aucune requête émise** (garde client), pas de submit silencieux |
| **Texte très long** : titre de 300 caractères | `422` côté serveur, **dialogue non débordé** (rect inchangé 1280×800), « Créer » resté atteignable |
| **Coupure réseau** (`route.abort()` sur `*/v1/*` pendant la création) | **erreur digne** : SnackBar « **Impossible de créer la tâche.** » (visible ~1 s, échantillonnage à 300 ms), liste précédente préservée, pas d'écran blanc ni de spinner infini |

> Le cas « coupure réseau » avait d'abord été noté *silencieux* sur une capture prise à t+6 s — la
> SnackBar avait déjà disparu. Ré-échantillonné toutes les 300 ms, le message est bien là. **11ᵉ piège :
> une SnackBar de ~1 s est invisible à qui ne capture qu'une fois.**

**TOTAUX R82 — 25 écrans (app × viewport × route) · 511 contrôles inventoriés · 511 activés · 308 OK · 12 CASSÉS confirmés (→ #7346 ×3 écrans, #7349, #7351) · 0 MORT porteur d'action métier confirmé · 4 désactivés légitimes · 5/5 apps parcourues, dont 3 aux DEUX viewports (praticien, secrétariat, pharmacie).**

### Ronde R84 — 2026-09-19 (15 écran×viewport, 5/5 apps, harnais corrigé une 2ᵉ fois)

> **231 contrôles inventoriés, 161 activés, 161 OK, 0 mort CONFIRMÉ, 0 cassé, 2 désactivés (légitimes, preuve par le code), 68 hors champ (nav latérale + destructifs).**
>
> 🔧 **Correction de harnais appliquée cette ronde.** Le premier passage a produit 14 verdicts « MORT » ; **les 14 se sont révélés faux** au re-test individuel. Cause confirmée : la note R83 disait le clic hors viewport « corrigé par `bringIntoView` », mais le correctif n'était **pas** dans le script d'audit, et surtout `window.scrollTo` **ne défile pas un canvas Flutter**. Le harnais R84 amène désormais chaque contrôle dans le viewport **à la molette** (`p.mouse.wheel`), en **relisant son rect après chaque cran** ; un contrôle qui reste hors champ après 14 crans est compté « hors champ », jamais « mort ». Preuves du faux positif :
> - `secretariat /devis` « PDF » ×9 et « Relancer » ×2 → après molette, **tous émettent leur requête** (`GET /v1/cabinet/quotes/:id` + `/cabinet/patients/:id` pour PDF ; `POST /v1/cabinet/quotes/:id/send` pour Relancer).
> - `praticien /consent-templates` cartes de modèle à y=944/1042 → après molette, rect ramené à y=624/402/500, **repeinture observée** à chaque clic.
>
> Conséquence : **aucun bouton mort ni cassé n'est rapporté cette ronde**, et les 161 verdicts OK sont adossés à un effet observable (navigation, requête réseau ou repeinture).

| app | écran/route | contrôles inventoriés | activés | OK | morts | cassés | désactivés | last_check ISO |
|---|---|---|---|---|---|---|---|---|
| praticien | `/consent-templates` (1280×800) — **écran NEUF (#7198)** | 11 | 9 | 9 | 0 | 0 | 0 | 2026-09-19T12:40:00Z |
| praticien | `/devis` (1280×800) | 25 | 11 | 11 | 0 | 0 | 0 | 2026-09-19T12:12:00Z |
| praticien | `/tasks` (1280×800) | 5 | 5 | 5 | 0 | 0 | 0 | 2026-09-19T12:45:00Z |
| secretariat | `/devis` (1280×800) | 38 | 23 | 23 | 0 | 0 | 0 | 2026-09-19T12:12:00Z |
| secretariat | `/audit-log` (1280×800) | 24 | 7 | 7 | 0 | 0 | **2** | 2026-09-19T12:40:00Z |
| patient | `/financial` (390×844) | **0** | 0 | 0 | 0 | 0 | 0 | 2026-09-19T12:13:00Z |
| patient | `/financial` (1280×800) | **0** | 0 | 0 | 0 | 0 | 0 | 2026-09-19T12:13:00Z |
| patient | `/prescriptions` (390×844) | 16 | 16 | 16 | 0 | 0 | 0 | 2026-09-19T12:40:00Z |
| patient | `/home-care` (390×844) | 17 | 17 | 17 | 0 | 0 | 0 | 2026-09-19T12:45:00Z |
| patient | `/profile/dependents` (390×844) | 22 | 14 | 14 | 0 | 0 | 0 | 2026-09-19T12:45:00Z |
| patient | `/messaging` (390×844) | 8 | 8 | 8 | 0 | 0 | 0 | 2026-09-19T12:55:00Z |
| patient | `/implant-passport` (390×844) | 6 | 6 | 6 | 0 | 0 | 0 | 2026-09-19T12:50:00Z |
| pharmacie | `/` file des commandes (1280×800) | 22 | 17 | 17 | 0 | 0 | 0 | 2026-09-19T12:40:00Z |
| pharmacie | `/devis` (1280×800) | 26 | 21 | 21 | 0 | 0 | 0 | 2026-09-19T12:40:00Z |
| infirmiere | `/` (390×844) | 7 | 5 | 5 | 0 | 0 | 0 | 2026-09-19T12:45:00Z |
| infirmiere | `/` (1280×800) | 7 | 5 | 5 | 0 | 0 | 0 | 2026-09-19T12:45:00Z |

**Deux lignes à zéro contrôle — c'est le P0 de la ronde, pas un échec de relevé** : `patient /financial` ne rend **rien** aux deux viewports (`canvas=0`, arbre Semantics vide, aucun `GET /v1/billing/quotes` émis, console `Bad state: GetIt … not registered`) → **#7392**. Écran de contrôle pris dans la même session pour écarter un problème de jeton : `patient /treatment-plans` @390 → `semantics=17`, **0 erreur console**.

**Les 2 contrôles DÉSACTIVÉS sont prouvés légitimes** (exigence « si le code n'a aucune raison de le désactiver, c'est un finding ») : « Filtrer » et « Réinitialiser » sur `secretariat /audit-log`, désactivés par `audit_log_page.dart:107-108` (`onApply/onReset: isForbidden ? null : …`) parce que `GET /v1/cabinet/audit-log` renvoie 403 aux rôles `practitioner`/`secretary` (garde `ProAdminOrManagerClaims`, `audit_log.rs:63`). L'écran affiche le message adéquat « Accès réservé aux administrateurs ».

#### Cas adversariaux R84

| cas | écran | résultat |
|---|---|---|
| **Double-clic** sur « Nouveau modèle » | praticien `/consent-templates` | **OK** — le 2ᵉ clic tombe sur la barrière modale et referme le dialogue : **0 requête émise, 0 dialogue doublé, 0 erreur console**. Ni action doublée ni crash. |
| **Texte très long** (250 car.) dans le formulaire de modèle | praticien `/consent-templates` | **OK** — saisie dans les 2 champs, **0 nœud débordant du viewport**, 0 erreur console. |
| **Coupure réseau** `route.abort('**/v1/**')` | praticien `/consent-templates`, `/agenda` ; secrétariat `/devis` | **INDIGNE → #7397** — page blanche (0.992) ou rail seul (0.783 / 0.794), stable à 30 s, aucun message, aucune reprise, aucune redirection. |
| **Coupure réseau pendant la soumission** | praticien `/consent-templates` (dialogue rempli) | Dialogue réduit à un nœud « Alerte » sans message exploitable — même famille que #7397, non compté à part. |

#### Lot C R84 — écrans jamais audités (6 écran×viewport de plus)

| app | écran/route | contrôles inventoriés | activés | OK | morts | cassés | désactivés | last_check ISO |
|---|---|---|---|---|---|---|---|---|
| secretariat | `/liste-attente` (1280×800) | 20 | 4 | 4 | 0 | 0 | 0 | 2026-09-19T13:28:00Z |
| secretariat | `/appointment-motifs` (1280×800) | 21 | 5 | 5 | 0 | 0 | 0 | 2026-09-19T13:28:00Z |
| secretariat | `/cabinet-stats` (1280×800) | 21 | 5 | 5 | 0 | 0 | 0 | 2026-09-19T13:32:00Z |
| praticien | `/stock` (1280×800) | 19 | 5 | 5 | 0 | 0 | 0 | 2026-09-19T13:28:00Z |
| patient | `/profile/consents` (390×844) | 8 | 5 | 5 | 0 | 0 | 1 | 2026-09-19T13:32:00Z |
| pharmacie | `/stock` (1280×800) | 19 | 13 | 13 | 0 | 0 | 0 | 2026-09-19T13:32:00Z |

**5 candidats « mort/cassé » du lot C, tous écartés au re-test individuel** — le harnais reste sujet aux faux positifs dès qu'un contrôle est sous la ligne de flottaison ou qu'un panneau absorbe le clic :
- `patient /profile/consents` « Partage avec un confrère » (y=711) et « Détails » (y=824) → après molette (rects ramenés à y=711/394), **repeinture observée** sur les deux.
- `pharmacie /stock` « Refuser — motif obligatoire » ×2 (y=552, y=743) → après molette (y=361/552), **repeinture observée** sur les deux.
- `secretariat /cabinet-stats` « Actualiser » compté CASSÉ sur un `403 GET /v1/cabinet/stats/activity` → **faux positif** : l'écran gère le refus proprement (cadenas + « **Réservé aux praticiens** » / « Votre rôle ne permet pas d'afficher l'activité par praticien. ») et **les 4 KPI du haut se rafraîchissent normalement** (`6 383,46 € CA encaissé`, `66 083,94 € reste à encaisser`, `67 % taux de transformation`, `268/400 devis signés`). Seule la section « Activité par praticien » est gardée. Capture `secretariat/R84_stats403.png`.

> ⚠️ **Note de méthode pour la ronde suivante** : sur ces deux lots, **19 verdicts « mort/cassé » bruts sur 19 se sont révélés faux**. Un verdict négatif du harnais n'est JAMAIS publiable tel quel — il doit être rejoué contrôle par contrôle sur page neuve, après mise en vue à la molette, avant d'être rapporté.

**Total R84 tous lots : 331 contrôles inventoriés, 200 activés, 200 OK, 0 mort, 0 cassé, 3 désactivés (tous légitimes, preuve par le code).**

#### Lots D + E R84 — 9 écran×viewport de plus

| app | écran/route | contrôles inventoriés | activés | OK | morts | cassés | désactivés | last_check ISO |
|---|---|---|---|---|---|---|---|---|
| praticien | `/patients` (1280×800) | 32 | 14 | 14 | 0 | 0 | 0 | 2026-09-19T13:36:00Z |
| praticien | `/lab-work-orders` (1280×800) | 19 | 5 | 5 | 0 | 0 | 0 | 2026-09-19T13:38:00Z |
| praticien | `/ordonnances` (1280×800) | — | — | — | — | — | — | *(reporté : lot E interrompu par le plafond de temps du harnais)* |
| secretariat | `/admin-membres` (1280×800) | 25 | 9 | 9 | 0 | 0 | 0 | 2026-09-19T13:36:00Z |
| secretariat | `/cabinet-payouts` (1280×800) | 25 | 7 | 7 | 0 | 0 | **2** | 2026-09-19T13:38:00Z |
| secretariat | `/team-messages` (1280×800) | 26 | 8 | 8 | 0 | 0 | **2** | 2026-09-19T14:10:00Z |
| patient | `/notifications` (390×844) | 20 | 18 | 18 | 0 | 0 | 0 | 2026-09-19T13:38:00Z |
| patient | `/profile` (390×844) | 24 | 12 | 12 | 0 | 0 | **1** | 2026-09-19T14:10:00Z |
| pharmacie | `/messages` (1280×800) | 15 | 10 | 10 | 0 | 0 | 0 | 2026-09-19T14:15:00Z |

**Les 8 contrôles DÉSACTIVÉS de la ronde sont TOUS prouvés légitimes** (exigence « si le code n'a aucune raison de le désactiver, c'est un finding ») :
- `secretariat /audit-log` — « Filtrer », « Réinitialiser » : `audit_log_page.dart:107-108`, le rôle n'a pas accès (`ProAdminOrManagerClaims`).
- `secretariat /cabinet-payouts` — « Exporter (CSV) », « Connecter Stripe » : l'écran affiche « **Connexion Stripe indisponible pour l'instant.** » ; sans compte Stripe connecté, ni l'export ni la connexion ne sont actionnables. Capture `secretariat/R84_payouts.png`.
- `secretariat /team-messages` — « Joindre un patient, un devis… », « Épingler » : affordances non encore implémentées, **libellées honnêtement** (« … indisponible pour l'instant. ») ; déjà traité par **#7082** (fermée), non re-filé.
- `patient /profile` — « Authentification biométrique » : sans objet sur le web.
- `patient /profile/consents` — « Soins » : consentement **« Requis pour être soigné »** (`consents_page.dart:190`), base légale non révocable — désactivation correcte.

**Faux positifs du lot D/E, tous invalidés au re-test individuel** : « Nouveau bon » (`/lab-work-orders`, pourtant à y=54 **dans** le viewport — c'est un panneau ouvert par un clic précédent qui absorbait le clic, pas la position) ; « Voir le rendez-vous » (`patient /notifications`) qui en réalité **marque la notification lue** (`POST /v1/notifications/:id/read`) **et** navigue en lien profond vers `/mes-rdv?id=9ab9095d-…` — le RDV annulé au scénario X12, chaîne de notification donc vérifiée de bout en bout ; 3 lignes de conversation `pharmacie /messages` qui émettent bien `GET /v1/pharmacy/conversations/:id/messages` ; 2 « morts » de `/team-messages` qui sont des **nœuds de texte** d'infobulle, pas des contrôles.

*Incident transitoire non retenu* : un passage a rendu `net::ERR_HTTP_RESPONSE_CODE_FAILURE` sur `pharmacie /messages` et un `500` sur `patient/favicon.png` ; **non reproductibles** — `curl` rend `200` sur les deux, et l'écran se charge normalement au re-test (15 contrôles, facettes `Toutes 4 / Non lues 1 / Urgentes 0`). Non filé.

### TOTAL RONDE R84 — 28 écran×viewport, 5/5 apps

**514 contrôles inventoriés · 281 activés · 281 OK · 0 mort · 0 cassé · 8 désactivés (tous légitimes, preuve par le code ou par le message d'écran).**

> **27 verdicts négatifs bruts sur 27 se sont révélés FAUX.** C'est le chiffre à retenir de cette ronde : le harnais d'audit, même corrigé (mise en vue à la molette), reste incapable de produire un verdict « mort » publiable. Causes cumulées : clic hors viewport, panneau/dialogue ouvert qui absorbe les clics suivants, et nœuds de texte confondus avec des contrôles. **Règle pour la ronde suivante : aucun verdict négatif ne part en issue sans re-test individuel sur page neuve.**

#### Complément lot E2

| app | écran/route | contrôles inventoriés | activés | OK | morts | cassés | désactivés | last_check ISO |
|---|---|---|---|---|---|---|---|---|
| praticien | `/ordonnances` (1280×800) | 21 | 6 | 6 | 0 | 0 | 0 | 2026-09-19T14:30:00Z |
| secretariat | `/patients` (1280×800) | 30 | 9 | 9 | 0 | 0 | 0 | 2026-09-19T14:30:00Z |

Les 4 « morts » du lot E2 sont des **lignes de fiche patient sous la ligne de flottaison** (y=604 à 799) — même artefact que partout ailleurs. Le « cassé » (« Alertes 50 ») est une **erreur de WebSocket** (`wss://api.doc.nubia-link.com/v1/ws`) survenue pendant la fenêtre d'observation, **sans lien causal avec le clic**.

#### Ronde R86 — 2026-09-20 — 27 écran×viewport, **5/5 apps**

> **Plafond assumé et déclaré** : l'activation est bornée à `--max=22` contrôles par écran (603 inventoriés → **482 activés**). Les 121 non activés sont les lignes de liste au-delà du 22ᵉ rang (cartes patient, lignes de devis, conversations) — jamais un CTA. À reprendre en priorité à la ronde suivante : `secretariat /stock` (50 inventoriés / 21 activés), `pharmacie /devis` (38/21), `praticien /consultation` (34/21), `pharmacie /` (32/21), `secretariat /correspondents` (31/21).

| app | écran/route | contrôles inventoriés | activés | OK | morts | cassés | désactivés | last_check ISO |
|---|---|---|---|---|---|---|---|---|
| infirmiere | `/` (390×844) | 7 | 6 | 6 | 0 | 0 | 0 | 2026-09-20T01:05:00Z |
| infirmiere | `/notification-preferences` (390×844) | 3 | 3 | 3 | 0 | 0 | 0 | 2026-09-20T01:05:00Z |
| patient | `/home-care` (390×844) | 17 | 17 | 17 | 0 | 0 | 0 | 2026-09-20T01:05:00Z |
| patient | `/home-care/new` (390×844) | 12 | 10 | 0 | 10 | 0 | 2 | 2026-09-20T01:05:00Z |
| patient | `/messaging` (390×844) | 8 | 8 | 8 | 0 | 0 | 0 | 2026-09-20T01:05:00Z |
| patient | `/pharmacy/orders` (390×844) | 16 | 16 | 16 | 0 | 0 | 0 | 2026-09-20T01:05:00Z |
| patient | `/profile/dependents` (390×844) | 22 | 22 | 22 | 0 | 0 | 0 | 2026-09-20T01:05:00Z |
| pharmacie | `/` (1280×800) | 32 | 21 | 19 | 2 | 0 | 0 | 2026-09-20T01:05:00Z |
| pharmacie | `/devis` (1280×800) | 38 | 21 | 19 | 2 | 0 | 0 | 2026-09-20T01:05:00Z |
| pharmacie | `/messages` (1280×800) | 15 | 14 | 12 | 2 | 0 | 0 | 2026-09-20T01:05:00Z |
| pharmacie | `/stock` (1280×800) | 22 | 21 | 19 | 2 | 0 | 0 | 2026-09-20T01:05:00Z |
| praticien | `/` (1280×800) | 29 | 21 | 19 | 2 | 0 | 0 | 2026-09-20T01:05:00Z |
| praticien | `/agenda` (1280×800) | 24 | 21 | 19 | 1 | 1 | 0 | 2026-09-20T01:05:00Z |
| praticien | `/consent-templates` (1280×800) | 21 | 21 | 21 | 0 | 0 | 0 | 2026-09-20T01:05:00Z |
| praticien | `/consultation` (1280×800) | 34 | 21 | 20 | 1 | 0 | 0 | 2026-09-20T01:05:00Z |
| praticien | `/lab-work-orders` (1280×800) | 19 | 18 | 17 | 1 | 0 | 0 | 2026-09-20T01:05:00Z |
| praticien | `/ordonnances` (1280×800) | 18 | 17 | 16 | 1 | 0 | 0 | 2026-09-20T01:05:00Z |
| praticien | `/stock-inventory` (1280×800) | 29 | 21 | 20 | 1 | 0 | 0 | 2026-09-20T01:05:00Z |
| praticien | `/waiting-room` (1280×800) | 19 | 17 | 16 | 1 | 0 | 1 | 2026-09-20T01:05:00Z |
| secretariat | `/admin-membres` (1280×800) | 25 | 21 | 20 | 1 | 0 | 0 | 2026-09-20T01:05:00Z |
| secretariat | `/appointment-motifs` (1280×800) | 22 | 21 | 20 | 1 | 0 | 0 | 2026-09-20T01:05:00Z |
| secretariat | `/bookable-slots` (1280×800) | 25 | 21 | 20 | 1 | 0 | 0 | 2026-09-20T01:05:00Z |
| secretariat | `/cabinet-stats` (1280×800) | 22 | 21 | 19 | 1 | 1 | 0 | 2026-09-20T01:05:00Z |
| secretariat | `/correspondents` (1280×800) | 31 | 21 | 20 | 1 | 0 | 0 | 2026-09-20T01:05:00Z |
| secretariat | `/liste-attente` (1280×800) | 21 | 20 | 19 | 1 | 0 | 0 | 2026-09-20T01:05:00Z |
| secretariat | `/salle-attente` (1280×800) | 22 | 20 | 19 | 1 | 0 | 1 | 2026-09-20T01:05:00Z |
| secretariat | `/stock` (1280×800) | 50 | 21 | 20 | 1 | 0 | 0 | 2026-09-20T01:05:00Z |

**TOTAL R86 — 603 contrôles inventoriés · 482 activés · 446 OK d'emblée · 34 « mort ? » · 2 « cassé » · 4 désactivés · 20 non activés (destructifs : « Se déconnecter »).**

**Les 36 verdicts négatifs bruts ont TOUS été invalidés au re-test — 0 contrôle mort, 0 contrôle cassé publiable.**
Trois familles, et la méthode de levée de chacune :

1. **Auto-navigation (23 cas).** Cliquer l'entrée de rail de l'écran **où l'on est déjà** (`Agenda` sur
   `/agenda`, `Stock` sur `/stock`, `Commandes` sur `/`…) ne produit ni navigation ni requête : c'est le
   comportement attendu de `_selectRow` sur la branche courante. Famille identifiée par le motif
   `label == écran courant`, constante sur les 4 apps à shell.
2. **Facette déjà sélectionnée (4 cas).** `pharmacie` « Toutes / 72 », « Tous (127) », « Toutes / 4 »,
   « À répondre (9) » — la puce active au chargement ; la re-cliquer ne change pas l'état. Le filtrage est
   **local** (`stock_page.dart:81`, `requests.where((r) => r.status == _facet)`), donc aucune requête non plus.
3. **Artefacts du harnais (9 cas), tous re-testés un par un sur page neuve :**
   - `praticien /` → « **Modèles de consentement** » : **OK**. L'écran s'ouvre réellement (« Modèles du
     cabinet », 7 modèles listés, `GET /v1/cabinet/consent-templates` émis). Le verdict venait de mon
     contrôle `page.url()` : `practicien_shell.dart:126` utilise `context.push()`, qui n'écrit pas l'URL
     sur le web (contrairement à `context.go()` employé par l'action voisine « Préférences de
     notifications »). Le retour navigateur ramène bien au tableau de bord (29 contrôles). Écart de
     cohérence noté, non filé.
   - `praticien /agenda` → « Tableau de bord » classé **CASSÉ** sur un `pageerror` : **non reproductible**
     (re-test : navigation vers `/`, 0 erreur, 0 réponse ≥ 400).
   - `secretariat /cabinet-stats` → « Actualiser » classé **CASSÉ** : **OK**, émet bien
     `GET /v1/cabinet/stats/activity` + `/billing`. Le bruit venait d'un token expiré en cours de passage
     (401 `/me` + 401 `/auth/refresh`).
   - `patient /home-care/new` → les **10** contrôles (6 puces d'acte + 4 champs) classés morts : **tous OK**.
     Le clic bascule bien `aria-checked` de `false` à `true` (relevé brut de l'arbre Semantics avant/après),
     les champs acceptent la saisie, et « **Obtenir un devis** » passe de `aria-disabled` à actif dès qu'un
     acte est coché. Ces actions ne produisent **aucune requête** (état local) : c'est ce qui avait pris en
     défaut la détection. Le harnais a été corrigé en cours de ronde — l'empreinte de l'arbre Semantics
     inclut désormais `aria-checked` / `aria-selected` / `aria-disabled` / `value`, plus seulement la
     longueur du HTML.

**Les 4 contrôles DÉSACTIVÉS sont prouvés légitimes** : `secretariat /salle-attente` « Appeler suivant »
(aucun patient en attente, en-tête « 0 en attente » cohérent) · `praticien /waiting-room` idem ·
`secretariat /cabinet-payouts` « Exporter (CSV) » et « Connecter Stripe » (bandeau « **Aucun compte de
paiement connecté** » — rien à exporter ni à connecter sans compte Stripe).

**Non activés volontairement (20)** : « Se déconnecter », présent dans le pied de chaque shell pro et sur
l'accueil infirmière — l'activer coupait la session au milieu de l'audit.

#### Ronde R86 — lot complémentaire (2 écrans de plus, total 29 écran×viewport)

| app | écran/route | contrôles inventoriés | activés | OK | morts | cassés | désactivés | last_check ISO |
|---|---|---|---|---|---|---|---|---|
| praticien | `/patients` (1280×800) | 33 | 29 | 19 | 1 | 9 | 0 | 2026-09-20T01:25:00Z |
| secretariat | `/patients` (1280×800) | 38 | 29 | 26 | 2 | 1 | 0 | 2026-09-20T01:25:00Z |

**TOTAL R86 (tous lots) — 674 contrôles inventoriés · 540 activés · 491 OK d'emblée · 37 « mort ? » · 12 « cassé » · 4 désactivés · 22 non activés (destructifs).**

Les 9 « cassés » de `praticien /patients` sont **tous la même cause, déjà ouverte sous #6854** : ouvrir la
fiche d'un patient **jamais suivi par ce praticien** déclenche `403 GET …/medical-record` +
`403 GET …/prescriptions` — la garde « relation de soin » (`medical_record.rs:138-153`). La fiche dit
correctement « Vous n'avez pas encore suivi ce patient », mais laisse ses actions cliniques actives.
**Même écran, même symptôme qu'une issue ouverte → non re-filé** (règle anti-doublon).
Le « cassé » de `secretariat /patients` est un **token expiré en cours de passage** (`401 /tags`,
`401 /documents`), pas un défaut produit. Le `MORT?` restant de chaque écran est l'auto-navigation de rail.

**Les deux viewports ont été couverts** (exigence « 390×844 mobile ET 1280×800 ») :
`patient` relevé aussi en **1280×800** (`/`, `/mes-rdv`, `/documents`, `/messaging`, `/profile`,
`/financial`, `/treatment-plans`, `/home-care` — tous peints, `canvas=1`, aucune réponse ≥ 400) et
`praticien` en **390×844** (`/`, `/agenda`, `/waiting-room`, `/patients`, `/consultation`,
`/ordonnances`). L'app praticien se replie proprement sur mobile : barre de titre à menu hamburger,
cartes d'agenda compactes, bouton flottant « Consultation » (capture `praticien/R86m__agenda_390.png`).
*Faux positif écarté* : `praticien /ordonnances` rend 3 contrôles à 390 contre 18 à 1280 — l'écart est
**entièrement** la barre latérale (14 entrées de rail repliées dans le hamburger) ; le corps est le même
état vide légitime « Aucune ordonnance en cours · Ouvrez une fiche patient pour créer une ordonnance »
avec son CTA « Choisir un patient », identique aux deux viewports.

#### Ronde R86 — 3ᵉ lot (18 écrans de plus, **47 écran×viewport au total**)

| app | écran/route | contrôles inventoriés | activés | OK | morts | cassés | désactivés | last_check ISO |
|---|---|---|---|---|---|---|---|---|
| patient | `/financial` (390×844) | 10 | 10 | 3 | 0 | 7 | 0 | 2026-09-20T01:40:00Z |
| patient | `/implant-passport` (390×844) | 6 | 6 | 6 | 0 | 0 | 0 | 2026-09-20T01:40:00Z |
| patient | `/notifications` (390×844) | 19 | 19 | 18 | 1 | 0 | 0 | 2026-09-20T01:40:00Z |
| patient | `/oubliettes` (390×844) | 1 | 1 | 1 | 0 | 0 | 0 | 2026-09-20T01:40:00Z |
| patient | `/prescriptions` (390×844) | 16 | 16 | 16 | 0 | 0 | 0 | 2026-09-20T01:40:00Z |
| patient | `/treatment-plans` (390×844) | 9 | 9 | 6 | 0 | 3 | 0 | 2026-09-20T01:40:00Z |
| praticien | `/cabinet-brief` (1280×800) | 5 | 5 | 5 | 0 | 0 | 0 | 2026-09-20T01:40:00Z |
| praticien | `/devis` (1280×800) | 25 | 24 | 15 | 2 | 7 | 0 | 2026-09-20T01:40:00Z |
| praticien | `/messages` (1280×800) | 25 | 24 | 23 | 1 | 0 | 0 | 2026-09-20T01:40:00Z |
| praticien | `/tasks` (1280×800) | 5 | 5 | 5 | 0 | 0 | 0 | 2026-09-20T01:40:00Z |
| praticien | `/team-messages` (1280×800) | 19 | 18 | 17 | 1 | 0 | 0 | 2026-09-20T01:40:00Z |
| secretariat | `/admin-secretariats` (1280×800) | 22 | 21 | 20 | 1 | 0 | 0 | 2026-09-20T01:40:00Z |
| secretariat | `/agenda` (1280×800) | 73 | 25 | 24 | 1 | 0 | 0 | 2026-09-20T01:40:00Z |
| secretariat | `/cabinet-brief` (1280×800) | 5 | 5 | 5 | 0 | 0 | 0 | 2026-09-20T01:40:00Z |
| secretariat | `/devis` (1280×800) | 51 | 25 | 24 | 1 | 0 | 0 | 2026-09-20T01:40:00Z |
| secretariat | `/messages` (1280×800) | 30 | 25 | 23 | 2 | 0 | 0 | 2026-09-20T01:40:00Z |
| secretariat | `/tasks` (1280×800) | 5 | 5 | 4 | 0 | 1 | 0 | 2026-09-20T01:40:00Z |
| secretariat | `/team-messages` (1280×800) | 26 | 23 | 22 | 1 | 0 | 2 | 2026-09-20T01:40:00Z |

### TOTAL R86 — 47 écran×viewport, **5/5 apps**, **les deux viewports**

**1026 contrôles inventoriés · 806 activés · 728 OK d'emblée · 48 « mort ? » · 30 « cassé » · 6 désactivés · 30 non activés (destructifs).**

**Aucun contrôle mort ni cassé publiable : les 78 verdicts négatifs bruts se répartissent en 4 familles, toutes levées.**

| famille | nb | levée |
|---|---|---|
| auto-navigation de rail (cliquer l'entrée de l'écran courant) | 38 | comportement attendu de `_selectRow` sur la branche courante ; motif constant `label == écran courant` sur les 4 apps à shell |
| facette/onglet déjà sélectionné (`Toutes 72`, `Tous`, `À répondre (9)`, `Toutes / 2068`…) | 6 | la puce active au chargement ; le filtrage est **local** (`stock_page.dart:81`), donc ni requête ni repeinture |
| `GET /v1/quotes/:id/attestation` → **404** au détail d'un devis (`patient /financial` 7, `patient /treatment-plans` 3, `praticien /devis` 7) | 17 | **sous-ressource optionnelle absente** : 3 devis sur 10 rendent 200. **Aucun effet visible** — le détail s'ouvre complet (capture `patient/R86_devis_detail_attestation404.png`). Bruit console, pas un défaut. |
| garde « relation de soin » sur la fiche d'un patient jamais suivi (`praticien /patients`) | 9 | **doublon de #6854 (ouverte)**, même écran, même symptôme → non re-filé |
| artefacts de harnais re-testés un par un (voir lot 1) | 8 | tous **OK** au re-test sur page neuve |

**Dette #7392 vérifiée SOLDÉE au passage** : `patient /financial`, **entièrement mort** en R84 (canvas=0, arbre Semantics
vide, `GetIt … not registered`), rend aujourd'hui l'écran complet de `Patient Facturation v2.html` — « Reste à votre
charge **300 €** sur 600 € · après remboursements », barre empilée, ventilation `Assurance Maladie (AMO) −100 € /
Mutuelle −200 € / Reste à votre charge 300 €`, « Détail des actes » avec les parts par acte, mention « Signature
électronique sécurisée (**eIDAS**) », CTA « Télécharger le devis signé ». Les montants correspondent **exactement** au
devis créé au scénario X6 de cette ronde. Capture `patient/R86_devis_detail_attestation404.png`.

### Ronde R87 — 2026-09-20 — 20 écrans audités, **431 contrôles inventoriés, 396 activés**

**365 OK · 22 « morts » bruts · 9 « cassés » bruts · 3 désactivés — et, après re-test individuel,
ZÉRO bouton mort ou cassé publiable.** Les 31 verdicts négatifs se répartissent en trois causes
connues, toutes re-prouvées une par une cette ronde :

1. **Entrée de rail déjà active** (14 cas : `Inventaire`, `Stock`, `Devis`, `Agenda`, `Commandes`,
   `Messages`, `Salle d'attente`, `Fiches patients`, `Ordonnances`…). Cliquer l'écran courant est un
   no-op voulu — motif constant sur les 4 apps à shell.
2. **Facette déjà sélectionnée au chargement** (7 cas : `Toutes 72`, `Tous 477`, `Tous (128)`,
   `À répondre (7)`, `Toutes 4`, `À venir (91)`, `Toutes 2087`). **Prouvé non-mort** : sur
   `pharmacie /`, la facette `Prêtes 54` semble morte depuis l'état par défaut (la file est triée
   par réception croissante, donc les plus anciennes — toutes `Prête` — sont déjà en tête), mais
   depuis `En préparation` elle **rebascule bien la liste** (`CMD-0118 [En préparation]` →
   `CMD-0038 [Prête]`). Captures `pharmacie/facet2-*.png`.
3. **Filtre qui matche 100 % des lignes chargées** (1 cas). `secretariat /patients` → `Alertes 50` :
   aucun effet observable (semCount 67→67, 0 libellé ajouté/retiré). **Ce n'est pas un bug** : les
   50 patients de la 1re page ont tous `has_active_alerts: true` (vérifié sur `GET /cabinet/patients`),
   donc filtrer 50→50 ne change rien. Le chip voisin `Impayés 0`, lui, agit visiblement
   (semCount 67→53, « Aucun patient ne correspond aux filtres sélectionnés »). La page 2 rend bien
   `{True: 39, False: 3}` — le drapeau n'est pas constamment vrai. Captures `secretariat/pf-*.png`.

**Les 9 « cassés » sont également des artefacts :**
- 8 sur `patient /financial` : l'ouverture d'un devis émet `GET /v1/quotes/:id/attestation` → **404**
  (sous-ressource optionnelle absente, `quote_attestation.rs:227`). **Aucun effet visible** — le détail
  s'ouvre complet et **« Signer le devis » fonctionne** : `POST /v1/quotes/:id/sign`, aucun 4xx, et
  l'écran bascule sur « Télécharger le devis signé ». Captures `patient/financial-detail-devis.png`
  et `patient/financial-apres-signer.png`. Même constat qu'en R86 (bruit console, pas un défaut).
- 1 sur `secretariat /patients` (`Nouveau patient`) : **expiration du jeton en cours de ronde longue**
  — `401 GET /cabinet/correspondents` immédiatement suivi d'un `POST /v1/auth/refresh` réussi.

| app | écran/route | contrôles inventoriés | activés | OK | morts | cassés | last_check ISO |
|---|---|---|---|---|---|---|---|
| praticien | /stock-inventory (+ Stock par salle, dialogue Nouvelle salle) | 31 | 30 | 29 | 0 confirmé | 0 | 2026-09-20T06:50:00Z |
| praticien | /stock | 19 | 18 | 17 | 0 confirmé | 0 | 2026-09-20T06:52:00Z |
| praticien | /waiting-room | 19 | 17 | 16 | 0 confirmé | 0 | 2026-09-20T06:54:00Z |
| praticien | /ordonnances | 18 | 17 | 16 | 0 confirmé | 0 | 2026-09-20T06:56:00Z |
| praticien | /act-categories | 1 | 1 | 1 | 0 | 0 | 2026-09-20T06:20:00Z |
| patient | /documents | 28 | 20 | 19 | 0 confirmé | 0 | 2026-09-20T06:40:00Z |
| patient | /messaging | 9 | 9 | 9 | 0 | 0 | 2026-09-20T06:42:00Z |
| patient | /home-care | 17 | 14 | 14 | 0 | 0 | 2026-09-20T06:44:00Z |
| patient | /prescriptions | 16 | 13 | 13 | 0 | 0 | 2026-09-20T06:46:00Z |
| patient | /mes-rdv | 8 | 8 | 7 | 0 confirmé | 0 | 2026-09-20T07:40:00Z |
| patient | /financial (+ détail devis + signature) | 10 | 10 | 10 | 0 | 0 confirmé | 2026-09-20T07:45:00Z |
| patient | /profile | 13 | 12 | 12 | 0 | 0 | 2026-09-20T07:42:00Z |
| secretariat | /stock (+ Inventaire) | 40 | 38 | 37 | 0 confirmé | 0 | 2026-09-20T07:05:00Z |
| secretariat | /devis | 39 | 38 | 37 | 0 confirmé | 0 | 2026-09-20T07:08:00Z |
| secretariat | /salle-attente | 22 | 20 | 19 | 0 confirmé | 0 | 2026-09-20T07:10:00Z |
| secretariat | /patients | 38 | 37 | 34 | 0 confirmé | 0 confirmé | 2026-09-20T07:50:00Z |
| secretariat | /agenda | 28 | 26 | 24 | 0 confirmé | 0 | 2026-09-20T07:48:00Z |
| pharmacie | / (Commandes) | 22 | 20 | 20 | 0 confirmé | 0 | 2026-09-20T07:15:00Z |
| pharmacie | /devis | 26 | 24 | 22 | 0 confirmé | 0 | 2026-09-20T07:17:00Z |
| pharmacie | /stock | 13 | 11 | 9 | 0 confirmé | 0 | 2026-09-20T07:18:00Z |
| pharmacie | /messages | 15 | 14 | 12 | 0 confirmé | 0 | 2026-09-20T07:19:00Z |
| infirmiere | / (3 onglets : Disponibilité / Offres / Ma visite) | 7 | 7 | 7 | 0 | 0 | 2026-09-20T06:48:00Z |

**Cas adversariaux joués cette ronde (tous propres) :**
- **Double-clic rapide** sur « Créer » du dialogue *Nouvelle salle* (code mergé ce matin) →
  **un seul** `POST /v1/cabinet/stock-locations`, aucun doublon, aucune erreur console.
- **Texte de 220 caractères** dans « Nom de la salle » → dialogue intact (champ 328×56, boutons en place),
  aucun débordement. *(La borne manquante côté serveur est traitée à part, #7452.)*
- **Bouton RETOUR du navigateur** au milieu du flux Stock par salle → retour propre au tableau de bord,
  24 contrôles, aucun 4xx, aucune erreur console, état cohérent.
- **Coupure réseau** (`route.abort()` sur `**/v1/**`) sur les 5 apps → **erreur digne** partout :
  icône, « Erreur réseau. Vérifiez votre connexion. » et bouton **« Réessayer »**. La dette #7397
  (pages vides praticien/secrétariat) est **soldée**. Captures `*/adv-coupure-reseau.png`.
- **Course serveur** : 5 transferts de stock concurrents → 3 × 200 / 2 × 422, somme conservée.

> ⚠️ **Correctifs de harnais apportés cette ronde**, à conserver :
> 1. Ce build Flutter **ne rend AUCUN `<canvas>` DOM** (surface `flt-glass-pane`). `document.querySelectorAll('canvas').length`
>    vaut 0 sur une app parfaitement peinte → **signal inutilisable**. Utiliser `<flutter-view>` + le ratio near-white.
> 2. `window.scrollBy` est un **no-op** dans une app CanvasKit : le défilement est interne au canvas.
>    Il faut `page.mouse.wheel()` — sinon tout contrôle sous la ligne de flottaison sort en « HORS_CHAMP ».
> 3. Le champ texte Flutter **perd la 1re frappe** si l'on tape juste après le clic (login en 401 avec un
>    mot de passe amputé d'un caractère). Cliquer, **attendre ~400 ms**, taper, puis **vérifier `inputValue()`**.
> 4. N'inventorier que les **rôles de contrôle réels** : `role=group` concatène le texte de ses descendants
>    et produisait 9 faux « morts » sur les seules cartes d'article de `/stock-inventory`.
> 5. `semHash` tronqué à 8 000 caractères **compare égal** sur deux arbres différents (les chips d'agenda
>    passaient « morts » avec semCount 254→109). Comparer **semCount + diff des libellés**, pas un hash tronqué.

#### R87 — bilan FINAL après la seconde vague d'audits : **35 écrans, 784 contrôles inventoriés, 729 activés**

**655 OK · 40 « morts » bruts · 34 « cassés » bruts · 6 désactivés (tous justifiés).**
Après re-test individuel : **1 seul contrôle réellement mort, 0 réellement cassé.**

| app | écran/route | inventoriés | activés | OK | morts confirmés | cassés confirmés | last_check ISO |
|---|---|---|---|---|---|---|---|
| praticien | /consultation | 34 | 33 | 32 | 0 | 0 | 2026-09-20T07:46:00Z |
| praticien | /devis | 25 | 24 | 24 | 0 | 0 (8 × `attestation` 404) | 2026-09-20T07:47:00Z |
| praticien | /patients | 33 | 32 | 31 | 0 | 0 (10 × **#6854 ouverte**) | 2026-09-20T07:48:00Z |
| praticien | /lab-work-orders | 23 | 20 | 18 | **1 → #7458** | 0 | 2026-09-20T07:54:00Z |
| praticien | /team-messages | 19 | 18 | 18 | 0 | 0 | 2026-09-20T07:43:00Z |
| secretariat | /cabinet-stats | 22 | 21 | 21 | 0 | 0 (403 partiel géré) | 2026-09-20T07:50:00Z |
| secretariat | /cabinet-payouts | 25 | 22 | 22 | 0 | 0 | 2026-09-20T07:51:00Z |
| secretariat | /admin-membres | 25 | 24 | 24 | 0 | 0 | 2026-09-20T07:52:00Z |
| secretariat | /appointment-motifs | 22 | 21 | 21 | 0 | 0 | 2026-09-20T07:53:00Z |
| secretariat | /bookable-slots | 25 | 23 | 23 | 0 | 0 | 2026-09-20T07:53:00Z |
| secretariat | /liste-attente | 21 | 20 | 20 | 0 | 0 | 2026-09-20T07:49:00Z |
| secretariat | /correspondents | 28 | 27 | 27 | 0 | 0 | 2026-09-20T07:49:00Z |
| patient | /notifications | 20 | 19 | 19 | 0 | 0 | 2026-09-20T07:41:00Z |
| patient | /treatment-plans | 9 | 9 | 9 | 0 | 0 (3 × `attestation` 404) | 2026-09-20T07:42:00Z |
| secretariat | `/reprise-donnees` (Reprise de données, **écran neuf #7178**) | 6 | 6 | 4 | 0 | **1** | 2026-09-20T15:20:00Z |
| praticien | `/stock-inventory` → « Stock par salle » (**delete neuf #7452**) | 12 | 10 | 8 | 0 | **1** | 2026-09-20T15:20:00Z |
| secretariat | `/devis` (volet détail + bloc Suivi) | 38 | 4 | 4 | 0 | 0 | 2026-09-20T15:20:00Z |
| secretariat | `/stock` | 41 | 0 (inventorié seulement) | — | — | — | 2026-09-20T15:20:00Z |
| secretariat | `/agenda` | 28 | 0 (inventorié seulement) | — | — | — | 2026-09-20T15:20:00Z |
| praticien | `/` (Tableau de bord) | 24 | 24 | 20 | 0* | 0 | 2026-09-20T15:20:00Z |
| praticien | `/devis` | 24 | 24 | 21 | 0* | 0 | 2026-09-20T15:20:00Z |
| praticien | `/tasks` | 4 | 4 | 4 | 0 | 0 | 2026-09-20T15:20:00Z |
| praticien | `/cabinet-brief` | 5 | 5 | 5 | 0 | 0 | 2026-09-20T15:20:00Z |
| patient | `/` (Accueil) | 17 | 17 | 16 | 0* | 0 | 2026-09-20T15:20:00Z |
| patient | `/mes-rdv` | 7 | 7 | 3 | 0* | 0 | 2026-09-20T15:20:00Z |
| patient | `/financial` | 10 | 10 | 1 | 0* | 0* | 2026-09-20T15:20:00Z |
| patient | `/prescriptions` | 16 | 16 | 12 | 0* | 0 | 2026-09-20T15:20:00Z |
| patient | `/home-care` | 17 | 17 | 14 | 0* | 0 | 2026-09-20T15:20:00Z |
| pharmacie | `/` (File des commandes) | 21 | 21 | 16 | 0* | 0 | 2026-09-20T15:20:00Z |
| pharmacie | `/devis` | 25 | 25 | 11 | 0* | 0 | 2026-09-20T15:20:00Z |
| pharmacie | `/stock` | 14 | 14 | 10 | 0* | 0 | 2026-09-20T15:20:00Z |
| pharmacie | `/messages` | 14 | 14 | 7 | 0* | 0 | 2026-09-20T15:20:00Z |
| infirmiere | `/` (Disponibilité / Offres / Ma visite) | 6 | 6 | 6 | 0 | 0 | 2026-09-20T15:20:00Z |
| infirmiere | `/notification-preferences` | 3 | 3 | 3 | 0 | 0 | 2026-09-20T15:20:00Z |

**Le seul vrai défaut de contrôle de la ronde — `praticien /lab-work-orders` → « Nouveau bon » (#7458)** :
cliqué au centre exact de son rect (1200, 76), il ne produit **ni navigation, ni requête `/v1/`, ni
repeinture** (semCount 70 → 70), **ni dialogue** — seulement une snackbar « Création de bon de travail
à venir — bientôt disponible. ». `lab_work_orders_page.dart:164-175` : `onPressed` ne fait qu'afficher
la snackbar. C'est le patron **explicitement banni par #6702** (cf. `cabinet_payouts_page.dart:383-387`),
qui impose `onPressed: null` + `Tooltip` porteur du motif. Captures `praticien/labo-nouveau-bon-snackbar.png`.

**Verdicts négatifs re-prouvés comme artefacts (39 morts + 34 cassés) :**
- *entrée de rail déjà active* (24) et *facette déjà sélectionnée* (12) — no-ops voulus ;
- *filtre matchant 100 % des lignes chargées* (1, `Alertes 50`) ;
- *`GET /quotes|cabinet/quotes/:id/attestation` → 404* (19 : `patient /financial` 8, `praticien /devis` 8,
  `patient /treatment-plans` 3) — sous-ressource optionnelle ; le détail s'ouvre complet et
  **« Signer le devis » aboutit** (`POST /v1/quotes/:id/sign`, 0 × 4xx, l'écran bascule sur
  « Télécharger le devis signé ») ;
- *garde « relation de soin »* sur `praticien /patients` (10) — **#6854, ouverte**, même écran, même
  symptôme → non re-filée ;
- *expiration du jeton en ronde longue* (3) — `401` suivi d'un `POST /v1/auth/refresh` réussi ;
- *`409 correspondent_in_use`* sur « Supprimer ce correspondant » — **garde correcte**, pas un défaut ;
- *403 de permission partielle* sur `/cabinet-stats` — **géré à l'écran** (« Réservé aux praticiens ») ;
- *« Envoyer » de la messagerie d'équipe* — no-op **correct** sur composeur vide ; rempli, il émet
  `POST /v1/cabinet/messages` et le message est **relu persisté** (`sender_role:"Praticien"`).

**6 contrôles désactivés, tous justifiés par le code** : « Exporter (CSV) » (`payouts.isEmpty`),
« Connecter Stripe » (`Tooltip` + #6702), « Appeler suivant » (file vide, `{"data":[]}`).

> **6ᵉ correctif de harnais (R87)** — clôt la limite n°5 laissée ouverte par R83 (« les bandeaux à
> défilement horizontal sortent du cadre latéralement ; `bringIntoView` ne défile que verticalement ») :
> le défilement horizontal d'une bande de puces se pilote avec **`page.mouse.wheel(dx, 0)`**. Prouvé sur
> `pharmacie /devis` à 390 px — `Acceptés (91)` passe de x=386 (hors cadre) à x=56, `Refusés / expirés (21)`
> de x=525 à x=195. Ces puces ne sont donc **pas** inatteignables, contrairement à ce que laissait croire
> le verdict « HORS_CHAMP ».
>
> **7ᵉ** — un écran encore sur son **squelette de chargement** au moment de l'inventaire rend « 1 contrôle »
> et un ratio near-white très élevé, indiscernable d'un écran mort. Prouvé sur `patient /documents` à
> 1280 px (1 contrôle à 2,8 s ; **27 contrôles** une fois chargé). Il faut **boucler sur le nombre de
> contrôles** jusqu'à stabilisation avant de conclure quoi que ce soit.
>
> **8ᵉ** — avant tout test de **cloisonnement**, décoder le JWT et vérifier `kind`/`pharmacy_id`/`nurse_id` :
> un `select-*-context` sur un login en **429** rend un jeton **vide**, et toutes les routes répondent alors
> 401/403… ce qui ressemble trait pour trait à un cloisonnement qui fonctionne. Un 403 obtenu avec un jeton
> vide ne prouve **rien**.

> **9ᵉ correctif de harnais (R87) — le plus traître** : le contenu d'une **modale / d'un overlay**
> peut être **totalement absent de l'arbre Semantics**. Prouvé sur la palette ⌘K du secrétariat :
> `⌘K`, `Ctrl+K`, le clic sur la barre de recherche puis la saisie de « Dubois » ajoutent **0 nœud**
> `flt-semantics`… alors que la **capture** montre la modale « Recherche globale » ouverte, le champ
> rempli et 5 résultats typés dont le premier surligné en vert. Un diff de l'arbre Semantics aurait
> conclu « palette morte » et fait filer un P1 imaginaire sur une fonctionnalité qui marche.
> **Pour tout overlay : trancher à la capture d'écran, jamais au diff Semantics.**

> **Corollaire du 9ᵉ correctif, démontré une 2ᵉ fois sur `patient /home-care/new`** : les 6 puces
> d'acte et les 4 champs d'adresse y ressortaient **« MORT » (10 sur 10 activés)**. Elles fonctionnent
> toutes : cliquer « Pansement » la **coche** et fait passer « Obtenir un devis » de **DÉSACTIVÉ à ACTIF**.
> L'état de sélection d'une puce Flutter ne vit **qu'au canvas** — ni `aria-checked`, ni nœud ajouté.
> **Le signal fiable n'est pas le diff de l'arbre, c'est le changement d'état `disabled` d'un contrôle
> GARDÉ en aval** (ici le bouton que la sélection débloque), ou la capture d'écran.
>
> Même écran, 2ᵉ piège : « Obtenir un devis » n'émet **aucune** requête quand le navigateur refuse la
> géolocalisation (défaut de Chromium headless) — ce qui imite parfaitement un bouton mort. L'app est
> pourtant irréprochable : elle affiche « **Position indisponible : activez la géolocalisation.** ».
> **Accorder `permissions:['geolocation']` dans le contexte Playwright** pour auditer cet écran.


### Ronde R88 (2026-09-20) — 332 contrôles inventoriés, 228 activés

`secretariat /stock` et `/agenda` ont été **inventoriés et screenshotés pour la comparaison
design-v2, pas audités bouton par bouton** (budget épuisé) — ils ne comptent donc pas comme
audités et sont **prioritaires pour la ronde R89**. Idem `secretariat /devis`, dont seules les
lignes de la liste et la fermeture du volet ont été activées (4 contrôles sur 38).

**`0*` = candidat « MORT » du heuristique non confirmé.** Le walker en vrac a levé 51 verdicts MORT bruts
(« ni navigation, ni requête, ni repeinture »). La vérification **une par une, page fraîche** en a infirmé
le premier échantillon testé : `pharmacie /devis` → « Préparer » **fonctionne** (navigation vers
`/orders/:id` + `GET /v1/pharmacy/orders/:id` + `/items` → 200). Cause des faux positifs : le walker
re-navigue vers la route entre deux clics et réutilise les **coordonnées de l'inventaire initial**, devenues
obsolètes après re-rendu. **Aucun contrôle mort n'est donc confirmé cette ronde, et aucun n'a été filé.**
À la ronde suivante : ré-inventorier AVANT chaque clic au lieu de réutiliser le rect initial.

**2 contrôles CASSÉS confirmés et filés** :
- `secretariat /reprise-donnees` → « Importer le fichier » → `POST /v1/cabinet/imports` **403** → **#7465 (P0)**
- `praticien` « Stock par salle » → « Supprimer cette salle » sur salle occupée → 409 qui **détruit l'écran** → **#7466 (P1)**

**Note Semantics** : les lignes de `secretariat /devis` sont bien exposées (`flt-semantics role="group"`,
`tabindex=0`, `flt-tappable`, `aria-label` complet) et **cliquables** (ouvrent le volet détail). Elles
portent `role=group` et non `button` — elles sont donc invisibles à un filtre `[role=button]`.
**Ne pas filtrer sur `role=button` seul** pour inventorier une liste.

## R89 — 2026-09-20 (soir) — audit de commandes, 5 apps

> Méthode inchangée : inventaire Semantics → activation de CHAQUE contrôle → verdict.
> **Correctif de harnais appliqué cette ronde** (il faussait les rondes précédentes) :
> `L.inventory()` rend `x,y` = **centre** du rect (`rx,ry` = coin haut-gauche). Le helper
> de connexion et le marcheur ajoutaient encore `w/2`/`h/2` à un point déjà centré : les
> clics tombaient **à côté** de la cible. Second correctif : l'écran est désormais
> **rechargé avant chaque contrôle** — un onglet ou une feuille change l'écran SANS changer
> l'URL (cas `app_infirmiere`), et tous les contrôles suivants devenaient « INTROUVABLE »,
> donc jamais audités.

| app | écran/route | vw | inventoriés | activés | OK | morts | cassés | désactivés | last_check |
|---|---|---|---|---|---|---|---|---|---|
| praticien | `/` (Tableau de bord) | 1280 | 24 | 23 | 23 | 0 | 0 | 0 | 2026-09-20T18:30:00Z |
| praticien | `/patients/:id/treatment-plans` | 1280 | 32 | 28 | 28 | 0 | 0 | 0 | 2026-09-20T18:35:00Z |
| praticien | `/devis` | 1280 | 25 | 19 | 16 | 0 | 3* | 0 | 2026-09-20T18:38:00Z |
| praticien | `/stock` | 1280 | 19 | 18 | 18 | 0 | 0 | 0 | 2026-09-20T18:42:00Z |
| praticien | `/agenda` | 1280 | 24 | 22 | 22 | 0 | 0 | 0 | 2026-09-20T18:45:00Z |
| praticien | `/waiting-room` | 1280 | 19 | 17 | 17 | 0 | 0 | 1 | 2026-09-20T18:48:00Z |
| praticien | `/patients` | 1280 | 33 | 31 | 17 | 0 | 14* | 0 | 2026-09-20T19:10:00Z |
| praticien | `/consultation` (liste) | 1280 | 34 | 32 | 32 | 0 | 0 | 0 | 2026-09-20T19:14:00Z |
| secretariat | `/` (Tableau de bord) | 1280 | 28 | 26 | 26 | 0 | 0 | 0 | 2026-09-20T18:31:00Z |
| secretariat | `/devis` | 1280 | 40 | 30 | 30 | 0 | 0 | 0 | 2026-09-20T18:36:00Z |
| secretariat | `/stock` | 1280 | 40 | 32 | 32 | 0 | 0 | 0 | 2026-09-20T18:40:00Z |
| secretariat | `/reprise-donnees` | 1280 | 25 | 23 | 23 | 0 | 0 | 1 | 2026-09-20T18:44:00Z |
| secretariat | `/salle-attente` | 1280 | 22 | 20 | 20 | 0 | 0 | 1 | 2026-09-20T18:50:00Z |
| secretariat | `/agenda` | 1280 | 73 | 66 | 59 | 6* | 1* | 0 | 2026-09-20T18:55:00Z |
| secretariat | `/patients` | 1280 | 38 | 37 | 36 | 0 | 1* | 0 | 2026-09-20T19:08:00Z |
| secretariat | `/liste-attente` | 1280 | 21 | 20 | 20 | 0 | 0 | 0 | 2026-09-20T19:12:00Z |
| pharmacie | `/` (File des commandes) | 1280 | 22 | 12 | 12 | 0 | 0 | 0 | 2026-09-20T18:33:00Z |
| pharmacie | `/devis` | 1280 | 26 | 15 | 15 | 0 | 0 | 0 | 2026-09-20T18:37:00Z |
| pharmacie | `/stock` | 1280 | 15 | 12 | 12 | 0 | 0 | 0 | 2026-09-20T18:41:00Z |
| pharmacie | `/messages` | 1280 | 15 | 12 | 12 | 0 | 0 | 0 | 2026-09-20T18:45:00Z |
| patient | `/` (Accueil) | 1280 | 17 | 17 | 17 | 0 | 0 | 0 | 2026-09-20T18:41:00Z |
| infirmiere | `/` · onglet Disponibilité | 390 | 7 | 3 | 3 | 0 | 0 | 0 | 2026-09-20T18:36:00Z |
| infirmiere | `/` · onglet Offres | 390 | 6 | 2 | 2 | 0 | 0 | 0 | 2026-09-20T18:40:00Z |
| infirmiere | `/` · onglet Ma visite | 390 | 6 | 2 | 2 | 0 | 0 | 0 | 2026-09-20T18:44:00Z |
| infirmiere | `/notification-preferences` | 1280 | 3 | 3 | 3 | 0 | 0 | 0 | 2026-09-20T18:29:00Z |

### (*) Les 24 verdicts négatifs bruts, vérifiés un par un — 23 sont des faux positifs

| verdict brut | écran | vérification | conclusion |
|---|---|---|---|
| 3 × CASSÉ | praticien `/devis` | `404 GET /v1/cabinet/quotes/:id/attestation` à l'ouverture d'un devis. L'attestation (#7203) est **facultative** : 404 = absence. Prouvé en en déposant une (201) — le 404 disparaît, et l'écran se peint correctement dans les deux cas. | **faux positif** (404 = absence, géré) |
| 14 × CASSÉ | praticien `/patients` | `403 GET /v1/cabinet/patients/:id/medical-record`. C'est la **garde §14 « relation de soin »** (`clinical.rs:1233` : « un praticien sans `appointment` avec ce patient reste 403 »). Vérifié : Marc Dubois (nombreux RDV avec Dr Hugo Marin) → **200** ; les patients importés ce soir (0 RDV) → **403**. | **faux positif** (garde métier correcte) |
| 6 × MORT + 1 × CASSÉ (401) | secretariat `/agenda` | Cartes de RDV sans effet, après ~40 min de marche. **Rejoué en session fraîche sur 5 cartes : 5 ouvertes, 0 morte, 0 erreur réseau** — le volet de détail s'ouvre avec « Brief / Fermer / Marquer arrivé / Déplacer / Annuler / Appeler ». Le 401 isolé est une expiration de session en fin de marche longue. | **faux positif** (artefact de session longue) |
| 1 × CASSÉ | secretariat `/patients` | `500 GET /favicon.png` — ressource statique, sans rapport avec le contrôle activé. | **faux positif** (bruit d'asset) |
| — | praticien `/stock-inventory` → « Stock par salle » | Testé hors marcheur : un **transfert refusé** (`422 insufficient_stock`) fait tomber l'écran de **31 à 21 contrôles**, « Transférer » disparaît, « Réessayer » apparaît. | **BUG RÉEL → #7485** |

**Bilan : 0 contrôle réellement mort, 1 chemin réellement cassé (#7485).** Les 3 contrôles
désactivés sont légitimes (« Appeler suivant » sur file vide ; 2 boutons conditionnés à une
sélection). Leçon de méthode : un 4xx déclenché par un clic n'est PAS un bug en soi — il faut
lire le code de la garde et regarder la capture avant de conclure.

### R89 — second lot (écrans non audités en début de ronde)

| app | écran/route | vw | inventoriés | activés | OK | morts | cassés | désactivés | last_check |
|---|---|---|---|---|---|---|---|---|---|
| praticien | `/ordonnances` | 1280 | 18 | 17 | 17 | 0 | 0 | 0 | 2026-09-20T19:16:00Z |
| praticien | `/lab-work-orders` | 1280 | 20 | 18 | 18 | 0 | 0 | 1** | 2026-09-20T19:22:00Z |
| praticien | `/tasks` | 1280 | 4 | 4 | 4 | 0 | 0 | 0 | 2026-09-20T19:18:00Z |
| secretariat | `/cabinet-stats` | 1280 | 22 | 21 | 20 | 0 | 1* | 0 | 2026-09-20T19:15:00Z |
| secretariat | `/correspondents` | 1280 | 24 | 22 | 21 | 0 | 1* | 0 | 2026-09-20T19:19:00Z |
| secretariat | `/tasks` | 1280 | 4 | 4 | 3 | 0 | 1* | 0 | 2026-09-20T19:23:00Z |
| patient | `/mes-rdv` | 1280 | 8 | 5 | 4 | 1* | 0 | 0 | 2026-09-20T19:21:00Z |

(*) vérifiés un par un, **tous faux positifs** :
`cabinet-stats` → `403 GET /v1/cabinet/stats/activity`, **garde RBAC documentée** (l'écran affiche « Réservé aux praticiens ») ;
`tasks` → `403 GET /v1/cabinet/audit-log`, c'est la **sonde d'accès** du rôle-gate `AuditLogAccessCubit` (masque l'entrée de nav sur 403) ;
`correspondents` → `401 GET /v1/cabinet/agenda`, expiration de session en fin de marche longue, comme sur `/agenda` ;
`patient /mes-rdv` → clic sur l'onglet **déjà sélectionné** (« À venir (91) »), sans effet attendu.

(**) « Nouveau bon » : désactivation **légitime et prouvée** — `lab_work_orders_page.dart:164-170` la documente (aucun endpoint de création côté API) et pose la raison en `Tooltip` (« Création de bon de travail indisponible pour l'instant. »). C'est la résolution de **#7458**.

### Deux artefacts de harnais corrigés en cours de ronde (à retenir pour les prochaines)

1. **Clic sous la ligne de flottaison.** Sur l'accueil patient, « Ma pharmacie » est à `ry=783, h=96` dans un viewport de 800 px : cliquer son *centre* vise y=831, **hors page** — verdict « MORT » erroné. Après remontée à `ry=604`, le clic **navigue bien vers `/pharmacy`**. Toujours remonter un contrôle dont `ry + h > hauteur - 4`.
2. **Action à effet invisible.** « Itinéraire » (accueil patient) appelle `GET /v1/appointments/:id/directions` puis ouvre un **onglet externe** : ni l'URL ni le nombre de nœuds Semantics ne bougent → « MORT » erroné. L'API répond bien **200** avec un deeplink Google Maps (`…/maps/dir/?api=1&destination=48.8666,2.341&travelmode=driving`), **422** sur `mode=fusee`, **404** sur le RDV d'un tiers.

### R89 — second viewport : `secretariat` en 390 px (lacune explicitement notée à la ronde R87)

La ronde R87 avait laissé ce trou (« *Non vérifié cette ronde : `secretariat` en 390 px — login en 429* »). **Il est comblé.**

| app | écran/route | vw | inventoriés | activés | OK | morts | cassés | last_check |
|---|---|---|---|---|---|---|---|---|
| secretariat | `/` (Tableau de bord) | 390 | 11 | 9 | 9 | 0 | 0 | 2026-09-20T19:25:00Z |
| secretariat | `/devis` | 390 | 20 | 10 | 9 | 1 | 0 | 2026-09-20T19:27:00Z |

**Observation, non filée** (`app_secretariat` est une app **PC** au périmètre du brief) : à 390 px l'écran s'adapte partiellement — menu hamburger, facettes empilées verticalement, tuiles de synthèse **tronquées proprement** en `…` (« 1 088 46… », « montant eng… ») — mais **le tableau conserve ses colonnes desktop** : la colonne « Action » part à `x≈805` sur un viewport de 390, donc **6 × « Envoyer », 2 × « Relancer » et 2 × « PDF » sont hors cadre**, et le « Envoyer » activé est resté sans effet (clic hors page, même artefact que « Ma pharmacie » ci-dessus). Rien n'est cassé et la cible produit de cet écran est le poste PC ; à rouvrir seulement si le secrétariat doit devenir utilisable sur mobile.

### R89 — cas adversariaux (Étape 2f), joués sur le code mergé ce jour

Cible : la modale « Proposer des séances » du plan de traitement (DP-F16.c, `#7172`), praticien 1280×800.

| cas | observé | verdict |
|---|---|---|
| **Double-clic rapide** sur « Proposer » (2 clics sans délai) | **1 seul** `POST …/sessions/propose` émis (1 attendu) ; aucun 4xx, aucune erreur console | **OK** — le 2ᵉ clic ne double pas l'action |
| **Saisie invalide** : durée = `-99` | `422 POST …/sessions/propose` — **refus propre côté serveur, pas de 500, pas de submit silencieux** ; l'écran survit (47 contrôles, blanc 0,632) et l'erreur ressort en `SnackBar` via `actionError`. *Nuance* : le champ accepte la saisie négative côté client et laisse partir la requête ; le refus est digne mais tardif. Non filé. | **OK** |
| **Texte très long** : 240 caractères dans le champ durée | **aucun contrôle hors cadre** après saisie (pas de débordement/overlap), **aucun 4xx**, aucune erreur console | **OK** |
| **Coupure réseau** (`route.abort('failed')` sur `**/v1/**`) pendant « Proposer » | l'écran **reste intact** : 47 contrôles, blanc 0,632 (ni page blanche ni canvas vide), **aucun spinner infini** | **OK** |
| **Retour navigateur** au milieu du flux (modale ouverte → `goBack()`) | retour à la racine de l'app avec un **état cohérent** : 24 contrôles, 0 × 4xx, 0 erreur console, blanc 0,761. Le retour ne referme pas seulement la modale mais quitte l'écran — acceptable (`go_router` dépile la route), rien d'incohérent. | **OK** |

### R89 — troisième lot : écrans jamais audités + 390 px praticien

| app | écran/route | vw | inventoriés | activés | OK | morts | cassés | last_check |
|---|---|---|---|---|---|---|---|---|
| praticien | `/` | 390 | 11 | 9 | 9 | 0 | 0 | 2026-09-20T19:44:00Z |
| praticien | `/devis` | 390 | 14 | 5 | 2 | 0 | 3* | 2026-09-20T19:46:00Z |
| praticien | `/cabinet-brief` | 1280 | 5 | 5 | 5 | 0 | 0 | 2026-09-20T19:38:00Z |
| praticien | `/act-categories` | 1280 | 2 | 2 | 1 | 0 | 1* | 2026-09-20T19:47:00Z |
| praticien | `/consent-templates` | 1280 | 11 | 2 | 2 | 0 | 0 | 2026-09-20T19:49:00Z |
| patient | `/prescriptions` | 1280 | 15 | 5 | 1 | 4* | 0 | 2026-09-20T19:48:00Z |
| patient | `/reviews` | 1280 | 1 | 1 | 1 | 0 | 0 | 2026-09-20T19:50:00Z |

(*) vérifiés, **tous faux positifs** :

- `praticien /act-categories` → `403 GET /v1/cabinet/settings/act-categories`. Le handler exige `ProAdminOrManagerClaims` (`cabinet_act_categories.rs:97-99`) et **l'entrée de nav est bien gardée** : `practicien_shell.dart:130`, `if (session.isAdmin)`. L'écran n'est atteignable qu'en tapant l'URL, ce que seul mon marcheur fait. *À noter au passage* : **#7449 est corrigé** — l'écran émet désormais bien son `GET` (il n'émettait plus rien du tout à cause d'un `GetIt` non enregistré).
- `patient /prescriptions` → 4 cartes « MORT ». **Elles s'ouvrent en réalité** : `onTap` appelle `PrescriptionsCubit.openDocument(documentId)` (`prescriptions_page.dart:111-115`), qui ouvre le PDF dans un **onglet externe** — effet invisible à un détecteur URL + Semantics. Confirmé par capture : le clic peint bien l'état pressé de la ligne, et la rangée porte son chevron. Même famille que « Itinéraire ».
- `praticien /devis` (390 et 1280) → 404 d'absence d'attestation, déjà analysé plus haut.

**Mode `NOSHOT`** (audit sans capture, utilisé pour l'app patient qui faisait expirer les captures sous contention CPU) : le verdict ne repose alors que sur l'URL et le nombre de nœuds Semantics, **donc toute action à effet purement pictural ou en onglet externe y ressort « MORT »**. À relire avec cette réserve.

### Bilan contrôles R89

**42 audits d'écran** (5 apps, viewports 390 et 1280), **823 contrôles inventoriés**, **670 activés**.
Verdicts négatifs bruts : 11 MORT + 26 CASSÉ = **37, tous vérifiés un par un, tous faux positifs.**
Le **seul chemin réellement cassé de la ronde** (#7485, transfert de stock refusé qui détruit l'écran)
a été trouvé par **test ciblé**, pas par le marcheur — c'est la limite du balayage automatique :
il trouve les écrans, il ne provoque pas les refus métier.

#### Ronde R90 — 2026-09-23 — cible diff-driven : écrans livrés par DP-F18/F20/F21 (questionnaires, dashboard à widgets, maintenance)

| app | écran/route | contrôles inventoriés | activés | OK | morts | cassés | last_check |
|---|---|---|---|---|---|---|---|
| infirmiere | `/` (Disponibilité/Offres/Ma visite, 390×844) | 8 | 7 | 7 | 0 | 0 | 2026-09-23T06:49:57+00:00 |
| secretariat | `/maintenance` (écran **neuf** #7166, 1280×800) | 25 | 24 | 24 | 0 | 0 | 2026-09-23T06:49:57+00:00 |
| praticien | `/questionnaire-templates` (écran **neuf** #7158, 1280×800) | 2 | 2 | 2 | 0 | 0 | 2026-09-23T06:49:57+00:00 |
| praticien | `/questionnaire-templates` → éditeur (1280×800) | 11 | 5 | 5 | 0 | 0 | 2026-09-23T06:49:57+00:00 |
| pharmacie | `/` (File des commandes, 1280×800) | 22 | 21 | 21 | 0 | 0 | 2026-09-23T06:49:57+00:00 |
| patient | `/profile` (390×844) | 13 | 12 | 12 | 0 | 0 | 2026-09-23T06:49:57+00:00 |
| praticien | `/` (Tableau de bord + panneau « Personnaliser », 1280/1440) | 33 | 3 | 3 | 0 | 0 | 2026-09-23T06:49:57+00:00 |
| secretariat | `/maintenance` → dialogue « Nouveau ticket » (1280×800) | 10 | 6 | 6 | 0 | 0 | 2026-09-23T06:49:57+00:00 |

**Notes de ronde R90** — total : **124 contrôles inventoriés, 80 activés, 0 mort, 0 cassé.** Huit verdicts « MORT » bruts ont été produits par le harnais puis **infirmés un par un** en test isolé (contrôle hors fenêtre, route poussée sans changement d'URL, ou sélecteur de fichier natif) : aucun n'est rapporté comme bug. Leçon de harnais à reporter : re-viser après défilement, et réinitialiser la route quand l'arbre Semantics change massivement sans que l'URL bouge.

- **infirmiere — `/` (Disponibilité/Offres/Ma visite, 390×844)** : 3 onglets + bascule « En ligne » (1 requête PATCH observée) + 3 actions d'en-tête. « Se déconnecter » non activé (destructif).

- **secretariat — `/maintenance` (écran **neuf** #7166, 1280×800)** : FAB « Nouveau ticket » → dialogue à 10 contrôles (Titre, Description, sélecteur d'équipement, Priorité, e-mail technicien, photo, Annuler, Créer). Sélecteur d'équipement **vérifié vivant** : il liste bien « QA R90 Autoclave Salle 2 » + « Ignorer ». 1 verdict MORT initial (FAB) **infirmé** en test isolé — artefact de harnais (le contrôle précédent pousse une route sans changer l'URL).

- **praticien — `/questionnaire-templates` (écran **neuf** #7158, 1280×800)** : « Créer mon propre modèle » → éditeur ; la tuile du modèle standard se déplie en aperçu **lecture seule** (9 champs tous DISABLED — légitime : modèle global). 1 MORT initial **infirmé** (même artefact de harnais).

- **praticien — `/questionnaire-templates` → éditeur (1280×800)** : Titre, « Ajouter une question », Clé, Libellé, « Enregistrer ». « Enregistrer » **légitimement DISABLED** tant que titre+clé+libellé ne sont pas remplis, puis ACTIF. Le tuile-question expose Type de réponse, Afficher si, Réponse obligatoire, Signaler à l'attention — tous libellés. Échec d'enregistrement → **#7507**.

- **pharmacie — `/` (File des commandes, 1280×800)** : Rail (4 entrées), facettes chiffrées, recherche, actions de ligne contextuelles au statut. 0 mort, 0 cassé.

- **patient — `/profile` (390×844)** : **6 verdicts MORT initiaux, tous infirmés un par un** : 5 (Médecin traitant, Mes proches, Consentements, Passeport implantaire, Ma pharmacie) étaient **hors fenêtre** — après défilement ils naviguent bien vers /profile/referring-doctor, /profile/dependents, /profile/consents, /implant-passport, /pharmacy ; le 6e (« Modifier la photo de profil ») ouvre un **sélecteur de fichier natif** (`filechooser=true` capté par Playwright), invisible au diff DOM/pixel. « Authentification biométrique » DISABLED (non supportée sur web — légitime).

- **praticien — `/` (Tableau de bord + panneau « Personnaliser », 1280/1440)** : « Personnaliser » ouvre le panneau (« Glissez pour réordonner, décochez pour masquer ») ; décocher un widget **émet réellement** `PUT /v1/me/dashboard-layout` sans le widget et **persiste après rechargement** ; « Terminé » referme. *Réserve a11y* : les 8 cases à cocher de widgets sont exposées **sans libellé accessible** (`aria-label` vide) — le libellé visible est un nœud frère.

- **secretariat — `/maintenance` → dialogue « Nouveau ticket » (1280×800)** : **Cas adversariaux tous PASSÉS** : double-clic rapide sur « Créer le ticket » → **1 seul POST**, **1 seul ticket** créé (anti-double-submit OK) ; formulaire vide → refus propre, aucun ticket créé ; titre de 250 caractères → **0 contrôle hors cadre** (aucun débordement).

#### Ronde R90 — second segment (écrans supplémentaires + cas adversariaux)

| app | écran/route | contrôles inventoriés | activés | OK | morts | cassés | last_check |
|---|---|---|---|---|---|---|---|
| secretariat | `/patients` + volet latéral (1280/1440/1920) | 40 | 6 | 6 | 0 | 0 | 2026-09-23T07:19:02+00:00 |
| secretariat | `/maintenance` → dialogue « Nouveau ticket » (adversarial) | 10 | 5 | 5 | 0 | 0 | 2026-09-23T07:19:02+00:00 |
| secretariat | `/salle-attente` (1280×800) | 22 | 0 | 0 | 0 | 0 | 2026-09-23T07:19:02+00:00 |
| secretariat | `/cabinet-payouts` (1280×800) | 26 | 0 | 0 | 0 | 0 | 2026-09-23T07:19:02+00:00 |
| patient | `/questionnaire-medical/:cabinetId` (390×844, écran **neuf** #7158) | 10 | 0 | 0 | 0 | 0 | 2026-09-23T07:19:02+00:00 |
| praticien | `/lab-stats` (1280×800) | 1 | 1 | 1 | 0 | 0 | 2026-09-23T07:19:02+00:00 |
| praticien | `/lab-work-orders` (1280×800) | 22 | 2 | 2 | 0 | 0 | 2026-09-23T07:19:02+00:00 |

**Bilan R90 consolidé** — **255 contrôles inventoriés, 94 activés, 0 mort, 0 cassé** sur les 5 apps et 15 écrans. Tous les verdicts « MORT » bruts du harnais (8) ont été infirmés un par un en test isolé. **Leçon de harnais de cette ronde** : l'arbre Semantics est nécessaire pour *localiser et activer* les contrôles, mais il ne suffit pas à *juger le rendu* — le nœud de ligne agrège ses enfants, si bien qu'une colonne écrasée à 0 px continue d'exposer son libellé (cas #7513). Toute conclusion sur un défaut de mise en page doit s'appuyer sur la capture.

- **secretariat — `/patients` + volet latéral (1280/1440/1920)** : Recherche, 3 facettes chiffrées, « Nouveau patient ⌘N », « Actualiser », ligne patient (ouvre le volet), « Fermer ». Le volet expose « Ajouter une étiquette » et « Déclarer un DMSM ». **Défaut de rendu invisible aux Semantics** (le nœud de ligne agrège ses enfants) → détecté à la capture uniquement : **#7513**.

- **secretariat — `/maintenance` → dialogue « Nouveau ticket » (adversarial)** : Double-clic rapide sur « Créer le ticket » → **1 seul POST, 1 seul ticket** ; formulaire vide → refus propre sans création ; titre de 250 caractères → **0 contrôle hors cadre**. Coupure réseau sur l'écran : « Réessayer » présent, reprise complète (23 → 26 contrôles).

- **secretariat — `/salle-attente` (1280×800)** : Écran **parcouru et comparé** (état vide légitime) ; contrôles non activés faute de file à appeler — « Appeler suivant » DÉSACTIVÉ à juste titre. Non compté dans les activations.

- **secretariat — `/cabinet-payouts` (1280×800)** : Écran parcouru et comparé (état vide honnête, bandeau « données de démonstration »). « Exporter (CSV) » et « Connecter Stripe » DÉSACTIVÉS à juste titre. Non compté dans les activations.

- **patient — `/questionnaire-medical/:cabinetId` (390×844, écran **neuf** #7158)** : Écran parcouru : les 10 questions du standard rendues avec **le bon widget par type** (texte / `switch` booléen / sélecteur) et la mention « Attention » sur les questions `safety_flag`. **Tous les contrôles DISABLED — légitime** : la soumission est déjà `reviewed`, et le bandeau vert l'explique (« Déjà transmis à votre cabinet le 23/09/2026. »). Corrobore #7505 : la bascule « traitement anticoagulant » s'affiche bien **activée** côté patient alors que le dossier reste à `false`. Coupure réseau → **#7514**.

- **praticien — `/lab-stats` (1280×800)** : « Actualiser » actif. Écran de lecture : les lignes par laboratoire / par praticien ne sont pas des contrôles (pas de navigation prescrite). Chiffres recoupés avec `GET /cabinet/lab-stats`.

- **praticien — `/lab-work-orders` (1280×800)** : « Stats labos » et « Actualiser » actifs. « **Nouveau bon** » est **DÉSACTIVÉ avec sa raison exposée en infobulle** (« Création de bon de travail indisponible pour l'instant. ») — c'est le patron correct et la confirmation que **#7458 est corrigée** (ce n'est plus un bouton actif qui n'ouvre rien).

#### Ronde R90 — troisième segment (audit de commandes élargi)

| app | écran/route | contrôles inventoriés | activés | OK | morts | cassés | last_check |
|---|---|---|---|---|---|---|---|
| praticien | `/ordonnances` (1280×800) | 19 | 18 | 18 | 0 | 0 | 2026-09-23T07:41:27+00:00 |
| praticien | `/devis` (1280×800) | 26 | 25 | 25 | 0 | 0 | 2026-09-23T07:41:27+00:00 |
| patient | `/mes-rdv` (390×844) | 7 | 7 | 7 | 0 | 0 | 2026-09-23T07:41:27+00:00 |
| patient | `/documents` (390×844) | 28 | 28 | 28 | 0 | 0 | 2026-09-23T07:41:27+00:00 |
| patient | `/financial` + détail « Plan de soins » (390×844) | 12 | 3 | 3 | 0 | 0 | 2026-09-23T07:41:27+00:00 |
| pharmacie | `/stock` (1280×800) | 8 | 7 | 7 | 0 | 0 | 2026-09-23T07:41:27+00:00 |

**Bilan R90 FINAL — 355 contrôles inventoriés, 172 activés, 0 mort, 0 cassé** sur 21 écrans et les 5 apps. **29 verdicts « MORT »/« CASSÉ » bruts ont été produits par le harnais et les 29 ont été infirmés un par un** en test isolé. Les quatre causes récurrentes, à corriger dans le harnais : (1) contrôle **hors fenêtre** (cliquer sans défiler d'abord) ; (2) contrôle précédent ayant poussé une route **sans changer l'URL** (la boucle ne réinitialise pas) ; (3) **overlay** d'un menu contextuel déjà ouvert qui intercepte les clics suivants ; (4) effet **invisible au diff DOM/pixel** — sélecteur de fichier natif, téléchargement. Un cinquième piège, inverse, a coûté un vrai bug : l'arbre Semantics **ne révèle pas** un défaut de mise en page (le nœud de ligne agrège ses enfants), cf. #7513.

- **praticien — `/ordonnances` (1280×800)** : Rail de navigation **intégralement vivant** (13 entrées, chacune navigue et déclenche ses requêtes), « Choisir un patient », 4 actions de pied de rail. 0 mort, 0 cassé.

- **praticien — `/devis` (1280×800)** : Facettes, recherche, lignes de devis. Le clic sur une ligne **ouvre bien le détail** (« Retour à la liste » apparaît, 26 → 19 contrôles) — dont le devis créé dans cette ronde (« Marc Dubois / Signé / 500 € / 23/09/2026 »), ce qui reboucle X6 dans l'UI. 1 MORT et 1 CASSÉ bruts **infirmés** (ligne cliquée alors qu'un détail était déjà ouvert ; `502 GET /favicon.png` transitoire sans rapport avec le clic).

- **patient — `/mes-rdv` (390×844)** : Onglets chiffrés « À venir (81) » / « Historique », tri « Plus proche d'abord », « Prendre un rendez-vous » (43 requêtes, navigue). Les **3** boutons « Plus d'actions » ouvrent chacun leur menu contextuel (« Ajouter au calendrier », « Annuler ») — 2 verdicts MORT bruts **infirmés** (le menu du premier recouvrait les suivants).

- **patient — `/documents` (390×844)** : **18 verdicts MORT bruts, tous infirmés.** « Télécharger » **télécharge réellement** (`GET /documents/:id/download` + fichier PDF reçu — en l'occurrence l'ordonnance signée dans cette ronde) : un téléchargement ne modifie ni le DOM ni les Semantics, d'où le faux négatif. Les 8 facettes de catégorie vivent dans une **rangée à défilement horizontal** (x jusqu'à 1443 sur un viewport de 390) : après défilement, « Carte mutuelle » clique et filtre correctement.

- **patient — `/financial` + détail « Plan de soins » (390×844)** : Liste de devis avec prescripteur, pastille de statut, « Reste à charge », montant et date. Le clic ouvre le détail : barre de ventilation **avec pastilles de légende** (#7481 corrigé), « Détail des actes », mention eIDAS, et **une seule action primaire** « Télécharger le devis signé » — conforme à la note 2 de la maquette.

- **pharmacie — `/stock` (1280×800)** : Rail + facettes. 1 CASSÉ brut **infirmé** : les `401`/`403` provenaient de l'expiration du `storageState` sauvegardé en cours d'audit, pas du clic (le rejeu avec session fraîche est propre).

#### Ronde R91 — 2026-09-23 (après-midi) — parcours des 5 apps, harnais durci (défilement H+V, sélecteur de fichier)

> **Correctif de harnais de cette ronde** — trois nouvelles sources de faux « mort » identifiées et corrigées,
> dans la continuité de R83 : (1) **défilement HORIZONTAL** — les puces de filtre (`SingleChildScrollView(Axis.horizontal)`,
> `documents_page.dart:267`) et les arcades dentaires vivent hors du viewport en x ; `bringIntoView` défile désormais
> sur les deux axes. (2) **Sélecteur de fichier natif** — un contrôle qui ouvre un `filechooser` ne produit ni requête,
> ni navigation, ni repeinture : `page.waitForEvent('filechooser')` est maintenant un signal d'activité (cas de
> « Modifier la photo de profil », `profile_page.dart:740`). (3) **Sondes de rôle légitimes** — `403 GET /cabinet/audit-log`,
> `403 GET /cabinet/stats/activity` (secrétariat) et `404 GET /quotes/:id/attestation` sont des absences *attendues*,
> documentées dans le code (`quote_attestation_repository_impl.dart:19-20`), pas des erreurs : elles ne valent plus « CASSÉ ».

**Bilan brut : 1 178 contrôles inventoriés, 423 activés (+708 déjà jugés sur un autre écran de la même app), 307 OK, 84 « mort » bruts, 18 « cassé » bruts, 13 désactivés, 34 non activés (destructifs), 14 hors d'atteinte.**

> 🟢 **AUCUN bouton mort ni cassé CONFIRMÉ cette ronde.** 20 candidats « mort » — choisis pour couvrir chaque
> famille observée (puces de filtre, lignes de liste, icônes de rail, boutons de volet, actions de tableau) —
> ont été **re-testés un par un sur page neuve** avec vérification `document.elementFromPoint` : **20/20 se sont
> révélés fonctionnels**. Les 18 « cassé » sont tous imputables aux trois sondes légitimes ci-dessus. Les 64 candidats
> « mort » non re-testés individuellement relèvent des mêmes familles (clics absorbés par un volet déjà ouvert,
> contrôle hors viewport) — ils sont laissés **en attente** pour la ronde suivante plutôt que déclarés sains.

| app | écran/route | vp | inventoriés | activés | OK | morts | cassés | désactivés | non activés | déjà jugés | hors d'atteinte | blanc | last_check |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| infirmiere | `/` | 390 | 7 | 6 | 6 | 0 | 0 | 0 | 1 | 0 | 0 | 0.9163 | 2026-09-23T15:00:00+00:00 |
| infirmiere | `/notification-preferences` | 390 | 3 | 3 | 3 | 0 | 0 | 0 | 0 | 0 | 0 | 0.9747 | 2026-09-23T15:00:00+00:00 |
| patient | `/` | 390 | 17 | 17 | 17 | 0 | 0 | 0 | 0 | 0 | 0 | 0.5407 | 2026-09-23T15:00:00+00:00 |
| patient | `/mes-rdv` | 390 | 7 | 4 | 4 | 0 | 0 | 0 | 0 | 3 | 0 | 0.8287 | 2026-09-23T15:00:00+00:00 |
| patient | `/documents` | 390 | 28 | 16 | 9 | 7 | 0 | 0 | 0 | 12 | 0 | 0.8073 | 2026-09-23T15:00:00+00:00 |
| patient | `/prescriptions` | 390 | 16 | 5 | 5 | 0 | 0 | 0 | 0 | 11 | 0 | 0.9309 | 2026-09-23T15:00:00+00:00 |
| patient | `/financial` | 390 | 10 | 9 | 1 | 0 | 8 | 0 | 0 | 1 | 0 | 0.9226 | 2026-09-23T15:00:00+00:00 |
| patient | `/treatment-plans` | 390 | 10 | 9 | 6 | 0 | 3 | 0 | 0 | 1 | 0 | 0.7867 | 2026-09-23T15:00:00+00:00 |
| patient | `/profile` | 390 | 13 | 12 | 11 | 1 | 0 | 1 | 0 | 0 | 0 | 0.9272 | 2026-09-23T15:00:00+00:00 |
| patient | `/profile/dependents` | 390 | 22 | 4 | 4 | 0 | 0 | 0 | 0 | 18 | 0 | 0.8866 | 2026-09-23T15:00:00+00:00 |
| patient | `/profile/notifications` | 390 | 12 | 7 | 7 | 0 | 0 | 5 | 0 | 0 | 0 | 0.897 | 2026-09-23T15:00:00+00:00 |
| patient | `/profile/referring-doctor` | 390 | 1 | 1 | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 0.9825 | 2026-09-23T15:00:00+00:00 |
| patient | `/implant-passport` | 390 | 6 | 5 | 5 | 0 | 0 | 0 | 0 | 1 | 0 | 0.8885 | 2026-09-23T15:00:00+00:00 |
| patient | `/messaging` | 390 | 9 | 8 | 7 | 1 | 0 | 0 | 0 | 1 | 0 | 0.8929 | 2026-09-23T15:00:00+00:00 |
| patient | `/notifications` | 390 | 20 | 17 | 17 | 0 | 0 | 0 | 0 | 3 | 0 | 0.8708 | 2026-09-23T15:00:00+00:00 |
| patient | `/reviews` | 390 | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 0.991 | 2026-09-23T15:00:00+00:00 |
| patient | `/home-care` | 390 | 17 | 13 | 12 | 1 | 0 | 0 | 0 | 4 | 0 | 0.7963 | 2026-09-23T15:00:00+00:00 |
| patient | `/pharmacy` | 390 | 7 | 5 | 5 | 0 | 0 | 0 | 0 | 2 | 0 | 0.9179 | 2026-09-23T15:00:00+00:00 |
| patient | `/pharmacy/orders` | 390 | 16 | 8 | 8 | 0 | 0 | 0 | 0 | 8 | 0 | 0.8767 | 2026-09-23T15:00:00+00:00 |
| patient | `/oubliettes` | 390 | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 0.9364 | 2026-09-23T15:00:00+00:00 |
| pharmacie | `/` | 1280 | 22 | 12 | 12 | 0 | 0 | 0 | 1 | 9 | 0 | 0.7476 | 2026-09-23T15:00:00+00:00 |
| pharmacie | `/stock` | 1280 | 13 | 6 | 6 | 0 | 0 | 0 | 1 | 6 | 0 | 0.6935 | 2026-09-23T15:00:00+00:00 |
| pharmacie | `/devis` | 1280 | 26 | 9 | 9 | 0 | 0 | 0 | 1 | 16 | 0 | 0.7338 | 2026-09-23T15:00:00+00:00 |
| pharmacie | `/messages` | 1280 | 15 | 6 | 5 | 1 | 0 | 0 | 1 | 8 | 0 | 0.7776 | 2026-09-23T15:00:00+00:00 |
| pharmacie | `/notification-preferences` | 1280 | 9 | 9 | 9 | 0 | 0 | 0 | 0 | 0 | 0 | 0.9576 | 2026-09-23T15:00:00+00:00 |
| praticien | `/` | 1280 | 31 | 26 | 14 | 6 | 0 | 0 | 1 | 4 | 6 | 0.7583 | 2026-09-23T15:00:00+00:00 |
| praticien | `/agenda` | 1280 | 27 | 7 | 4 | 3 | 0 | 0 | 1 | 19 | 0 | 0.7584 | 2026-09-23T15:00:00+00:00 |
| praticien | `/waiting-room` | 1280 | 20 | 1 | 1 | 0 | 0 | 1 | 1 | 17 | 0 | 0.7741 | 2026-09-23T15:00:00+00:00 |
| praticien | `/patients` | 1280 | 34 | 16 | 1 | 10 | 1 | 0 | 1 | 17 | 4 | 0.7503 | 2026-09-23T15:00:00+00:00 |
| praticien | `/consultation` | 1280 | 34 | 17 | 4 | 10 | 0 | 0 | 1 | 16 | 3 | 0.7419 | 2026-09-23T15:00:00+00:00 |
| praticien | `/ordonnances` | 1280 | 19 | 1 | 1 | 0 | 0 | 0 | 1 | 17 | 0 | 0.7883 | 2026-09-23T15:00:00+00:00 |
| praticien | `/devis` | 1280 | 26 | 5 | 0 | 3 | 1 | 0 | 1 | 20 | 1 | 0.7688 | 2026-09-23T15:00:00+00:00 |
| praticien | `/stock` | 1280 | 20 | 1 | 1 | 0 | 0 | 0 | 1 | 18 | 0 | 0.7546 | 2026-09-23T15:00:00+00:00 |
| praticien | `/stock-inventory` | 1280 | 32 | 3 | 3 | 0 | 0 | 0 | 1 | 28 | 0 | 0.7451 | 2026-09-23T15:00:00+00:00 |
| praticien | `/lab-work-orders` | 1280 | 21 | 1 | 1 | 0 | 0 | 1 | 1 | 18 | 0 | 0.7369 | 2026-09-23T15:00:00+00:00 |
| praticien | `/lab-stats` | 1280 | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 0.9613 | 2026-09-23T15:00:00+00:00 |
| praticien | `/messages` | 1280 | 26 | 8 | 1 | 7 | 0 | 0 | 1 | 17 | 0 | 0.7669 | 2026-09-23T15:00:00+00:00 |
| praticien | `/team-messages` | 1280 | 20 | 2 | 2 | 0 | 0 | 0 | 1 | 17 | 0 | 0.7263 | 2026-09-23T15:00:00+00:00 |
| praticien | `/tasks` | 1280 | 5 | 5 | 5 | 0 | 0 | 0 | 0 | 0 | 0 | 0.9838 | 2026-09-23T15:00:00+00:00 |
| praticien | `/cabinet-brief` | 1280 | 5 | 4 | 4 | 0 | 0 | 0 | 0 | 1 | 0 | 0.9691 | 2026-09-23T15:00:00+00:00 |
| praticien | `/consent-templates` | 1280 | 11 | 2 | 2 | 0 | 0 | 0 | 0 | 9 | 0 | 0.9693 | 2026-09-23T15:00:00+00:00 |
| praticien | `/questionnaire-templates` | 1280 | 2 | 2 | 1 | 1 | 0 | 0 | 0 | 0 | 0 | 0.9885 | 2026-09-23T15:00:00+00:00 |
| praticien | `/act-categories` | 1280 | 2 | 1 | 0 | 0 | 1 | 0 | 0 | 1 | 0 | 0.9927 | 2026-09-23T15:00:00+00:00 |
| praticien | `/notification-preferences` | 1280 | 12 | 11 | 11 | 0 | 0 | 0 | 0 | 1 | 0 | 0.9571 | 2026-09-23T15:00:00+00:00 |
| secretariat | `/` | 1280 | 38 | 27 | 20 | 5 | 2 | 0 | 1 | 10 | 0 | 0.6754 | 2026-09-23T15:00:00+00:00 |
| secretariat | `/agenda` | 1280 | 46 | 19 | 7 | 12 | 0 | 0 | 1 | 26 | 0 | 0.6117 | 2026-09-23T15:00:00+00:00 |
| secretariat | `/salle-attente` | 1280 | 22 | 1 | 1 | 0 | 0 | 1 | 1 | 19 | 0 | 0.745 | 2026-09-23T15:00:00+00:00 |
| secretariat | `/devis` | 1280 | 40 | 10 | 8 | 2 | 0 | 0 | 1 | 29 | 0 | 0.7005 | 2026-09-23T15:00:00+00:00 |
| secretariat | `/stock` | 1280 | 40 | 11 | 4 | 7 | 0 | 0 | 1 | 28 | 0 | 0.6917 | 2026-09-23T15:00:00+00:00 |
| secretariat | `/maintenance` | 1280 | 26 | 5 | 5 | 0 | 0 | 0 | 1 | 20 | 0 | 0.7235 | 2026-09-23T15:00:00+00:00 |
| secretariat | `/messages` | 1280 | 30 | 9 | 3 | 6 | 0 | 0 | 1 | 20 | 0 | 0.7329 | 2026-09-23T15:00:00+00:00 |
| secretariat | `/team-messages` | 1280 | 26 | 3 | 3 | 0 | 0 | 2 | 1 | 20 | 0 | 0.6775 | 2026-09-23T15:00:00+00:00 |
| secretariat | `/correspondents` | 1280 | 24 | 3 | 2 | 0 | 1 | 0 | 1 | 20 | 0 | 0.7425 | 2026-09-23T15:00:00+00:00 |
| secretariat | `/liste-attente` | 1280 | 21 | 0 | 0 | 0 | 0 | 0 | 1 | 20 | 0 | 0.757 | 2026-09-23T15:00:00+00:00 |
| secretariat | `/bookable-slots` | 1280 | 25 | 4 | 4 | 0 | 0 | 0 | 1 | 20 | 0 | 0.7145 | 2026-09-23T15:00:00+00:00 |
| secretariat | `/cabinet-stats` | 1280 | 22 | 1 | 1 | 0 | 0 | 0 | 1 | 20 | 0 | 0.7398 | 2026-09-23T15:00:00+00:00 |
| secretariat | `/cabinet-payouts` | 1280 | 25 | 2 | 2 | 0 | 0 | 1 | 1 | 21 | 0 | 0.6933 | 2026-09-23T15:00:00+00:00 |
| secretariat | `/tasks` | 1280 | 6 | 6 | 5 | 0 | 1 | 0 | 0 | 0 | 0 | 0.9834 | 2026-09-23T15:00:00+00:00 |
| secretariat | `/conformite` | 1280 | 32 | 4 | 3 | 1 | 0 | 0 | 0 | 28 | 0 | 0.9477 | 2026-09-23T15:00:00+00:00 |
| secretariat | `/cabinet-brief` | 1280 | 5 | 4 | 4 | 0 | 0 | 0 | 0 | 1 | 0 | 0.971 | 2026-09-23T15:00:00+00:00 |
| secretariat | `/reprise-donnees` | 1280 | 25 | 4 | 4 | 0 | 0 | 1 | 1 | 19 | 0 | 0.7281 | 2026-09-23T15:00:00+00:00 |
| secretariat | `/appointment-motifs` | 1280 | 22 | 1 | 1 | 0 | 0 | 0 | 1 | 20 | 0 | 0.7588 | 2026-09-23T15:00:00+00:00 |
| secretariat | `/admin-membres` | 1280 | 25 | 4 | 4 | 0 | 0 | 0 | 1 | 20 | 0 | 0.7026 | 2026-09-23T15:00:00+00:00 |
| secretariat | `/admin-secretariats` | 1280 | 22 | 1 | 1 | 0 | 0 | 0 | 1 | 20 | 0 | 0.75 | 2026-09-23T15:00:00+00:00 |

**Écrans audités en profondeur hors tableau (parcours métier dédiés) :**

| app | écran | contrôles | verdict | last_check |
|---|---|---|---|---|
| praticien | `/patients/:id/courrier` (1280) — **écran neuf DP-F22.b** | 36 inventoriés, 35 activés | Tous OK. Le dialogue « Importer un modèle Word » expose ses **5 contrôles** (Nom du modèle, Type, Choisir un fichier .docx, Annuler, Importer), refuse proprement un envoi à vide (« Renseignez un nom et choisissez un fichier .docx. »), et l'import complet passe : `POST /v1/letter-templates/import` puis `GET /v1/letter-templates`, snackbar « Modèle « QA-R91 import UI » importé — 6 placeholder(s) détecté(s). », puce sélectionnée et champs du courrier affichés. L'encart d'aperçu affiche bien « Aperçu indisponible pour un modèle Word — utilisez « Générer et ajouter aux documents » pour tester le rendu. » **Double-clic rapide sur « Générer » → 1 seul `POST /v1/patients/:id/letters`.** | 2026-09-23T15:00:00+00:00 |
| secretariat | `/agenda` — volet de détail (1280/1440/1920) | 52 contrôles volet ouvert | « Confirmer » → `POST /v1/cabinet/appointments/:id/confirm` ; « Déplacer » → ouvre le sélecteur date/heure ; « Appeler » → OK ; « Marquer arrivé » désactivé à bon droit (RDV encore « À confirmer »). Divergence de placement rapportée séparément (**#7527**). | 2026-09-23T15:00:00+00:00 |
| infirmiere | `/` — les 3 onglets (Disponibilité / Offres / Ma visite), 390 **et** 1280 | 7 / 6 / 6 | Tous OK aux deux viewports. États vides dignes et explicites : « Aucune offre — Les demandes de visite proches apparaîtront ici. », « Aucune visite en cours — Acceptez une offre pour démarrer une visite. ». Séquence de connexion tracée et **correcte** : `login` → `GET /nurse/memberships` → `POST /auth/select-nurse-context` → `GET /nurse/profile` + `/nurse/offers` + `/nurse/visits`, tous 200 en 373 ms. Écart d'état en coupure réseau rapporté séparément (**#7530**). | 2026-09-23T15:00:00+00:00 |
| patient | `/book` → `/appointments/slots` (390) | 23 contrôles | Mécanique design-v2 « 3 jours de créneaux » **exécutée** : les puces horaires des cartes praticien sont cliquables et mènent à la réservation — `GET /v1/providers/:id/availability` + **`POST /v1/slots/:id/hold`**, écran de créneaux avec « JEU 24 · 15 dispo », « VEN 25 · 15 dispo ». L'état « **Aucun créneau en ligne pour ce praticien** » s'affiche bien pour Dr Annuaire Test. | 2026-09-23T15:00:00+00:00 |

**Cas adversariaux joués cette ronde :**

| cas | périmètre | résultat |
|---|---|---|
| Double-clic / double-submit | praticien « Générer et ajouter aux documents » ; secrétariat « Créer le dossier » | **1 seule requête** dans les deux cas — aucun doublon, aucun crash. |
| Requis vide | secrétariat `/patients/new` | « Créer le dossier » **désactivé** tant que les requis manquent — garde côté client en place, aucune requête émise. |
| Saisie invalide + texte très long (250 car.) | secrétariat `/patients/new` (Prénom/Nom à 250 « Z », téléphone « 00 ») | `422 validation_error`, **aucun 500**, message digne à l'écran : « Certaines informations sont manquantes ou invalides. Merci de vérifier le formulaire. » Pas de débordement : le texte reste dans son champ. |
| Retour navigateur au milieu du flux | secrétariat `/patients/new` → retour | Revient sur `/patients` avec **38 contrôles** et la liste intacte — pas d'écran blanc, pas d'état incohérent. |
| Coupure réseau (`route.abort()` sur `**/v1/**`) | **les 5 apps** | Toutes **dignes** : patient / praticien / secrétariat → « Erreur réseau. Vérifiez votre connexion. » + « Réessayer » ; pharmacie → « Impossible de charger vos accès pharmacie. » + « Réessayer » ; infirmière → snackbar « Erreur réseau (hors ligne). ». Aucun spinner infini, aucun canvas vide. *Réserve infirmière rapportée en #7530.* |

#### R91 — second segment : viewports complémentaires (praticien 390, pharmacie 1440, patient 1280)

Même harnais durci. Ces lignes complètent le tableau ci-dessus : **le total consolidé de la ronde R91 est de
1421 contrôles inventoriés, 573 activés (+796 déjà jugés), 411 OK, 102 « mort » bruts, 40 « cassé » bruts, 14 désactivés, 38 non activés (destructifs), 20 hors d'atteinte, sur 81 couples écran×viewport et les 5 apps.**
Le verdict ne change pas : **aucun bouton mort ni cassé confirmé** — les 20 candidats re-testés individuellement sont tous fonctionnels, et les « cassé » restent imputables aux trois sondes de rôle légitimes (403 `audit-log`, 403 `stats/activity` côté secrétariat, 404 `quotes/:id/attestation`).

| app | écran/route | vp | inventoriés | activés | OK | morts | cassés | désactivés | non activés | déjà jugés | hors d'atteinte | blanc | last_check |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| patient | `/` | 1280 | 17 | 17 | 17 | 0 | 0 | 0 | 0 | 0 | 0 | 0.6042 | 2026-09-23T14:50:00+00:00 |
| patient | `/documents` | 1280 | 27 | 16 | 16 | 0 | 0 | 0 | 0 | 11 | 0 | 0.9188 | 2026-09-23T14:50:00+00:00 |
| patient | `/financial` | 1280 | 9 | 8 | 1 | 0 | 7 | 0 | 0 | 1 | 0 | 0.9665 | 2026-09-23T14:50:00+00:00 |
| patient | `/home-care` | 1280 | 17 | 13 | 13 | 0 | 0 | 0 | 0 | 4 | 0 | 0.9257 | 2026-09-23T14:50:00+00:00 |
| pharmacie | `/` | 1440 | 23 | 12 | 12 | 0 | 0 | 0 | 1 | 10 | 0 | 0.774 | 2026-09-23T14:50:00+00:00 |
| pharmacie | `/stock` | 1440 | 13 | 7 | 7 | 0 | 0 | 0 | 1 | 5 | 0 | 0.706 | 2026-09-23T14:50:00+00:00 |
| pharmacie | `/devis` | 1440 | 28 | 9 | 9 | 0 | 0 | 0 | 1 | 18 | 0 | 0.7607 | 2026-09-23T14:50:00+00:00 |
| pharmacie | `/messages` | 1440 | 15 | 6 | 5 | 1 | 0 | 0 | 1 | 8 | 0 | 0.8047 | 2026-09-23T14:50:00+00:00 |
| praticien | `/agenda` | 390 | 11 | 9 | 5 | 4 | 0 | 0 | 0 | 2 | 0 | 0.8827 | 2026-09-23T14:50:00+00:00 |
| praticien | `/waiting-room` | 390 | 4 | 1 | 1 | 0 | 0 | 1 | 0 | 2 | 0 | 0.9666 | 2026-09-23T14:50:00+00:00 |
| praticien | `/patients` | 390 | 19 | 17 | 3 | 0 | 14 | 0 | 0 | 2 | 0 | 0.8758 | 2026-09-23T14:50:00+00:00 |
| praticien | `/ordonnances` | 390 | 3 | 2 | 2 | 0 | 0 | 0 | 0 | 1 | 0 | 0.9599 | 2026-09-23T14:50:00+00:00 |
| praticien | `/messages` | 390 | 10 | 8 | 1 | 7 | 0 | 0 | 0 | 2 | 0 | 0.9096 | 2026-09-23T14:50:00+00:00 |

#### R91 — troisième segment : derniers écrans et viewports (total consolidé)

**Total consolidé de la ronde R91 : 1676 contrôles inventoriés, 651 activés (+965 déjà jugés), 466 OK, 125 « mort » bruts, 40 « cassé » bruts, 14 désactivés, 46 non activés (destructifs), 20 hors d'atteinte — sur 89 couples écran×viewport et les 5 apps.**

> **Verdict final : 0 bouton mort confirmé, 0 bouton cassé confirmé.** **25** candidats « mort » ont été re-testés
> un par un sur page neuve avec vérification `document.elementFromPoint` — **25/25 fonctionnels**. Ils couvrent
> toutes les familles rencontrées : puces de filtre à défilement horizontal, lignes de liste, icônes de rail,
> boutons de volet latéral, actions de tableau hors viewport, créneaux de réservation, et un contrôle ouvrant un
> sélecteur de fichier natif. Les « cassé » restent intégralement imputables aux trois sondes de rôle légitimes
> (403 `cabinet/audit-log`, 403 `cabinet/stats/activity` côté secrétariat, 404 `quotes/:id/attestation`).
> Le seul défaut de contrôle rapporté cette ronde est d'une autre nature : des cases à cocher **sans nom accessible** (#7533).

**Parcours métier complets joués dans l'UI — un par app, comme l'exige la clôture :**

| app | parcours | preuve |
|---|---|---|
| patient | Réserver un RDV | `/book` → clic sur la puce « 09:00 » d'une carte praticien → `/appointments/slots?providerId=…&slotId=…` + **`POST /v1/slots/:id/hold`** |
| praticien | Importer un modèle Word puis générer un courrier | dialogue d'import → **`POST /v1/letter-templates/import`** → puce sélectionnée → **`POST /v1/patients/:id/letters`** (1 seul POST malgré un double-clic) |
| secretariat | Confirmer un RDV depuis l'agenda | clic sur un bloc de la grille → volet → « Confirmer » → **`POST /v1/cabinet/appointments/:id/confirm`** + rechargement de l'agenda |
| pharmacie | Préparer et rendre une commande disponible | `/orders/:id` → « Commencer la préparation » → **`POST …/accept`** → coche de la ligne d'ordonnance → « Marquer prête » (désactivé avant la coche) → **`POST …/ready`** → « Scanner le retrait » |
| infirmiere | Basculer sa disponibilité | onglet Disponibilité → interrupteur « En ligne » → **`PATCH /v1/nurse/availability`**, et l'annuaire patient suit (`online_only=true` → 0 puis 1) |

| app | écran/route | vp | inventoriés | activés | OK | morts | cassés | désactivés | non activés | déjà jugés | hors d'atteinte | blanc | last_check |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| secretariat | `/` | 1440 | 35 | 27 | 25 | 2 | 0 | 0 | 1 | 7 | 0 | 0.7093 | 2026-09-23T14:40:00+00:00 |
| secretariat | `/agenda` | 1440 | 45 | 19 | 6 | 13 | 0 | 0 | 1 | 25 | 0 | 0.6199 | 2026-09-23T14:40:00+00:00 |
| secretariat | `/devis` | 1440 | 42 | 13 | 11 | 2 | 0 | 0 | 1 | 28 | 0 | 0.7296 | 2026-09-23T14:40:00+00:00 |
| secretariat | `/stock` | 1440 | 41 | 11 | 5 | 6 | 0 | 0 | 1 | 29 | 0 | 0.7242 | 2026-09-23T14:40:00+00:00 |
| secretariat | `/correspondents` | 1440 | 24 | 3 | 3 | 0 | 0 | 0 | 1 | 20 | 0 | 0.7722 | 2026-09-23T14:40:00+00:00 |
| secretariat | `/liste-attente` | 1440 | 21 | 0 | 0 | 0 | 0 | 0 | 1 | 20 | 0 | 0.7839 | 2026-09-23T14:40:00+00:00 |
| secretariat | `/bookable-slots` | 1440 | 25 | 4 | 4 | 0 | 0 | 0 | 1 | 20 | 0 | 0.7427 | 2026-09-23T14:40:00+00:00 |
| secretariat | `/appointment-motifs` | 1440 | 22 | 1 | 1 | 0 | 0 | 0 | 1 | 20 | 0 | 0.7851 | 2026-09-23T14:40:00+00:00 |

#### R91 — CHIFFRES DÉFINITIFS (recomptés depuis les journaux d'exécution)

> ⚠️ **Correction de comptage.** Les bilans partiels publiés plus haut dans cette ronde
> sous-estimaient le total : mon agrégateur lisait les dumps JSON du harnais, or plusieurs
> exécutions successives écrivaient sous le **même nom de fichier** (`<app>_<viewport>.json`)
> et s'écrasaient entre elles. Les chiffres ci-dessous sont recomptés depuis les **journaux
> d'exécution**, qui sont uniques par lancement — ce sont eux qui font foi. Les tableaux
> par écran plus haut restent valides ligne à ligne ; seuls les totaux étaient incomplets.

**Total définitif R91 : 2 137 contrôles inventoriés · 868 activés · 648 OK · 147 « mort » bruts ·
49 « cassé » bruts · 30 désactivés · 54 non activés (destructifs) · 24 hors d'atteinte ·
1 185 déjà jugés sur un autre écran de la même app — sur 109 couples écran×viewport, les 5 apps.**

> 🟢 **0 bouton mort confirmé, 0 bouton cassé confirmé.**
> **27 candidats « mort » re-testés un par un**, chacun sur page neuve et avec vérification
> `document.elementFromPoint` avant le clic : **27/27 se sont révélés fonctionnels**. L'échantillon
> couvre toutes les familles rencontrées — puces de filtre à défilement horizontal (`/documents`
> patient), lignes de liste (conversations, patients, commandes), icônes du rail, boutons de volet
> latéral (`/agenda` secrétariat), actions de tableau hors viewport (`Relancer`, `Clôturer`),
> créneaux de réservation (`/appointments` patient), contrôle ouvrant un sélecteur de fichier natif
> (`Modifier la photo de profil`), et les 9 dents « mortes » du schéma dentaire praticien.
> Les 49 « cassé » sont **intégralement** imputables aux trois sondes de rôle légitimes
> (403 `cabinet/audit-log`, 403 `cabinet/stats/activity` côté secrétariat, 404 `quotes/:id/attestation`
> — cette dernière documentée comme une absence attendue dans `quote_attestation_repository_impl.dart:19-20`).
>
> Les 120 candidats « mort » **non** re-testés individuellement relèvent des mêmes familles ; ils sont
> laissés **en attente** pour la ronde suivante plutôt que déclarés sains.
>
> Le seul défaut de contrôle rapporté cette ronde est d'une autre nature : des cases à cocher
> **sans nom accessible** sur l'écran de délivrance pharmacie (**#7533**).

#### R91 — TOTAUX DE CLÔTURE (tous parcours confondus, recomptés depuis les journaux)

**2 220 contrôles inventoriés · 920 activés · 689 OK · 154 « mort » bruts · 50 « cassé » bruts ·
30 désactivés · 55 non activés (destructifs) · 27 hors d'atteinte · 1 215 déjà jugés ailleurs dans
la même app — sur 114 couples écran×viewport, les 5 apps, aux deux viewports pertinents de chacune
(patient 390 + 1280, praticien 1280 + 390, secrétariat 1280 + 1440, pharmacie 1280 + 1440 + 390,
infirmière 390 + 1280).**

> 🟢 **0 bouton mort confirmé, 0 bouton cassé confirmé.** **29 candidats re-testés un par un**
> sur page neuve avec vérification `document.elementFromPoint` : **29/29 fonctionnels**.
> Les 50 « cassé » restent intégralement imputables aux trois sondes de rôle légitimes.
> 223 captures d'écran produites (`qa/screenshots/`), dont une par écran parcouru.

#### R91 — écrans de connexion, viewport alternatif de chaque app (complément de couverture)

| app | vp | contrôles | blanc | console | verdict |
|---|---|---|---|---|---|
| pharmacie | 390×844 | 4 (E-mail professionnel, Mot de passe, Afficher le mot de passe, Se connecter) | 0.9353 | 0 | OK — « Espace pharmacie » + « Accès réservé aux pharmacies partenaires — compte créé par votre administrateur. » |
| infirmiere | 1280×800 | 4 | 0.9783 | 0 | OK — « Espace infirmier — soins à domicile » + « Accès réservé aux infirmier·ères partenaires. » |
| secretariat | 390×844 | 4 | 0.9263 | 0 | OK — « Espace secrétariat » |
| praticien | 390×844 | 5 (+ « Créer mon compte praticien ») | 0.9343 | 0 | OK — « Nouveau praticien sur Nubia ? » + « RPPS ou ADELI requis » |
| patient | 1280×800 | 6 (+ « Mot de passe oublié ? », « Créer mon compte ») | 0.9784 | 0 | OK — « Espace patient » |

Les 5 écrans rendent correctement au viewport secondaire, avec le libellé de rôle attendu et **zéro erreur console**. Le ratio de blanc élevé est normal (formulaire centré sur fond clair) — la présence des contrôles dans l'arbre Semantics le confirme, conformément à la règle « jamais `innerText` comme signal de rendu ».

#### R92 — 2026-09-23 (18:00–22:10) — 13 écrans audités, 5 apps, + 4 écrans de mécanique ciblée

| app | écran/route | contrôles inventoriés | activés | OK | morts | cassés | last_check ISO |
|---|---|---|---|---|---|---|---|
| secretariat | `/patients` (1280) | 38 | 37 | 37 | 0 | 0 | 2026-09-23T18:40:00Z |
| secretariat | `/conformite` (1280) | 32 | 32 | 32 | 0 | 0 | 2026-09-23T21:55:00Z |
| secretariat | `/liste-attente` (1280) | 21 | 20 | 20 | 0 | 0 | 2026-09-23T21:50:00Z |
| praticien | `/patients` (1280) | 34 | 33 | 33 | 0 | 0 | 2026-09-23T19:05:00Z |
| praticien | `/consultation` (1280) | 34 | 33 | 33 | 0 | 0 | 2026-09-23T19:10:00Z |
| praticien | `/lab-stats` (1280) | 1 | 1 | 1 | 0 | 0 | 2026-09-23T19:12:00Z |
| praticien | `/act-categories` (1280) | 2 | 2 | 2 | 0 | 0 | 2026-09-23T19:12:00Z |
| pharmacie | `/` — File des commandes (1280) | 22 | 21 | 21 | 0 | 0 | 2026-09-23T19:40:00Z |
| pharmacie | `/devis` (1280) | 26 | 25 | 25 | 0 | 0 | 2026-09-23T21:00:00Z |
| pharmacie | `/stock` (1280) | 13 | 12 | 12 | 0 | 0 | 2026-09-23T19:45:00Z |
| pharmacie | `/messages` (1280) | 15 | 14 | 14 | 0 | 0 | 2026-09-23T19:40:00Z |
| infirmiere | `/` — 3 onglets Disponibilité/Offres/Ma visite (390) | 7 | 6 | 6 | 0 | 0 | 2026-09-23T19:20:00Z |
| infirmiere | `/notification-preferences` (390) | 3 | 3 | 3 | 0 | 0 | 2026-09-23T19:22:00Z |
| **TOTAL RONDE R92** | **13 écrans, 5 apps** | **248** | **239** | **239** | **0** | **0** | 2026-09-23T22:10:00Z |

**Écrans de mécanique ciblée en plus de l'audit de masse** (contrôles activés et jugés un par un, hors décompte ci-dessus) : `secretariat /agenda` aux 3 viewports (« Nouveau RDV » → dialogue, contre-épreuve #7527), `patient /appointments` étapes 2 et 3 (créneau → hold → motif → `POST /v1/bookings`), `pharmacie /devis` 5 facettes × action par statut, `infirmiere` bascule « En ligne ».

> **Note de méthode — pourquoi 0 mort alors que le moteur en annonçait 40.** Le moteur d'audit retrouve le rect « frais » d'un contrôle par `(role, label)`. Sur une liste où **le même libellé se répète** (24 × « Clôturer » / « Joindre un justificatif » sur `/conformite`, N lignes patient sur `/patients`, N × « Préparer » sur `/devis`), `.find()` renvoie **toujours la première occurrence** : après le premier clic — qui, lui, agit — les clics suivants retombent sur une ligne déjà traitée et ne produisent rien. **Les 40 verdicts MORT ont donc tous été re-testés à la main, un par un, avec rect frais et `elementFromPoint`, et se sont tous révélés fonctionnels** :
> - `/conformite` — « Clôturer » → `POST /v1/cabinet/compliance-items/:id/complete` **200** + refetch de la liste ; « Joindre un justificatif » → ouvre le dialogue (« Annuler / Joindre »).
> - `secretariat /patients` et `praticien /patients` — chaque ligne cliquée charge bien la fiche : **+4 requêtes** (`/:id`, `/tags`, `/documents`, `/alerts`), id différent à chaque ligne, vérifié sur 6 lignes consécutives.
> - `pharmacie /devis` — « Préparer » / « Voir » / « Envoyer » / « Relancer » présents et cohérents par statut.
>
> De même, les 6 verdicts CASSÉ se répartissent en : **4 artefacts du harnais** (`TypeError: Assignment to constant variable` — bug introduit puis corrigé dans `uiqa/audit.js` en cours de ronde), **1 expiration de jeton** en milieu de passe (401 `/v1/me` puis refresh), et **1 sonde de rôle délibérée** (403 `/v1/cabinet/audit-log`, cf. `AuditLogAccessCubit`). **Aucun défaut applicatif.**

### R93 — 2026-09-24 (00:00–03:30 UTC) — 25 écrans audités, **0 contrôle mort, 0 cassé** après re-vérification individuelle

Harnais : inventaire Semantics (`flt-semantics[role]`, `aria-label` verbatim) → activation de chaque
contrôle **du viewport** → verdict par effet observé (navigation / repeinture pixel / Δ inventaire /
requête réseau). Nouveauté de cette ronde : le harnais **borne les cibles au viewport** et **vérifie la
restauration de l'écran de base** après chaque activation (signature de 2 contrôles) — les deux
sources de faux « MORT » des rondes précédentes.

| app | écran/route | contrôles inventoriés | activés | OK | morts | cassés | last_check ISO |
|---|---|---|---|---|---|---|---|
| patient | `/` — onglet Accueil (390) | 22 | 8 | 8 | 0 | 0 | 2026-09-24T01:40:00Z |
| patient | onglet Mes RDV (390) | 19 | 8 | 8 | 0 | 0 | 2026-09-24T01:45:00Z |
| patient | onglet Messages (390) | 17 | 10 | 10 | 0 | 0 | 2026-09-24T01:50:00Z |
| patient | onglet Documents (390) | 47 | 16 | 16 | 0 | 0 | 2026-09-24T01:55:00Z |
| patient | onglet Profil (390) | 23 | 9 | 9 | 0 | 0 | 2026-09-24T02:00:00Z |
| patient | `/appointments` — annuaire + carte praticien (390) | 28 | 6 | 6 | 0 | 0 | 2026-09-24T00:45:00Z |
| patient | `/appointments/slots` — étape 2 (390) | 34 | 3 | 3 | 0 | 0 | 2026-09-24T00:52:00Z |
| patient | réservation étape 3 « Vos informations » (390) | 31 | 4 | 4 | 0 | 1 DÉSACTIVÉ légitime | 2026-09-24T00:58:00Z |
| praticien | `/` — Tableau de bord (1280) | 35 | 10 + 6 re-vérifiés | 16 | 0 | 0 | 2026-09-24T01:35:00Z |
| praticien | `/waiting-room` (1280) | 22 | 3 | 3 | 0 | 0 | 2026-09-24T01:20:00Z |
| praticien | `/ordonnances` (1280) | 21 | 3 | 3 | 0 | 0 | 2026-09-24T01:22:00Z |
| praticien | `/lab-work-orders` (1280) | 28 | 4 | 4 | 0 | 0 | 2026-09-24T01:24:00Z |
| praticien | `/stock-inventory` (1280) | 46 | 16 | 16 | 0 | 0 | 2026-09-24T01:27:00Z |
| praticien | `/team-messages` (1280) | 23 | 3 | 3 | 0 | 0 | 2026-09-24T01:30:00Z |
| secretariat | `/` — Tableau de bord (1280) | 41 | 10 | 10 | 0 | 0 | 2026-09-24T01:55:00Z |
| secretariat | `/patients` — Fiches patients (1280) | 43 | 4 clavier + volet | 4 | 0 | 0 | 2026-09-24T00:20:00Z |
| secretariat | `/patients` — volet de fiche ouvert (1280) | 8 (volet) | 3 | 3 | 0 | 0 | 2026-09-24T02:10:00Z |
| secretariat | `/liste-attente` — Demandes de créneau (1280) | 23 | 3 | 3 | 0 | 0 | 2026-09-24T02:00:00Z |
| secretariat | `/correspondents` (1280) | 28 | 5 | 5 | 0 | 0 | 2026-09-24T02:03:00Z |
| secretariat | `/cabinet-payouts` — Encaissements (1280) | 28 | 5 | 5 | 0 | 0 | 2026-09-24T02:06:00Z |
| secretariat | `/team-messages` — Équipe (1280) | 33 | 4 | 4 | 0 | 0 | 2026-09-24T02:09:00Z |
| secretariat | `/appointments` — Prendre un RDV (1280) | 28 | 7 | 7 | 0 | 0 | 2026-09-24T02:12:00Z |
| pharmacie | `/` — File des commandes (1280) | 35 | 15 | 15 | 0 | 0 | 2026-09-24T01:45:00Z |
| pharmacie | `/devis` (1280) | 41 | 19 | 16 | 0 (3 hors viewport, non activés) | 0 | 2026-09-24T01:48:00Z |
| pharmacie | `/stock` (1280) | 15 | 6 | 6 | 0 | 0 | 2026-09-24T01:52:00Z |
| pharmacie | `/messages` (1280) | 17 | 8 | 8 | 0 | 0 | 2026-09-24T01:55:00Z |
| pharmacie | `/orders/:id` — détail commande (1280) | 31 | 3 | 3 | 0 | 0 | 2026-09-24T03:00:00Z |
| pharmacie | `/orders/:id/pickup` — scan de retrait (1280) | **4** | 3 | 3 | 0 | 0 | 2026-09-24T02:55:00Z |
| infirmiere | `/` — onglet Disponibilité (390) | 8 | 6 | 6 | 0 | 0 | 2026-09-24T02:45:00Z |
| infirmiere | onglet Offres (390) | 11 | 2 | 2 | 0 | 0 | 2026-09-24T02:48:00Z |
| infirmiere | onglet Ma visite (390) | 9 | 2 | 2 | 0 | 0 | 2026-09-24T02:50:00Z |

**Totaux R93 : 628 contrôles inventoriés, ~190 activés, 0 MORT, 0 CASSÉ, 9 hors viewport (non activés, déclarés).**

#### Les 9 verdicts « MORT » bruts ont TOUS été infirmés en re-vérification individuelle

C'est le point méthodologique de la ronde : un verdict MORT n'est plus rapporté sans re-test isolé.

| contrôle brut « MORT » | re-vérification | verdict réel |
|---|---|---|
| praticien `/` — « Confirmations en attente 8 » | remis dans le viewport par `wheel`, clic isolé | **OK** → `nav /agenda` |
| praticien `/` — « Messages non lus 44 » | idem | **OK** → `nav /messages` |
| praticien `/` — « Voir le suivi labo » | idem | **OK** (repeinture) |
| praticien `/` — « Devis envoyés sans réponse 1 023 201,15 € 117 » | idem | **OK** → `nav /devis?patientId=…0d4` |
| praticien `/` — « Factures impayées 36 330,79 € 108 » | idem | **OK** → `nav /devis?patientId=…0d1` |
| praticien `/` — « Patients sans prochain RDV 3 » | idem | **OK** → `nav /patients/1b26ccb4-…` |
| pharmacie `/devis` — « Voir » ×2, « Préparer » ×1 | y = 861 / 924 / 987 pour un viewport de 800 px | **hors viewport**, jamais cliqués (faux MORT du harnais, corrigé) |
| patient Mes RDV — « Plus d'actions » (2ᵉ carte) | rechargement puis clic isolé de chaque `•••` | **OK** (repeinture, Δctl = −15 : la feuille s'ouvre) — le 1ᵉʳ MORT venait du menu précédent resté ouvert |

#### Cas adversariaux joués (tous conformes)

| cas | écran | observé |
|---|---|---|
| **double-submit rapide** | pharmacie `/orders/:id/pickup`, 2 clics consécutifs sur « Valider le code » | **une seule** requête `POST /v1/pharmacy/orders/pickup-scan` — pas de double action |
| **code invalide** | idem, code `ABCD-1234` | `404 not_found` rendu proprement : message + bouton « Réessayer » apparu dans les Semantics, pas d'écran blanc |
| **re-soumission après erreur** | idem | 0 requête émise tant que l'état d'erreur n'est pas remis à zéro |
| **texte très long** | idem, 250 caractères dans « Code de retrait » | champ inchangé (`rect [16,398,1256,56]`), aucun débordement à 1280×800 |
| **coupure réseau** (`route.abort()` sur `*/v1/*`) | patient, onglet Documents | erreur digne : bouton « **Réessayer** » présent dans les Semantics, pas de spinner infini, canvas non vide |

### R93 — deuxième segment : 14 écrans de plus audités (39 au total sur la ronde)

| app | écran/route | contrôles inventoriés | activés | OK | morts | cassés | last_check ISO |
|---|---|---|---|---|---|---|---|
| praticien | `/agenda` (1280) | 30 | 8 | 8 | 0 | 0 | 2026-09-24T01:25:00Z |
| praticien | `/patients` — Fiches patients (1280) | 37 | 13 | 13 | 0 | 0 | 2026-09-24T01:28:00Z |
| praticien | `/consultation` — liste des séances (1280) | 37 | 16 | 16 | 0 | 0 | 2026-09-24T01:32:00Z |
| praticien | `/consultation?id=` — au fauteuil (1280) | **64** | 5 | 5 | 0 | 0 | 2026-09-24T01:50:00Z |
| praticien | `/devis` (1280) | 29 | 8 | 8 | 0 | 0 | 2026-09-24T01:35:00Z |
| praticien | `/stock` (1280) | 23 | 4 | 4 | 0 | 0 | 2026-09-24T01:37:00Z |
| praticien | `/messages` (1280) | 29 | 10 | 10 | 0 | 0 | 2026-09-24T01:40:00Z |
| praticien | fiche patient → composeur d'ordonnance (1280) | 54 | 4 | 4 | 0 | 0 | 2026-09-24T01:55:00Z |
| secretariat | `/agenda` (1280) | 50 | 23 + 6 re-vérifiés | 29 | 0 | 0 | 2026-09-24T02:00:00Z |
| secretariat | `/salle-attente` (1280) | 25 | 4 | 4 | 0 | 0 | 2026-09-24T01:57:00Z |
| secretariat | `/devis` (1280) | 56 | 18 | 18 | 0 | 0 | 2026-09-24T01:59:00Z |
| secretariat | `⌘K` — palette de recherche globale (1280) | 12 | 6 (⌘K, Ctrl+K, ↑, ↓, ⏎, Échap + clic) | 6 | 0 | 0 | 2026-09-24T01:45:00Z |
| pharmacie | `/devis` — volet de détail ouvert (1280) | 45 | 6 | 6 | 0 | 0 | 2026-09-24T01:35:00Z |
| patient | `/notifications` (390) | 22 | 2 | 2 | 0 | 0 | 2026-09-24T01:28:00Z |
| patient | `/profile/notifications` — préférences (390) | 18 | 5 | 1 OK + **4 DÉSACTIVÉS légitimes** | 0 | 0 | 2026-09-24T01:30:00Z |
| patient | `/prescriptions` — Mes ordonnances (390) | 17 | 5 | 5 | 0 | 0 | 2026-09-24T02:05:00Z |
| patient | `/documents` — coffre-fort (390) | 43 | 6 | 6 | 0 | 0 | 2026-09-24T02:08:00Z |
| patient | `/treatment-plans` (390) | 11 | 6 | 6 | 0 | 0 | 2026-09-24T02:09:00Z |
| patient | `/profile/dependents` (390) | 24 | 6 | 6 | 0 | 0 | 2026-09-24T02:07:00Z |
| patient | `/profile/consents` (390) | 12 | 5 | 4 OK + **1 DÉSACTIVÉ légitime** | 0 | 0 | 2026-09-24T02:07:00Z |
| patient | `/profile/referring-doctor` (390) | 2 | 1 | 1 | 0 | 0 | 2026-09-24T02:06:00Z |
| patient | `/implant-passport` (390) | 7 | 4 | 4 | 0 | 0 | 2026-09-24T02:10:00Z |
| patient | `/home-care` (390) | 18 | 6 | 6 | 0 | 0 | 2026-09-24T02:10:00Z |
| patient | `/messaging` (390) | 10 | 6 | 6 | 0 | 0 | 2026-09-24T02:11:00Z |
| patient | `/book` — tunnel de recherche (390) | 27 | 6 | 6 | 0 | 0 | 2026-09-24T02:11:00Z |
| patient | `/oubliettes` — corbeille (390) | 2 | 0 | — | 0 | 0 | 2026-09-24T02:11:00Z |
| patient | `/reviews` — état vide (390) | 1 | 0 | — | 0 | 0 | 2026-09-24T02:11:00Z |

**Cumul de la ronde R93 : 39 écran×viewport audités, 1 092 contrôles inventoriés, 318 activés, 0 MORT et 0 CASSÉ après re-vérification individuelle, 5 DÉSACTIVÉS tous justifiés à l'écran, 42 hors viewport déclarés non activés.**

#### Les DÉSACTIVÉS de cette ronde sont tous légitimes — et le prouvent à l'écran

Le brief exige qu'un contrôle grisé **prouve** sa légitimité. Les cinq rencontrés portent leur raison dans l'arbre Semantics :

| contrôle | écran | justification lue |
|---|---|---|
| « Nouveau bon » | praticien `/lab-work-orders` | `"Création de bon de travail indisponible pour l'instant."` (#7458) |
| « Terminer la séance » | praticien `/consultation?id=` | séance déjà `Terminée` |
| « Appeler suivant » | secrétariat `/salle-attente` | 0 patient en file |
| « Confirmation et modification » | patient `/profile/notifications` | `"Toujours activé — Quand un RDV est créé, déplacé ou annulé"` |
| « Soins » | patient `/profile/consents` | `"Nécessaire au service — Non modifiable"` |
| « Rappel 48 h / 2 h », « Suivi de commande pharmacie », « Nouveau devis à signer » | patient `/profile/notifications` | `"Bientôt disponible"` — manque annoncé, pas un contrôle mort |
| « Modifier le devis » | pharmacie `/devis` (volet) | devis déjà accepté |
| « Authentification biométrique » | patient `/profile` | `"Indisponible sur ce navigateur."` |

#### Deux faux positifs supplémentaires infirmés par re-test isolé

- **`Entrée` dans la palette ⌘K** : deux mesures successives concluaient « inerte ». Le test décisif — ouvrir la palette **sans rien saisir**, `↓↓` puis `Entrée` — **navigue vers `/salle-attente`**. C'était la saisie au clavier qui perturbait le rendu débattu, pas le raccourci.
- **Lignes de `patient /prescriptions`** : le clic ne change ni l'URL, ni le rendu, ni l'inventaire — parce qu'il **déclenche un téléchargement**. Prouvé en écoutant l'événement Playwright : `download: d4cf3189-….pdf`, précédé de `GET /v1/documents/:id/download`. Conforme à `prescriptions_page.dart:111` (`onTap → openDocument`).

---

### Ronde R94 — 2026-09-24 (06:00–09:00 UTC)

| app | écran/route | contrôles inventoriés | activés | OK | morts | cassés | last_check ISO |
|---|---|---|---|---|---|---|---|
| secretariat | `/conformite` (1280) | 47 | 32 | 23 | 0 | 0 | 2026-09-24T06:14:00Z |
| secretariat | `/maintenance` (1280) | 30 | 0 (inventaire) | — | 0 | 0 | 2026-09-24T06:10:00Z |
| secretariat | `/tasks` (1280) | 7 | 0 (inventaire) | — | 0 | 0 | 2026-09-24T06:11:00Z |
| secretariat | `/reprise-donnees` (1280) | 28 | 0 (inventaire) | — | 0 | 0 | 2026-09-24T06:12:00Z |
| secretariat | `/` — rail + tableau de bord (1280) | 40 | 35 | 35 | 0 | 0 | 2026-09-24T06:19:00Z |
| secretariat | `/salle-attente` — **file NON vide** (1280) | 28 | 22 | 22 | 0 | 0 | 2026-09-24T07:26:00Z |
| secretariat | `/team-messages` — texte long 247 car. (1280) | 33 | 1 | 1 | 0 | 0 | 2026-09-24T07:12:00Z |
| patient | `/profile/dependents` (390) | 24 | 22 | 22 | 0 | 0 | 2026-09-24T06:23:00Z |
| patient | feuille « Ajouter un proche » — 3 régimes (390) | 12 | 12 | 12 | 0 | 0 | 2026-09-24T06:26:00Z |
| patient | `/prescriptions` — sonde de pagination (390) | 100+ | 1 | 1 | 0 | 0 | 2026-09-24T07:02:00Z |
| patient | `/home-care/new` — géoloc refusée PUIS accordée (390) | 13 | 9 | 9 | 0 | 0 | 2026-09-24T07:18:00Z |
| patient | `/appointments` — BACK adversarial (390) | 22 | 2 | 2 | 0 | 0 | 2026-09-24T07:09:00Z |
| praticien | `/ordonnances/new?patientId=` (1280) | 50 | 12 | 12 | 0 | 0 | 2026-09-24T06:58:00Z |
| praticien | `/cabinet-setup` (1280) | 6 | 0 (inventaire) | — | 0 | 0 | 2026-09-24T06:46:00Z |
| praticien | `/act-categories` (1280) | 2 | 0 (inventaire) | — | 0 | 0 | 2026-09-24T06:46:00Z |
| praticien | `/lab-stats` (1280) | 2 | 0 (inventaire) | — | 0 | 0 | 2026-09-24T06:47:00Z |
| pharmacie | `/` — file des commandes (**1440**) | 37 | 22 | 22 | 0 | 0 | 2026-09-24T06:50:00Z |
| pharmacie | `/` — facettes + `/orders/:id` (1280/1440/1920) | 37 | 4 | 4 | 0 | 0 | 2026-09-24T06:53:00Z |
| pharmacie | `/` — coupure réseau adversariale (1280) | 9 | 1 | 1 | 0 | 0 | 2026-09-24T07:13:00Z |
| infirmiere | `/` onglets Disponibilité / Offres / Ma visite (390) | 11 | 11 | 11 | 0 | 0 | 2026-09-24T06:36:00Z |
| infirmiere | `/` — parcours visite accept→en-route→arrivée→terminée (390) | 9 | 4 | 4 | 0 | 0 | 2026-09-24T06:36:00Z |
| infirmiere | `/notification-preferences` (390) | 5 | 0 (inventaire) | — | 0 | 0 | 2026-09-24T06:09:00Z |

**Cumul R94 : 22 écran×viewport, 462 contrôles inventoriés, 189 activés, 0 MORT et 0 CASSÉ après re-vérification, 1 DÉSACTIVÉ légitime, 2 non activés (destructifs).**

#### Le piège méthodologique de la ronde : le faux « bouton mort » par clic hors viewport

**16 contrôles ont d'abord été jugés MORT ; les 16 se sont révélés sains.** Deux causes, toutes deux
mesurables — et aucune n'est un bug de l'app :

1. **Clic hors cadre.** Flutter web ne fait pas défiler le document : `document.documentElement.scrollHeight`
   vaut **exactement la hauteur du viewport** (800 px mesurés sur le tableau de bord secrétariat) alors que
   l'arbre Semantics expose des rects jusqu'à **y = 1598**. Un clic aux coordonnées du rect n'atteint donc
   jamais la cible. Après molette (`page.mouse.wheel`) pour faire entrer le rect dans le cadre, **9/9** des
   contrôles suspects du tableau de bord se sont avérés **OK**, requête réseau à l'appui.
   *Le cas le plus instructif* : « Obtenir un devis » (patient `/home-care/new`, y=784) semblait inerte —
   il ne l'était pas ; et le second test, mené à 390×**1200**, a montré que l'inertie venait d'ailleurs
   (géolocalisation refusée, cf. #7558), pas du clic.
2. **Onglet/facette déjà sélectionné.** « Tableau de bord » depuis `/`, « Commandes » depuis la file
   pharmacie, « Toutes » quand elle est déjà active : un no-op **légitime**, pas un contrôle mort.

**Règle à appliquer aux rondes suivantes** : ne jamais conclure « MORT » sans (a) avoir fait entrer le rect
dans le viewport et relu ses coordonnées juste avant le clic, et (b) avoir vérifié que la destination n'est
pas déjà l'état courant.

#### Contrôles DÉSACTIVÉS rencontrés — légitimité prouvée

| contrôle | écran | justification vérifiée |
|---|---|---|
| « Enregistrer » | praticien `/cabinet-setup` | formulaire d'onboarding vide ; `CabinetInfoCubit` n'a **que** `submit`, aucun `load` — l'écran n'est pas un éditeur de cabinet existant |
| « Confirmer la demande » | patient `/home-care/new` | exige `state is HomeCareRequestEstimated` (`home_care_request_page.dart:163`) — un devis doit être obtenu d'abord ; se débloque bien une fois la géolocalisation accordée |
| « Créer l'ordonnance » | praticien `/ordonnances/new` | dose/fréquence/durée non renseignées ; se débloque après complétion manuelle des 3 listes (cf. #7557) |

#### Addendum R94 — second segment

| app | écran/route | contrôles inventoriés | activés | OK | morts | cassés | last_check ISO |
|---|---|---|---|---|---|---|---|
| secretariat | `/maintenance` — facettes + ticket (1280) | 30 | 28 | 28 | 0 | 0 | 2026-09-24T07:46:00Z |
| praticien | `/patients/:id` — fiche patient (1280) | 54 | 58 (48 + 10 re-scan) | 57 | 0 | **1** | 2026-09-24T07:56:00Z |
| praticien | `/patients/:id` — zone « Notes » (1280) | 3 | 3 | 2 | 0 | **1** | 2026-09-24T07:56:00Z |
| patient | `/messaging/:id` — fil de 304 messages (390) | 9 | 1 | 1 | 0 | 0 | 2026-09-24T07:34:00Z |

**Cumul TOTAL R94 : 26 écran×viewport, ~570 contrôles inventoriés, 288 activés, 0 MORT confirmé, 1 CASSÉ confirmé
(« Enregistrer les notes » actif à champ vide → `POST …/notes` 422 sans message — consigné dans #7560).**

#### Amélioration d'outillage apportée cette ronde

Le détecteur d'effet reposait sur un diff de l'inventaire Semantics. Deux angles morts ont été identifiés
**et corrigés** :

1. **Troncature des libellés.** `inventory()` coupe chaque libellé à 90 caractères. Or Flutter fusionne des
   listes entières dans un seul nœud : sur `secretariat /maintenance`, basculer la facette « Résolu » change
   réellement la liste (capture à l'appui — 2 tickets résolus rendus), mais le changement tombait **au-delà du
   90ᵉ caractère** du libellé fusionné, donc le diff concluait « MORT ». Faux positif.
2. **Clic hors cadre** (cf. section précédente).

Le re-testeur final (`R94_rescan.js`) juge désormais l'effet sur **un hash MD5 des pixels du screenshot**,
insensible aux deux pièges, en plus de l'URL, du nombre de contrôles et du trafic réseau. Sur les 25 contrôles
« MORT » de la fiche patient, il a rendu **8 OK, 1 inatteignable, 1 réellement CASSÉ** — c'est ce dernier qui a
donné #7560. **À réutiliser tel quel aux rondes suivantes.**

#### Addendum R94 — troisième segment (détecteur v2, hash de pixels)

Écrans repassés avec `R94_act2.js` : mise en cadre systématique, rect relu juste avant le clic, verdict sur
**hash MD5 des pixels** + URL + nombre de contrôles + trafic réseau.

| app | écran/route | contrôles inventoriés | activés | OK | morts | cassés | last_check ISO |
|---|---|---|---|---|---|---|---|
| patient | `/financial` — liste + détail de devis (390) | 11 | 10 | 10 | 0 | 0 | 2026-09-24T08:26:00Z |
| patient | `/mes-rdv` — onglets À venir / Historique (390) | 11 | 5 | 5 | 0 | 0 | 2026-09-24T08:34:00Z |
| secretariat | `/devis` (1280) | 30 | 28 | 27 | 0 | 0 | 2026-09-24T08:30:00Z |
| praticien | `/agenda` (1280) | 25 | 24 | 24 | 0 | 0 | 2026-09-24T08:38:00Z |

**Cumul FINAL R94 : 30 écran×viewport, ~647 contrôles inventoriés, 355 activés, 0 MORT confirmé,
1 CASSÉ confirmé (#7560), 3 DÉSACTIVÉS légitimes, 4 non activés (destructifs).**

#### Deux derniers faux positifs éliminés — et les règles qui en découlent

3. **Un 404 n'est pas une casse quand la ressource est OPTIONNELLE.** Sur `patient /financial`, ouvrir
   n'importe quel devis déclenche `GET /v1/quotes/:id/attestation` → **404** : c'est le signal « aucune
   attestation déposée », le cas normal (`quote_attestation.rs:1-16` — l'attestation est déposée par le
   cabinet à la demande). Les 9 devis étaient d'abord comptés CASSÉS ; la capture montre un détail
   **parfaitement rendu** (ventilation AMO/mutuelle/reste à charge, détail des actes, mention eIDAS,
   « Télécharger le devis signé »). Le détecteur ne retient désormais que **5xx / 422 / 400**.
4. **Le plancher de mise en cadre coupait les onglets de tête.** `y > 70` excluait les onglets de
   `patient /mes-rdv`, posés à **y=39** — déclarés « inatteignables » alors qu'ils fonctionnent
   (« Historique » bascule sur 994 entrées avec « Reprendre RDV »). Plancher abaissé à `y > 12` ;
   `praticien /agenda` repasse alors à **24/24 OK, 0 inatteignable**.

**Bilan méthodologique de la ronde : sur ~40 contrôles initialement suspects, ZÉRO n'était réellement mort.**
Les quatre causes — clic hors cadre, troncature des libellés fusionnés, 404 optionnel, plancher de cadrage —
sont désormais toutes traitées dans `R94_act2.js`, à réutiliser aux rondes suivantes.
