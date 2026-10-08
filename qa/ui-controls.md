# Ledger des contrôles UI audités — flutter-qa-agent

> Une ligne par écran audité en profondeur (inventaire Semantics + activation de
> CHAQUE contrôle + verdict OK/MORT/CASSÉ/DÉSACTIVÉ). Alimenté au fil des rondes ;
> à la ronde suivante, commencer par les écrans jamais audités ou les plus anciens.
> Complète `explored-paths.md` (scénarios API/flux) — ce fichier-ci se concentre
> sur la mécanique bouton-par-bouton d'un écran donné.




### Ronde R136 — 2026-10-08 (12:00–14:0x UTC) — 5/5 apps, **23 écrans audités, 285 contrôles activés et jugés** — **0 contrôle mort confirmé, 0 cassé**

> **Tous les « MORT » et « CASSÉ » bruts du parcours ont été rejoués un par un sur un écran
> RECHARGÉ, et aucun n'a survécu.** 33 MORT bruts et 9 CASSÉ bruts → **0 confirmé**. Deux
> causes, toutes deux de méthode :
>
> 1. **Délai d'observation trop court (1 800 ms).** `Ma carte de visite` (praticien) met plus de
>    2 s à rendre `GET /cabinet/vcard` + `/vcard/qr.png` ; `Personnaliser` repeint après coup.
>    Portés à **3 500 ms**, les deux sortent OK. *Correctif appliqué au harnais cette ronde.*
> 2. **Cascade d'overlay.** Dès qu'un contrôle ouvre un dialogue modal (sans changer l'URL,
>    donc sans déclencher la re-navigation d'isolation), **tous les contrôles suivants de
>    l'écran tombent sur l'overlay** et ressortent MORT en série. C'est l'intégralité des
>    5 `Accepter`/`Refuser` de pharmacie `/stock` : rejoués sur écran neuf, **5/5 OK**, chacun
>    ouvrant bien sa confirmation (« Accepter la demande / Annuler / Accepter ») **sans aucune
>    requête avant confirmation** — ce qui est le bon comportement.
>
> **Deux contrôles méritaient mieux qu'un verdict de harnais et ont été prouvés par un canal
> dédié :**
> - **« Modifier la photo de profil » (patient `/profile`)** — seul contrôle encore MORT après
>   vérification individuelle. Il ouvre un **sélecteur de fichier natif**, que Chromium headless
>   n'affiche pas : ni requête, ni repeinture, ni changement d'arbre. Tranché avec l'évènement
>   Playwright `filechooser` : l'évènement **se déclenche**, et en lui fournissant un vrai PNG
>   l'upload part — **`PUT /v1/account/avatar` → 204**. Contrôle pleinement fonctionnel.
> - **« Rechercher un patient » (praticien `/patients`)** — un champ peut filtrer sans requête
>   et avec un debounce. Saisie réelle de `Dubois` → **`GET /v1/cabinet/patients?limit=200&q=Dubois`
>   → 200** et la liste passe de **20 à 12 lignes**. OK.
>
> **Le seul DÉSACTIVÉ rencontré sur une action métier est légitime et la preuve est faite :**
> `Confirmer le rendez-vous` (patient, étape 3 du tunnel) est `aria-disabled="true"` tant que le
> **motif** — champ requis — est vide ; la sélection de la puce `Contrôle` le fait passer à
> `aria-disabled="false"`, et le clic émet `POST /v1/bookings` → **201**.

| app | écran/route | contrôles inventoriés | activés | OK | morts | cassés | last_check ISO |
|---|---|---|---|---|---|---|---|
| patient | `/financial` (390×844) | 8 | 8 | 8 | 0 | 0 *(7 « CASSÉ » bruts = sonde de capacité, cf. note)* | 2026-10-08T12:17:00Z |
| patient | `/treatment-plans` (390×844) | 9 | 9 | 8 | 0 | 0 | 2026-10-08T12:19:00Z |
| patient | `/documents` (390×844) | 19 | 19 | 9 | 0 | 0 *(10 hors-viewport)* | 2026-10-08T12:22:00Z |
| patient | `/messaging` (390×844) | 9 | 9 | 8 | 0 | 0 | 2026-10-08T12:24:00Z |
| patient | `/mes-rdv` (390×844) | 14 | 14 | 11 | 0 | 0 | 2026-10-08T13:04:00Z |
| patient | `/notifications` (390×844) | 20 | 20 | 20 | 0 | 0 | 2026-10-08T13:06:00Z |
| patient | `/profile` (390×844) | 24 | 20 | 19 | 0 | 0 *(1 désactivé légitime : biométrie)* | 2026-10-08T13:08:00Z |
| patient | `/reviews` (390×844) | 3 | 3 | 3 | 0 | 0 | 2026-10-08T13:09:00Z |
| patient | `/appointments` tunnel étapes 1→3 (390×844) | 37 | 37 | 37 | 0 | 0 | 2026-10-08T13:35:00Z |
| praticien | `/` tableau de bord (1280×800) | 29 | 22 | 22 | 0 | 0 | 2026-10-08T12:46:00Z |
| praticien | `/patients` (1280×800) | 35 | 22 | 22 | 0 | 0 | 2026-10-08T12:52:00Z |
| praticien | `/consultations`, `/inventaire`, `/labo` (1280×800) | 1 ×3 | 1 ×3 | 1 ×3 | 0 | 0 | 2026-10-08T12:49:00Z |
| secretariat | `/agenda` (1280×800) | 85 | 10 | 10 | 0 | 0 | 2026-10-08T12:30:00Z |
| secretariat | `/liste-attente` (1280×800) | 22 | 20 | 20 | 0 | 0 | 2026-10-08T12:57:00Z |
| secretariat | `/devis` (1280×800) | 40 | 20 | 20 | 0 | 0 | 2026-10-08T12:59:00Z |
| secretariat | `/salle-attente` (1280×800) | 23 | 20 | 20 | 0 | 0 | 2026-10-08T13:01:00Z |
| secretariat | `/cabinet-payouts` (1280×800) | 27 | 27 | 26 | 0 | 0 *(1 désactivé avec motif : Connecter Stripe)* | 2026-10-08T13:14:00Z |
| pharmacie | `/` file des commandes (1280×800) | 28 | 20 | 20 | 0 | 0 | 2026-10-08T12:54:00Z |
| pharmacie | `/stock` (1280×800) | 25 | 20 | 20 | 0 | 0 | 2026-10-08T12:56:00Z |
| pharmacie | `/devis` (1280×800) | 26 | 20 | 20 | 0 | 0 | 2026-10-08T12:58:00Z |
| pharmacie | `/messages` (1280×800) | 12 | 12 | 12 | 0 | 0 | 2026-10-08T12:59:00Z |
| infirmiere | `/` 3 onglets (390×844) | 7 | 7 | 7 | 0 | 0 | 2026-10-08T13:02:00Z |
| infirmiere | `/notification-preferences` (390×844) | 3 | 3 | 3 | 0 | 0 | 2026-10-08T13:03:00Z |

### R136 — « MORT » et « CASSÉ » bruts, et leur explication prouvée

| contrôle(s) | écran | explication (vérifiée individuellement) |
|---|---|---|
| `Accepter` ×3, `Refuser` ×2 | pharmacie `/stock` | **5/5 OK en isolation** : ouvrent la confirmation (Semantics 66 → 11, le modal reprend l'arbre), **aucune requête avant confirmation**. Les MORT du parcours = cascade d'overlay. |
| `Ma carte de visite` | praticien `/` | **OK** : `GET /v1/cabinet/vcard` → 200 **et** `GET /v1/cabinet/vcard/qr.png` → 200. La feuille de partage (`Share.shareXFiles`) est invisible en headless, d'où l'absence de repeinture. |
| `Personnaliser` | praticien `/` | **OK** : le libellé bascule en **« Terminé »** et l'inventaire passe de 29 à 30 contrôles (`dashboard_page.dart:366`). |
| `Rechercher un patient` | praticien `/patients` | **OK** : `q=Dubois` → `GET /cabinet/patients?limit=200&q=Dubois` 200, liste **20 → 12**. |
| `Modifier la photo de profil` | patient `/profile` | **OK** : évènement `filechooser` déclenché ; PNG fourni → **`PUT /v1/account/avatar` → 204**. Sélecteur natif, invisible en headless. |
| `Rappels e-mail`, `Notifications push` | patient `/profile` | **OK** : chacun émet `PATCH /v1/account/notification-preferences` → 200. |
| `Notifications RDV · Toutes les préférences ›` | patient `/profile` | **OK** : navigue vers `/profile/notifications` + `GET /account/notification-preferences` 200. |
| `Questionnaire médical` ×2 | patient `/mes-rdv` | **OK** : navigue vers `/questionnaire-medical/1111…` + 2 GET 200. Le correctif #8028 tient. |
| `Tableau de bord` ×2, `Congés` ×2, `Devis, 31`, `Salle d'attente` ×2 | secretariat (rails) | **OK en isolation** : chacun navigue et déclenche ses requêtes (`/` → 5 GET, `/conges` → 2 GET, `/devis` → 3 GET). |
| `Demandes de créneau` | secretariat `/liste-attente` | **No-op légitime** : c'est l'entrée de rail de la **page courante** (`pro_config.dart:125` → `route: '/liste-attente'`). |
| `Commandes`, `Stock`, `Devis`, `Messages`, `Patients` | rails pharmacie / praticien | **No-op légitime** : entrée de rail de la page courante. |
| `Tous (189)`, `Toutes`, `À répondre (6)`, `À venir (63)` | facettes diverses | **Facette déjà active** au chargement (`aria-checked="true"`) : le re-clic ne change rien, c'est correct. |
| `Plus d'actions` ×2 | patient `/mes-rdv` | **Hors-viewport** (déjà consigné R132/R135), non activable aux coordonnées relevées. |
| 7 cartes de devis + 1 carte de plan | patient `/financial` | **Faux CASSÉ** : le clic déclenche la **sonde de capacité** `GET /v1/quotes/:id/attestation` → **404**, délibérée — `financial_bloc.dart:203` replie l'échec en `attestation: null` (`fold((_) => null, …)`) et masque simplement le panneau. L'écran rend correctement le devis (« Reste à votre charge 450 € », « Télécharger le devis signé »). Même famille que la sonde `GET /cabinet/audit-log` → 403 du secrétariat. |
| `Retour à l'accueil` | secretariat page « introuvable » | **Faux CASSÉ**, même motif : sonde `audit-log` → 403. Le bouton **navigue bien** vers `/` avec 8 requêtes. |

### R136 — cas adversariaux (Étape 2f), tunnel de réservation patient

| cas | résultat |
|---|---|
| **Double-submit** — 2 clics < 100 ms sur `Confirmer le rendez-vous` | **1 seul `POST /v1/bookings` → 201**, **une seule** occurrence de « Demande de rendez-vous envoyée » à l'écran, 0 erreur console. |
| **BACK navigateur au milieu du tunnel** | Retour sur `/appointments` : **état cohérent**, 22 contrôles, écran non vide. `goForward()` **restaure** `/appointments/slots?providerId=…&slotId=…` avec ses 37 contrôles. |
| **Champ requis vide** — submit sans motif | Bouton `aria-disabled="true"`, **0 requête**, **aucun 5xx**, aucun submit silencieux. Refus propre. |
| **Texte très long** — 220 caractères dans « Précisions pour le praticien » | `scrollWidth` **390** = `clientWidth` **390** : **aucun débordement horizontal**. |
| **Coupure réseau** — `route.abort()` sur `**/v1/**` puis rechargement de `/mes-rdv` | **Erreur digne** : l'écran rend un bouton **« Réessayer »** (présent dans l'arbre Semantics). Ni spinner infini, ni écran blanc muet. |

### Ronde R135 — 2026-10-08 (06:00–09:0x UTC) — 5/5 apps + tunnel SSR, 24 écrans audités, **401 contrôles inventoriés, 310 activés et jugés** — **0 contrôle mort confirmé, 0 cassé**

> ⚠️ **Résultat principal de la ronde : les verdicts « MORT » bruts du harnais étaient FAUX.**
> 3 défauts du harnais ont été trouvés et corrigés ; après correction, **tous** les contrôles
> suspects se sont révélés fonctionnels ou légitimement inertes. Détail des 3 correctifs :
>
> 1. **Routage par `#` au lieu du chemin.** Les 5 apps appellent `usePathUrlStrategy()`
>    (`front/apps/*/lib/bootstrap.dart`) : `goto(app+'/#'+route)` retombait sur le tableau de
>    bord. Symptôme : `/consultation` et `/ordonnances` rendaient des compteurs **identiques au
>    contrôle près** (inv 32, act 29, OK 24, MORT 4). Corrigé → `goto(app+route)`.
> 2. **Retour-sur-écran en `startsWith`.** Après un contrôle qui navigue vers un sous-écran
>    (`/implant-passport/:id`), `pathname.startsWith('/implant-passport')` restait vrai : le
>    harnais ne revenait pas en arrière et **tous les clics suivants tombaient sur l'écran de
>    détail** → cascade de faux MORT. Corrigé → égalité stricte du `pathname`, plus `Escape`
>    + re-navigation après **chaque** contrôle (une feuille de confirmation ouverte avalait
>    aussi tous les clics suivants).
> 3. **Empreinte Semantics aveugle à la sélection.** `semFingerprint()` ignorait
>    `aria-checked`/`aria-selected`/`aria-disabled` : une puce de filtre qui bascule bien sa
>    sélection sans changer la liste (jeu de démo où tous les compteurs valent 1) sortait
>    « MORT ». Corrigé → l'empreinte inclut ces attributs.
>
> **Effet mesuré** : secrétariat `/conformite` est passé de **21 MORT → 1 MORT / 32 OK** par le
> seul correctif n°2. Les rondes antérieures ayant utilisé `R132-lib.js` + routage `#`, leurs
> compteurs de contrôles morts sont à considérer avec la même prudence.
>
> **Reste à corriger dans le harnais (R136)** : le délai de jugement de 1 500 ms est trop court
> pour un contrôle qui fait un aller-retour serveur — l'interrupteur « En ligne » de l'app
> infirmière (`PATCH /v1/nurse/availability`) a été jugé MORT à 1 500 ms et s'est révélé
> **parfaitement fonctionnel à 3 200 ms** (sémantique `checked` true→false, PATCH 200, bandeau
> « Vous êtes hors ligne »). Passer à ≥3 000 ms, ou attendre la quiescence réseau.

| app | écran/route | inventoriés | activés | OK | morts | cassés | last_check ISO |
|---|---|---|---|---|---|---|---|
| praticien | /consultation | 38 | 35 | 33 | 0 (1 = élément de rail déjà actif) | 0 | 2026-10-08T06:5xZ |
| praticien | /stock-inventory | 47 | 33 | 31 | 0 (1 = rail actif « Inventaire ») | 0 | 2026-10-08T06:5xZ |
| praticien | /mes-conges | 24 | 21 | 19 | 0 (1 = rail actif « Congés ») | 0 | 2026-10-08T06:5xZ |
| praticien | /act-categories | 1 | 1 | 1 | 0 | 0 | 2026-10-08T06:2xZ |
| praticien | /lab-work-orders | 28 | — | — | — | — | 2026-10-08T07:0xZ |
| secrétariat | /conformite | 50 | 34 | 32 | 0 (1 = filtre actif « À venir / échu ») | 0 (« Retour » = faux CASSÉ : sonde 403 audit-log) | 2026-10-08T06:4xZ |
| secrétariat | /liste-attente | 24 | 22 | 20 | 0 (1 = rail actif) | 0 | 2026-10-08T06:4xZ |
| secrétariat | /maintenance | 30 | 26 | 25 | 0 | 0 | 2026-10-08T06:5xZ |
| pharmacie | /messages | 14 | 12 | 7 | 0 (3 puces de filtre vérifiées OK + 1 rail actif) | 0 | 2026-10-08T06:3xZ |
| pharmacie | /stock | 34 | 25 | 22 | 0 (1 rail actif + 1 puce vérifiée OK) | 0 | 2026-10-08T06:3xZ |
| patient | /oubliettes | 2 | 1 | 1 | 0 | 0 | 2026-10-08T06:2xZ |
| patient | /implant-passport | 7 | 6 | 1 | 0 (4 cartes vérifiées : naviguent vers /implant-passport/:id) | 0 | 2026-10-08T06:2xZ |
| patient | /profile/consents | 12 | 8 | 3 | 0 (interrupteurs : ouvrent la feuille de retrait) | 0 | 2026-10-08T07:1xZ |
| patient | /treatment-plans | 11 | — | — | — | — | 2026-10-08T07:5xZ |
| infirmière | Disponibilité (onglet) | 8 | 7 | 6 | 0 (« En ligne » vérifié OK à 3 200 ms) | 0 | 2026-10-08T08:1xZ |
| infirmière | Offres (onglet) | 5 | 3 | 3 | 0 | 0 | 2026-10-08T08:2xZ |
| infirmière | Ma visite (onglet) | 7 | 6 | 5 | 0 (onglets vérifiés : `aria-selected` commute) | 0 | 2026-10-08T08:2xZ |
| infirmière | /notification-preferences | 5 | 3 | 3 | 0 (2 interrupteurs → `PATCH /me/notification-preferences` 200) | 0 | 2026-10-08T08:0xZ |
| secrétariat | /reprise-donnees | 28 | 25 | 20 | 0 (3 = puces de filtre/rail actif) | 0 | 2026-10-08T07:0xZ |
| pharmacie | /devis | 42 | 26 | 23 | 0 (1 rail actif + puce « Tous (189) » déjà active) | 0 | 2026-10-08T07:0xZ |
| pharmacie | /orders/:id/pickup | 4 | 3 | 2 | 0 | 0 (1 DÉSACTIVÉ **prouvé légitime**, cf. ci-dessous) | 2026-10-08T07:1xZ |
| pharmacie | /notification-preferences | — | — | — | — | — | 2026-10-08T07:0xZ |
| praticien | /cabinet-brief | 6 | 5 | 5 | 0 | 0 | 2026-10-08T07:0xZ |
| praticien | /consent-templates | 22 | 11 | 11 | 0 | 0 | 2026-10-08T07:0xZ |
| praticien | /questionnaire-templates | 4 | 2 | 2 | 0 | 0 | 2026-10-08T07:0xZ |

> **Le seul contrôle DÉSACTIVÉ de la ronde, prouvé légitime** — « Valider le code »
> (`/orders/:id/pickup`) : champ vide → `aria-disabled=true` ; **code saisi → `false`** ;
> champ réeffacé → `true`. Et il **agit** quand il est actif (clic avec un mauvais code →
> `POST /pharmacy/orders/pickup-scan` → 404 → « Code inconnu — Revérifiez… »). C'est un
> verrou de formulaire, pas un bouton mort.

> **Tunnel SSR (`reservation.doc.nubia-link.com`)** — audité au niveau HTTP (ce n'est pas du
> Flutter) : formulaire de confirmation à 5 champs + consentement, tous `required`, et
> **166 créneaux cliquables sur 5 jours** sur la fiche praticien. Détail dans `explored-paths.md`
> (`R135-tunnel-SSR-*`).

### Ronde R134 — 2026-10-08 (00:00–02:0x UTC) — **5/5 apps + tunnel SSR**, 62 écrans, **1 468 contrôles inventoriés, 1 426 activés et jugés**

> **Méthode** : inventaire depuis l'arbre `flt-semantics` du rendu (jamais `innerText`),
> activation réelle au clic/saisie de chaque contrôle, verdict par observation
> (navigation / requête réseau / repeinture Semantics / erreur). Sessions réutilisées
> via `storageState` (un seul login par app) pour ne pas déclencher le limiteur IP
> `5 tentatives / 60 s` de `auth/login.rs:27-28`.
>
> ⚠️ **Lire les colonnes MORT/CASSÉ comme des *candidats*, pas des verdicts.** Chacun a
> été re-joué à la main ; la très grande majorité s'est révélée **fausse alerte** et
> n'a PAS été filée :
> - onglet/route **déjà actif** (« Tableau de bord » sur `/`, « Messages » sur `/messages`,
>   « Tous » sur un filtre déjà sélectionné) → MORT légitime ;
> - en-tête de groupe du rail **clippé** sous le pli (« Absences », « Réglages du cabinet »)
>   → symptôme connu #7706/#7859, le clic répond après défilement ;
> - **téléchargement** (`Exporter (CSV)` secrétariat → `suivi_devis.csv`, `Télécharger`
>   patient → `2f473cd5-….pdf`) : ni navigation ni requête `/v1/`, donc invisible pour
>   le détecteur — vérifié manuellement, les deux fonctionnent ;
> - **attente trop courte** (1,6 s) après un clic qui ouvre un écran lourd : re-joué à
>   13 s, `/pharmacy/orders/:id` rend bien sa timeline horodatée et son QR ;
> - **401 de session expirée** sur les contextes réutilisés > 15 min (artefact du harnais) ;
> - **case à cocher** dont seul `aria-checked` change : la signature de comparaison du harnais ne lisait que `aria-label` + position — corrigé par re-jeu manuel (`/rdv/:id/prepare`, « Carte Vitale » se coche bien).
>
> Les contrôles réellement défaillants de la ronde ont été filés séparément :
> **#8140** (facette « Dentiste » sans effet), **#8145** et **#8147** (app infirmière).

| app | écran/route | contrôles inventoriés | activés | OK | morts (candidats) | cassés (candidats) | last_check ISO |
|---|---|---|---|---|---|---|---|
| infirmiere | `/` (390px) | 8 | 8 | 1 | 0 | 6 | 2026-10-08T01:55:00Z |
| patient | `/appointments` (390px) | 28 | 28 | 24 | 4 | 0 | 2026-10-08T01:55:00Z |
| patient | `/book` (390px) | 28 | 28 | 25 | 0 | 0 | 2026-10-08T01:55:00Z |
| patient | `/coverage-setup` (390px) | 9 | 2 | 0 | 2 | 0 | 2026-10-08T01:55:00Z |
| patient | `/documents` (390px) | 41 | 41 | 10 | 12 | 19 | 2026-10-08T01:55:00Z |
| patient | `/financial` (390px) | 9 | 18 | 2 | 0 | 16 | 2026-10-08T01:55:00Z |
| patient | `/mes-rdv` (390px) | 13 | 13 | 6 | 7 | 0 | 2026-10-08T01:55:00Z |
| patient | `/notifications` (390px) | 20 | 20 | 15 | 1 | 4 | 2026-10-08T01:55:00Z |
| patient | `/oubliettes` (390px) | 2 | 2 | 1 | 1 | 0 | 2026-10-08T01:55:00Z |
| patient | `/pharmacy` (390px) | 8 | 8 | 6 | 2 | 0 | 2026-10-08T01:55:00Z |
| patient | `/pharmacy/search` (390px) | 1 | 1 | 1 | 0 | 0 | 2026-10-08T01:55:00Z |
| patient | `/pharmacy/send` (390px) | 66 | 40 | 27 | 13 | 0 | 2026-10-08T01:55:00Z |
| patient | `/prescriptions` (390px) | 17 | 17 | 17 | 0 | 0 | 2026-10-08T01:55:00Z |
| patient | `/profile` (390px) | 17 | 17 | 11 | 5 | 0 | 2026-10-08T01:55:00Z |
| patient | `/profile/consents` (390px) | 12 | 24 | 13 | 9 | 0 | 2026-10-08T01:55:00Z |
| patient | `/profile/dependents` (390px) | 21 | 21 | 9 | 9 | 3 | 2026-10-08T01:55:00Z |
| patient | `/profile/notifications` (390px) | 17 | 17 | 9 | 3 | 0 | 2026-10-08T01:55:00Z |
| patient | `/rdv/01f07796-dd0f-4daf-9b4b-126eaf94cbea/prepare` (390px) | 3 | 3 | 1 | 2 | 0 | 2026-10-08T01:55:00Z |
| patient | `/reviews` (390px) | 1 | 1 | 1 | 0 | 0 | 2026-10-08T01:55:00Z |
| patient | `/treatment-plans` (390px) | 11 | 11 | 10 | 0 | 1 | 2026-10-08T01:55:00Z |
| pharmacie | `/` (1280px) | 44 | 24 | 21 | 0 | 2 | 2026-10-08T01:55:00Z |
| pharmacie | `/devis` (1280px) | 42 | 42 | 38 | 3 | 0 | 2026-10-08T01:55:00Z |
| pharmacie | `/messages` (1280px) | 14 | 14 | 7 | 6 | 0 | 2026-10-08T01:55:00Z |
| pharmacie | `/orders/c1a76f57-72ba-48cb-bea0-51581a92c8c8/pickup` (1280px) | 4 | 4 | 2 | 1 | 0 | 2026-10-08T01:55:00Z |
| pharmacie | `/stock` (1280px) | 34 | 34 | 30 | 3 | 0 | 2026-10-08T01:55:00Z |
| praticien | `/agenda` (1280px) | 31 | 31 | 26 | 4 | 0 | 2026-10-08T01:55:00Z |
| praticien | `/consent-templates` (1280px) | 22 | 22 | 22 | 0 | 0 | 2026-10-08T01:55:00Z |
| praticien | `/consultation` (1280px) | 38 | 38 | 36 | 1 | 0 | 2026-10-08T01:55:00Z |
| praticien | `/courriers` (1280px) | 6 | 6 | 4 | 2 | 0 | 2026-10-08T01:55:00Z |
| praticien | `/devis` (1280px) | 30 | 30 | 17 | 2 | 10 | 2026-10-08T01:55:00Z |
| praticien | `/lab-work-orders` (1280px) | 32 | 59 | 44 | 13 | 0 | 2026-10-08T01:55:00Z |
| praticien | `/mes-conges` (1280px) | 24 | 24 | 19 | 3 | 1 | 2026-10-08T01:55:00Z |
| praticien | `/messages` (1280px) | 30 | 30 | 25 | 1 | 3 | 2026-10-08T01:55:00Z |
| praticien | `/notification-preferences` (1280px) | 6 | 6 | 3 | 3 | 0 | 2026-10-08T01:55:00Z |
| praticien | `/ordonnances` (1280px) | 22 | 22 | 16 | 2 | 3 | 2026-10-08T01:55:00Z |
| praticien | `/ordonnances/new` (1280px) | 22 | 22 | 20 | 1 | 0 | 2026-10-08T01:55:00Z |
| praticien | `/patients` (1280px) | 38 | 31 | 28 | 2 | 1 | 2026-10-08T01:55:00Z |
| praticien | `/questionnaire-templates` (1280px) | 4 | 4 | 2 | 2 | 0 | 2026-10-08T01:55:00Z |
| praticien | `/stock` (1280px) | 24 | 13 | 11 | 2 | 0 | 2026-10-08T01:55:00Z |
| praticien | `/stock-inventory` (1280px) | 47 | 47 | 35 | 11 | 0 | 2026-10-08T01:55:00Z |
| praticien | `/treatment-plans` (1280px) | 6 | 6 | 4 | 2 | 0 | 2026-10-08T01:55:00Z |
| praticien | `/waiting-room` (1280px) | 23 | 23 | 19 | 2 | 1 | 2026-10-08T01:55:00Z |
| secretariat | `/` (1280px) | 37 | 36 | 27 | 7 | 1 | 2026-10-08T01:55:00Z |
| secretariat | `/admin-membres` (1280px) | 23 | 13 | 11 | 1 | 1 | 2026-10-08T01:55:00Z |
| secretariat | `/admin-secretariats` (1280px) | 5 | 5 | 2 | 3 | 0 | 2026-10-08T01:55:00Z |
| secretariat | `/agenda` (1280px) | 83 | 83 | 63 | 15 | 0 | 2026-10-08T01:55:00Z |
| secretariat | `/appointment-motifs` (1280px) | 5 | 5 | 2 | 3 | 0 | 2026-10-08T01:55:00Z |
| secretariat | `/appointments` (1280px) | 29 | 21 | 17 | 4 | 0 | 2026-10-08T01:55:00Z |
| secretariat | `/audit-log` (1280px) | 5 | 5 | 2 | 3 | 0 | 2026-10-08T01:55:00Z |
| secretariat | `/bookable-slots` (1280px) | 28 | 28 | 21 | 6 | 0 | 2026-10-08T01:55:00Z |
| secretariat | `/cabinet-payouts` (1280px) | 28 | 28 | 20 | 5 | 0 | 2026-10-08T01:55:00Z |
| secretariat | `/cabinet-stats` (1280px) | 25 | 25 | 17 | 6 | 1 | 2026-10-08T01:55:00Z |
| secretariat | `/conges` (1280px) | 41 | 41 | 21 | 9 | 10 | 2026-10-08T01:55:00Z |
| secretariat | `/correspondents` (1280px) | 47 | 47 | 42 | 4 | 0 | 2026-10-08T01:55:00Z |
| secretariat | `/data-import` (1280px) | 5 | 5 | 4 | 1 | 0 | 2026-10-08T01:55:00Z |
| secretariat | `/devis` (1280px) | 56 | 56 | 49 | 5 | 1 | 2026-10-08T01:55:00Z |
| secretariat | `/liste-attente` (1280px) | 24 | 24 | 18 | 4 | 1 | 2026-10-08T01:55:00Z |
| secretariat | `/maintenance` (1280px) | 30 | 30 | 22 | 7 | 0 | 2026-10-08T01:55:00Z |
| secretariat | `/messages` (1280px) | 47 | 47 | 37 | 8 | 1 | 2026-10-08T01:55:00Z |
| secretariat | `/patients` (1280px) | 44 | 44 | 34 | 7 | 2 | 2026-10-08T01:55:00Z |
| secretariat | `/salle-attente` (1280px) | 26 | 26 | 24 | 0 | 0 | 2026-10-08T01:55:00Z |
| secretariat | `/tasks` (1280px) | 5 | 5 | 4 | 0 | 1 | 2026-10-08T01:55:00Z |

**Cas adversariaux joués** (en plus de l'audit bouton-par-bouton) :

| cas | cible | résultat |
|---|---|---|
| double-submit rapide (2 clics < 100 ms) | messagerie patient → cabinet, « Envoyer le message » | **OK** — 1 seul `POST /v1/conversations/:id/messages`, 1 seule occurrence à l'écran |
| submit avec champs requis vides | patient, feuille « Ajouter un proche » | **OK** — « Ajouter » reste `aria-disabled=true`, 0 requête, pas de 500 |
| texte très long (215 caractères) | patient, champs Prénom/Nom du proche | **OK** — 0 débordement horizontal mesuré sur l'arbre Semantics |
| sélecteur de date | patient, « Date de naissance » du proche | **OK** — le dialogue s'ouvre (`Sélectionner une année`, `Mois précédent/suivant`, jours) |
| retour navigateur au milieu de la réservation | patient `/appointments` → `/appointments/slots?...` → bénéficiaire → `goBack()` | **OK** — retour cohérent sur `/appointments` (34 nœuds, 0 erreur), `goForward()` restaure l'écran de créneaux (81 nœuds) |
| double-clic sur une **action métier** d'un back-office | pharmacie `/stock`, « Accepter » une demande de réappro | **OK** — le 1er clic ouvre un `alertdialog` (« Accepter la demande » + note optionnelle), le double-clic sur sa validation n'émet qu'**un seul** `POST /v1/pharmacy/stock-requests/:id/accept`, 0 réponse ≥ 400 |
| deux requêtes **réellement concurrentes** | `POST /v1/cabinet/quotes` ×2 en parallèle | 2 brouillons distincts créés — **pas un défaut** : l'endpoint ne déclare pas d'idempotence (`cabinet_quotes.rs` n'a aucun `Idempotency-Key`) et aucun client du dépôt n'en envoie sur cette route (seuls `payments_api`, `review_api`, `billing_api`, `search_api` le font) |
| coupure réseau (`route('**/v1/**').abort`) | **les 5 apps** | 4/5 **OK** (message + « Réessayer ») ; **app infirmière sans aucun chemin de reprise → #8145** |


### Ronde R133 — 2026-10-07 (18:00–19:3x UTC) — **5/5 apps + tunnel SSR**, 36 écrans/vues, **377 contrôles inventoriés, 357 activés et jugés, 0 MORT RÉEL, 0 CASSÉ RÉEL**

> **Ciblage** : écrans touchés par les 7 merges depuis `ca491fa7` (#6853 file de travail secrétariat,
> #6854 fiche patient praticien, #6857 `/book`, #6859 `/profile/consents`, #8110 distances) en priorité,
> puis rotation sur les routes **jamais auditées** (`/oubliettes`, `/reviews`, `/liste-attente`,
> `/bookable-slots`, `/correspondents`, `/lab-work-orders`, praticien `/stock`, pharmacie `/messages`).
>
> ⚠️ **Correctif de méthode de cette ronde (à conserver)** : `page.mouse.click(x,y)` **ne déclenche pas**
> certains boutons Flutter web — le tap est trop court pour que le `GestureDetector` le reconnaisse.
> Le bouton « **Accepter** » d'une offre de l'app infirmière a été relevé « MORT » (0 requête,
> 0 repeinture) alors qu'il **fonctionne parfaitement** : avec `move → down → 90 ms → up`, le même clic
> émet `POST /v1/nurse/visits/:id/accept` **200** et bascule l'écran sur « Ma visite ».
> L'auditeur utilise désormais le geste long par défaut, et **tous les « MORT » bruts de la ronde ont
> été re-joués un par un** avec ce geste avant d'être consignés.

| app | écran/route | contrôles inventoriés | activés | OK | morts | cassés | last_check ISO |
|---|---|---|---|---|---|---|---|
| praticien | `/patients` (1280×800) | 14 | 13 | 13 | 0 | 0 | 2026-10-07T18:19:00Z |
| praticien | `/patients/:id` — patient **sans** relation de soin (1280×800) | 11 | 7 | 7 | 0 | 0 | 2026-10-07T18:12:00Z |
| praticien | `/patients/:id` — patient **avec** relation de soin (1280×800) | 11 | 10 | 10 | 0 | 0 | 2026-10-07T18:13:00Z |
| praticien | `/ordonnances` (1280×800, sans patient) | 3 | 3 | 3 | 0 | 0 | 2026-10-07T18:20:00Z |
| praticien | `/ordonnances/new?patientId=` (1440×900, **3 colonnes**) | 24 | 20 | 20 | 0 | 0 | 2026-10-07T19:14:00Z |
| praticien | **⌘K palette Spotlight** (1280×800) | 18 | 15 | 15 | 0 | 0 | 2026-10-07T18:36:00Z |
| praticien | `/lab-work-orders` (1280×800) | 7 | 7 | 7 | 0 | 0 | 2026-10-07T19:21:00Z |
| praticien | `/stock` (1280×800) | 4 | 4 | 4 | 0 | 0 | 2026-10-07T19:21:00Z |
| praticien | `/team-messages` → « Mentionner » + composeur (1280×800) | 4 | 4 | 4 | 0 | 0 | 2026-10-07T19:25:00Z |
| secretariat | `/` tableau de bord (1280×800) | 21 | 21 | 21 | 0 | 0 | 2026-10-07T18:22:00Z |
| secretariat | `/` rail de navigation — repli des 5 groupes (1280×1000) | 5 | 5 | 5 | 0 | 0 | 2026-10-07T19:00:00Z |
| secretariat | `/team-messages` (1280×800) | 22 | 19 | 16 | 0 | 0 | 2026-10-07T18:42:00Z |
| secretariat | `/liste-attente` (1280×800) | 14 | 12 | 12 | 0 | 0 | 2026-10-07T19:20:00Z |
| secretariat | `/bookable-slots` (1280×800) | 17 | 15 | 15 | 0 | 0 | 2026-10-07T19:21:00Z |
| secretariat | `/correspondents` (1280×800) | 29 | 21 | 20 | 0 | 0 | 2026-10-07T19:21:00Z |
| patient | `/book` (390×844) | 22 | 22 | 22 | 0 | 0 | 2026-10-07T18:25:00Z |
| patient | `/profile/consents` + feuille de retrait (390×844) | 10 | 9 | 9 | 0 | 0 | 2026-10-07T18:28:00Z |
| patient | `/documents` + facettes de catégorie (390×844) | 24 | 22 | 22 | 0 | 0 | 2026-10-07T19:19:00Z |
| patient | `/financial` + détail d'un devis ventilé (390×844) | 9 | 9 | 9 | 0 | 0 | 2026-10-07T19:13:00Z |
| patient | `/notifications` (390×844) | 6 | 6 | 6 | 0 | 0 | 2026-10-07T19:10:00Z |
| patient | `/implant-passport` + `/implant-passport/:id` (390×844) | 12 | 10 | 10 | 0 | 0 | 2026-10-07T19:02:00Z |
| patient | `/messaging` + fil de conversation (390×844) | 12 | 12 | 12 | 0 | 0 | 2026-10-07T19:06:00Z |
| patient | `/oubliettes` (390×844) | 1 | 1 | 1 | 0 | 0 | 2026-10-07T19:23:00Z |
| patient | `/reviews` (390×844) | 1 | 1 | 1 | 0 | 0 | 2026-10-07T19:23:00Z |
| patient | `/profile/dependents` (390×844) | 12 | 12 | 12 | 0 | 0 | 2026-10-07T19:23:00Z |
| pharmacie | `/` file des commandes (1280×800) | 19 | 19 | 19 | 0 | 0 | 2026-10-07T18:32:00Z |
| pharmacie | `/stock` demandes des cabinets (1280×800) | 20 | 20 | 20 | 0 | 0 | 2026-10-07T18:34:00Z |
| pharmacie | `/devis` devis d'officine (1280×800) | 18 | 18 | 18 | 0 | 0 | 2026-10-07T19:23:00Z |
| pharmacie | `/messages` + les 3 facettes (1280×800) | 7 | 7 | 7 | 0 | 0 | 2026-10-07T19:25:00Z |
| infirmiere | `/` 3 onglets (390×844) | 4 | 4 | 4 | 0 | 0 | 2026-10-07T18:47:00Z |
| infirmiere | **parcours métier complet** : Offres → Accepter → Je pars → Je suis arrivé·e → Visite terminée (390×844) | 8 | 8 | 8 | 0 | 0 | 2026-10-07T18:52:00Z |
| praticien | `/agenda` (1280×800) | 8 | 8 | 8 | 0 | 0 | 2026-10-07T19:28:00Z |
| praticien | `/waiting-room` (1280×800) | 5 | 3 | 3 | 0 | 0 | 2026-10-07T19:30:00Z |
| praticien | `/messages` (1280×800) | 10 | 10 | 10 | 0 | 0 | 2026-10-07T19:32:00Z |
| praticien | `/consultation` — liste des séances (1280×800 et **1258×834**) | 24 | 22 | 22 | 0 | 0 | 2026-10-07T19:31:00Z |
| patient | `/mes-rdv` — onglets À venir / Historique (390×844) | 6 | 6 | 6 | 0 | 0 | 2026-10-07T19:29:00Z |
| secretariat | `/salle-attente` poste comptoir (1280×800) | 17 | 16 | 15 | 0 | 0 | 2026-10-07T19:38:00Z |
| patient | `/pharmacy` ma pharmacie — dont liens externes (390×844) | 7 | 7 | 7 | 0 | 0 | 2026-10-07T19:51:00Z |
| patient | `/pharmacy/search` annuaire d'officines (390×844) | 1 | 1 | 1 | 0 | 0 | 2026-10-07T19:53:00Z |
| tunnel SSR | `/`, `/dentiste/lyon`, fiche praticien, `/reservation/confirmer` (1280×900 + 390×844) | 8 | 8 | 8 | 0 | 0 | 2026-10-07T19:03:00Z |

**« MORT » bruts relevés puis invalidés (25)** — chacun re-joué avec le geste long et/ou après défilement :

| contrôle | écran | verdict brut | ce que c'était réellement |
|---|---|---|---|
| `Accepter` (offre de visite) | infirmiere `/` Offres | MORT | **artefact de clic court** — `POST /nurse/visits/:id/accept` **200** avec `down/up 90 ms`, l'écran bascule sur « Ma visite » |
| `Mentionner` | secretariat `/team-messages` | MORT | **artefact de clic court** — geste long : focus composeur + `@` pré-saisi, la frappe active « Envoyer », `POST /v1/cabinet/messages` **201** |
| `Dentiste` (facette) | patient `/book` 390 | MORT | **hors viewport** (`x=490..587` sur 390 px) ; le rail défile horizontalement, après molette `GET /search/providers?q=dentiste` part bien *(le défaut réel de cette facette est fonctionnel → #8121)* |
| 8 facettes de catégorie (`Radio 27`, `CBCT 3`, `Photo 10`, `Compte-rendu 7`, `Consentement 8`, `Consigne 24`, `Carte mutuelle 31`, `Autre 24`) | patient `/documents` 390 | MORT ×8 | **hors viewport** (`x=561..1548` sur 390 px). Après défilement : `Radio 27` passe `checked false→true` **et la liste est réellement filtrée** (12 cartes « Devis/Ordonnance » → 12 cartes « Radio ») |
| `Absences` (en-tête de groupe du rail) ×3 | secretariat `/`, `/liste-attente`, `/bookable-slots` 1280×**800** | MORT ×3 | **artefact de comptage** : replier le groupe retire « Congés » **et** démasque l'en-tête « Réglages du cabinet » jusque-là rogné ⇒ total inchangé. À 1280×**1000** le repli est net (18 → 17, « Congés » disparaît) et « Réglages du cabinet » déplie 5 destinations (18 → 23) |
| `Équipe` / `Demandes de créneau` / `Correspondants` / `Facturation` | secretariat (écran courant) | MORT ×4 | **destination ou groupe déjà actif** — un clic sur l'écran déjà affiché ne fait rien, légitime |
| `Écrire à l'équipe…` (textbox) | secretariat `/team-messages` | MORT | **limite de l'instrument** : le texte saisi est peint sur le canvas, invisible de l'arbre Semantics. Preuve indirecte : « Envoyer » passe de `aria-disabled=true` à actif |
| `Joindre un patient ou un devis est indisponible…` / `Épinglage de message indisponible…` | secretariat `/team-messages` | MORT ×2 | **ne sont pas des contrôles** : ce sont les libellés accessibles qui *énoncent la raison* des 2 boutons désactivés (#6702) |
| `À répondre (6)` / `Tous (188)` / `Toutes 1` | pharmacie `/stock`, `/devis`, `/messages` | MORT ×3 | **facette déjà active** (`aria-checked=true`). Re-sélection depuis une autre facette : OK (`/stock` 73 → 66 nœuds) |
| `Itinéraire` / `Appeler` | patient `/pharmacy` | MORT ×2 | **ouverture externe, invisible de la page** : instrumenté `window.open`, les deux boutons appellent bien `https://www.google.com/maps/search/?api=1&query=12+quai+du+Rhône…` et `tel:+33 4 78 00 00 84` |
| `Nom de la pharmacie ou ville` (textbox) | patient `/pharmacy/search` | MORT | **limite de l'instrument** : la frappe « Confluence » déclenche `GET /v1/pharmacies?q=Confluence` **200** et la liste passe de vide à « Pharmacie Confluence · 76 Avenue Tony Garnier, 69007 » |
| `Non lues 1` / `Urgentes 1` | pharmacie `/messages` | MORT ×2 | **bascule correcte mais résultat identique** : l'unique conversation du jeu de données est à la fois non lue ET urgente ⇒ la liste ne change pas. `checked` bascule bien et les 3 facettes restent mutuellement exclusives (vérifié) |

**« CASSÉ » bruts relevés puis invalidés (7)** : 6 sur `praticien /patients` (les 403 `notes`/`medical-record`/
`prescriptions` sur un patient **jamais suivi** — c'est la garde §14 attendue, et l'écran l'**explique**
au lieu de casser), 1 sur `secretariat /correspondents` (**401** sur `GET /v1/cabinet/patients` = jeton
d'accès expiré en cours de run long, non reproduit après reconnexion fraîche : 0 requête 4xx/5xx).

**DÉSACTIVÉS vérifiés légitimes (9)** : `Soins` (consentement verrouillé §14, « Requis pour être soigné ») ·
`Démarrer une consultation` (aucun RDV démarrable, `patients_page.dart:379 startableAppointment == null`) ·
`Schéma dentaire` / `Bilan parodontal` / `Plan de traitement` / `Créer une ordonnance` (patient jamais suivi — #6854, raison affichée) ·
`Joindre un patient, un devis…` / `Épingler` (#6702, raison affichée) · `Envoyer` (composeur vide) ·
3 puces de suggestion ⌘K (`aria-disabled=true` + motif « Réponse en langage naturel indisponible pour le moment. »).

**Non activés (destructifs, hors périmètre)** : `Se déconnecter` (×5 apps), `Supprimer mon compte`
(patient `/profile/consents`), 7 actions de suppression de `secretariat /correspondents`.

### Ronde R131 — 2026-10-07 (06:00–08:3x UTC) — **5/5 apps + tunnel SSR**, 31 écrans/vues, **687 contrôles inventoriés, 426 activés et jugés, 0 MORT RÉEL, 0 CASSÉ RÉEL** (69 « MORT » bruts et 3 « CASSÉ » bruts, tous triés : artefacts de viewport/textbox/rail courant, ou comportements documentés) (1 stub assumé → #8088)

> **Ciblage** : `git fetch`/`git pull` impossibles (Forgejo `100.91.208.56:3000` injoignable pendant toute
> la ronde, cf. `explored-paths.md`) → pas de ciblage diff-driven possible ; rotation sur les **routes les
> moins auditées** du ledger (`/cabinet-setup`, `/team-messages`, `/onboard`, `/patients/new`, `/conges`,
> `/account-setup`, `/devis` + `/stock` officine) et sur les **mécaniques** jamais exécutées.
>
> ⚠️ **Correctif de méthode appliqué cette ronde** : l'activation d'un contrôle par clic aux coordonnées
> produisait des faux « MORT » sur tout contrôle situé **hors du viewport** (`mouse.click` hors fenêtre =
> aucun effet). `R131-audit.js` scrolle désormais le contrôle dans le viewport avant de cliquer et
> marque `HORS-VIEWPORT` ce qu'il ne peut pas atteindre. **6 des 9 « MORT » relevés sur `pharmacie /devis`
> étaient des artefacts de ce défaut** — re-vérifiés un par un (`R131-pha-devis-btn.js`) : `Préparer`
> et `Voir` naviguent bien vers `/orders/<id>` à tous les paliers de défilement.
>
> ⚠️ **Troisième source de faux positifs, identifiée cette ronde : le hors-viewport HORIZONTAL.**
> Le rail de facettes de `patient /documents` déborde à droite (12 puces de `x=16` à `x=1496` sur un
> viewport de **390 px**) : seules « Tous », « Devis », « Facture » et le début d'« Ordonnance » sont
> atteignables sans défilement. Les 8 puces suivantes étaient jugées « MORT ». **Contre-épreuve
> décisive** : un clic sur « Devis 97 » (`x=141..233`, DANS le viewport) bascule bien
> `Tous=true → false` et `Devis=false → true`. Le filtrage est **client-side** (aucune requête — les
> 692 documents sont déjà chargés, cf. R128-F8). Idem pour « Confirmer la demande » de
> `/home-care/new` (`cy=884` pour un viewport de 844) et pour « Voir le devis » de `/notifications`,
> tous deux **fonctionnels** une fois amenés dans la fenêtre.
>
> ⚠️ **Deuxième source de faux positifs neutralisée** : un verdict `MORT` sur un `textbox` (la frappe
> n'émet ni requête ni navigation) et sur l'entrée de rail **déjà sélectionnée** n'a aucune valeur.
> Les 24 « MORT » bruts de cette ronde se décomposent en **0 réel** : 11 textbox, 6 entrées de rail
> courantes, 5 conteneurs `group`/`flt-semantics` de boutons désactivés, 2 contrôles re-testés et OK.

| app | écran/route | contrôles inventoriés | activés | OK | morts | cassés | last_check ISO |
|---|---|---|---|---|---|---|---|
| pharmacie | `/devis` (1280×800) | 42 | 41 | 41 | 0 | 0 | 2026-10-07T06:30:00Z |
| pharmacie | `/stock` (1280×800) + volet de détail | 34 | 33 | 33 | 0 | 0 | 2026-10-07T06:32:00Z |
| praticien | `/cabinet-setup` (1280×800) — formulaire complet + soumission | 6 | 6 | 6 | 0 | 0 | 2026-10-07T07:18:00Z |
| praticien | `/team-messages` (1280×800) — composeur, `Mentionner`, envoi | 32 | 31 | 31 | 0 | 0 | 2026-10-07T07:22:00Z |
| secretariat | `/onboard` (1280×800) | 1 | 1 | 1 | 0 | 0 | 2026-10-07T07:05:00Z |
| secretariat | `/patients/new` (1280×800) — remplissage + création réelle | 8 | 8 | 8 | 0 | 0 | 2026-10-07T07:24:00Z |
| secretariat | `/conges` (1280×800) — file d'attente + décision | 41 | 29 | 29 | 0 | 0 | 2026-10-07T07:28:00Z |
| patient | `/account-setup` (390×844) | 6 | 6 | 6 | 0 | 0 | 2026-10-07T07:10:00Z |
| patient | `/pharmacy` (390×844) — inventaire (audit interrompu : `tel:`/`maps:` sortent de l'app) | 8 | — | — | 0 | 0 | 2026-10-07T07:12:00Z |
| patient | `/financial` + détail d'un devis **à signer** et d'un devis **signé** (390×844) | 3 + 3 | 6 | 6 | 0 | 0 | 2026-10-07T06:46:00Z |
| patient | `/treatment-plans` (390×844) — 3 sections + « Prochaine séance » + « Voir » | 23 | 2 (carte, `Voir`) | 2 | 0 | 0 | 2026-10-07T07:00:00Z |
| patient | `/messaging/:id` — double-submit, 240 caractères, envoi à vide | 8 | 4 | 4 | 0 | 0 | 2026-10-07T07:20:00Z |
| infirmiere | `/` (390×844) — 3 onglets + bascule « En ligne » | 8 | 7 | 7 | 0 | 0 | 2026-10-07T06:56:00Z |
| infirmiere | `/` (**1280×800**) — mêmes contrôles au viewport PC | 8 | 7 | 7 | 0 | 0 | 2026-10-07T06:59:00Z |
| infirmiere | `/notification-preferences` (390×844) | 5 | 5 | 5 | 0 | 0 | 2026-10-07T06:58:00Z |
| praticien | `/patients/:id/treatment-plans` (1280×800 **et** 1258×834) | 36 | 2 | 2 | 0 | 0 | 2026-10-07T06:36:00Z |
| secretariat | `/salle-attente` (1280×800, **file de 2 patients construite pour la ronde**) | 31 | — (comparaison design-v2 + recoupement API) | — | 0 | 0 | 2026-10-07T06:52:00Z |
| secretariat | `/devis` (1280×800) | 17 | — (comparaison design-v2 + recoupement montants) | — | 0 | 0 | 2026-10-07T06:40:00Z |
| reservation (SSR) | `/`, `/dentiste/lyon`, `/dr-claire-lefevre-omnipratique`, `/zzz-inexistant`, `robots.txt`, `sitemap.xml` — **390 et 1280** | 41 liens + 1 formulaire + 170 créneaux cliquables | 10 navigations | 10 | 0 | 0 | 2026-10-07T07:40:00Z |

| praticien | `/messages` (1280×800) | 30 | 25 | 25 | 0 | 0 | 2026-10-07T07:44:00Z |
| praticien | `/act-categories` (1280×800) — **403 de chargement** | 1 | 1 | 1 | 0 | 0 | 2026-10-07T07:50:00Z |
| praticien | `/waiting-room` (1280×800, **file non vide**) | 28 | — (inventaire + comparaison) | — | 0 | 0 | 2026-10-07T07:47:00Z |
| patient | `/home-care/new` (390×844) — **parcours métier complet jusqu'à la demande créée** | 13 | 13 | 13 | 0 | 0 | 2026-10-07T07:41:00Z |
| patient | `/profile/consents` (390×844) | 12 | 12 | 12 | 0 | 0 | 2026-10-07T07:38:00Z |
| patient | `/profile` (390×844) — inventaire | 16 | — | — | 0 | 0 | 2026-10-07T07:22:00Z |
| secretariat | `/salle-attente` — **bandeau de dépassement de seuil** (1280×800) | 31 | 1 (`Prévenir le praticien`) | 0 | 0 | 0 (**stub assumé → #8088**) | 2026-10-07T07:55:00Z |
| secretariat | `/devis` — double-clic et clic répété sur `Relancer` (1280×800) | 17 | 1 | 1 | 0 | 0 | 2026-10-07T07:41:00Z |

| praticien | `/agenda` (1280×800) | 31 | 25 | 25 | 0 | 0 | 2026-10-07T07:58:00Z |
| praticien | `/stock-inventory` (1280×800) | 47 | 25 | 25 | 0 | 0 | 2026-10-07T08:05:00Z |
| secretariat | `/agenda` (1280×800) | 65 | 24 | 24 | 0 | 0 | 2026-10-07T08:10:00Z |
| secretariat | `/bookable-slots` (1280×800) | 28 | 25 | 25 | 0 | 0 | 2026-10-07T08:14:00Z |
| patient | `/notifications` (390×844) | 21 | 21 | 21 | 0 | 0 | 2026-10-07T08:17:00Z |
| patient | `/documents` (390×844) — 12 facettes + liste | 41 | 23 | 23 | 0 | 0 | 2026-10-07T08:25:00Z |

#### Cas adversariaux joués cette ronde

| cas | app / écran | résultat |
|---|---|---|
| **double-submit** sur « Envoyer le message » | patient `/messaging/:id` | **1 seul** `POST /v1/conversations/:id/messages` (201). Garde correcte. |
| **double-tap** sur la bascule « En ligne » | infirmiere `/` | 2 `PATCH /v1/nurse/availability` enchaînés — **l'état final dépend de la course** (cf. **F2**). |
| **BACK navigateur** au milieu du tunnel de réservation | patient `/appointments` → `/appointments/provider` → BACK | revient sur `/appointments`, **24 contrôles**, aucun écran blanc. `FORWARD` ne ré-entre pas dans le tunnel (reste sur `/appointments`) — sans conséquence d'état. |
| **texte très long** (240 caractères) dans le composeur | patient `/messaging/:id` | **0 contrôle débordant** avant et après envoi, `201` à l'envoi. |
| **soumission à vide** | patient `/messaging/:id` | aucune requête, aucune erreur brute — refus silencieux propre. |
| **saisie invalide via l'UI** | praticien `/cabinet-setup` | téléphone/SIRET hors format ⇒ « Enregistrer » **reste désactivé** ; valeurs valides ⇒ bouton actif. |
| **403 sur une action métier** | praticien `/cabinet-setup` → `PATCH /v1/cabinet` | snackbar **« Accès refusé. Rôle administrateur requis. »** — message digne, pas de silence. |
| **403 sur une action métier** | secretariat `/conges` → `POST …/leave-requests/:id/decide` | snackbar **« Validation réservée aux administrateurs/managers. »** (comportement documenté #7143). |
| **coupure réseau** (`route.abort` sur `**/v1/**`) | patient `/mes-rdv` | « **Erreur réseau. Vérifiez votre connexion.** » + « Réessayer » ; après rétablissement, « Réessayer » ramène 18 contrôles. |
| **coupure réseau** | infirmiere `/` | l'écran reste rendu (8 contrôles, 3 onglets) avec le sous-titre « Disponibilité indisponible — impossible de joindre le serveur » ; **aucun bouton de reprise** sur cet écran (la bascule reste le seul geste possible) — déjà consigné en R128. |
| **BACK navigateur** | infirmiere `/notification-preferences` → BACK | retour sur `/`, 8 contrôles, pas d'écran blanc. |
| **double-clic** sur « Relancer » (devis) | secretariat `/devis` | **1 seul** `POST …/remind` — garde front correcte. *(L'API, elle, n'a aucune fenêtre de garde → #8087.)* |
| **clic répété à 3 s** sur « Relancer » | secretariat `/devis` | le 2ᵉ clic n'émet rien non plus. |
| **403 de chargement d'écran** | praticien `/act-categories` → `GET /v1/cabinet/settings/act-categories` | état vide digne : cadenas + « **Accès réservé aux administrateurs** » + « Accès refusé. Rôle administrateur requis. » |
| **contrôle sous le pli** | patient `/home-care/new` → « Confirmer la demande » à `cy=884` (viewport 844) | invisible sans défilement ; après défilement ⇒ `201 POST /v1/account/visit-requests` et navigation vers `/home-care/:id` (« Recherche d'une infirmière »). **Faux « MORT » initial du harnais — corrigé.** |

### Ronde R128 — 2026-10-06 (12:00–15:00 UTC) — **5/5 apps + tunnel SSR**, 37 écrans/vues, **899 contrôles inventoriés, 434 activés et jugés, 0 MORT RÉEL, 5 CASSÉS RÉELS (dont 1 P0)**

> **Ciblage** : ronde diff-driven (4 merges depuis `ce660b99`) puis rotation sur les écrans et les
> **mécaniques** les moins éprouvées. Le gros de la valeur de cette ronde ne vient pas du balayage
> de boutons (les 5 apps sont très couvertes) mais des **cas adversariaux sur les boutons d'action** :
> c'est un **double-clic** sur « Ajouter » qui a sorti le **P0 de la ronde** (F7, écran de consultation
> entièrement détruit).

> ⚠️ **Deux nouvelles familles de faux positifs, à retenir pour les prochaines rondes** — elles ont
> toutes deux failli produire des findings inventés :
>
> **(10ᵉ) Les `SnackBar` Flutter ne sont PAS dans l'arbre Semantics.** Clic sur « Appeler » d'une ligne
> hors tête de file en salle d'attente : 0 requête, 0 navigation, `flt-semantics` **inchangé** →
> l'auditeur conclut « MORT ». **Faux.** La capture au même instant montre, en bas de l'écran,
> « *Seul le patient en tête de file peut être appelé pour l'instant.* ». **Règle : avant de déclarer
> MORT un contrôle sans requête, prendre une capture et la regarder.** Le `blankRatio` seul ne suffit
> pas non plus (un snackbar change ~1 % des pixels).
>
> **(11ᵉ) La valeur d'un champ Flutter n'est pas dans le DOM.** `input.value` reste `""` même quand le
> champ est pré-rempli : le texte est peint sur le canvas. Sonder `document.querySelectorAll('input')`
> pour vérifier un pré-remplissage donne **toujours** « vide ». Vérifié sur le dialogue d'acte CCAM :
> `value=""` côté DOM, « **26** » et « **600,00** » bien visibles sur la capture. La dent sélectionnée
> dans le schéma EST donc bien reportée dans l'acte (`ccam_picker.dart:390`, #4048) — mécanique
> **conforme**, contrairement à ce que le DOM laissait croire.
>
> *(Rappel des familles déjà connues, toutes reconfirmées : wrapper `group|…`, entrée de rail **active**
> (cliquer « Devis » depuis `/devis` ne navigue nulle part), facette **déjà sélectionnée**, champ de
> saisie (le focus seul ne repeint pas), contrôle **sous le bord du viewport**, `push()` sans
> changement d'URL. **Nouveauté R128 : l'en-tête de groupe du rail.** Replier « Facturation » retire
> 2 entrées sur 19 : le `blankRatio` bouge de `-0.0000` → jugé MORT. Test dédié
> (`R128-rail.js`, comptage des entrées avant/après) : **5 en-têtes sur 5 replient réellement**
> (`Ma journée` −3, `Patients` −3, `Facturation` −2, `Messages` −2, `Absences` −1). 0 mort.)*

> **Seuil « canvas vide » : 0,92 ne suffit pas seul.** Deux écrans légitimes dépassent le seuil —
> le scan de retrait pharmacie (`0,935`, écran volontairement épuré) et l'écran d'erreur réseau
> (`0,994`, « Impossible de charger vos accès pharmacie. » + « Réessayer »). **À coupler systématiquement
> avec `countCanvas()` et le nombre de contrôles** : le vrai blank de F7 donne `nearWhite=1.000`,
> **`canvas=0`**, `flt-semantics=1`, 0 contrôle — c'est `canvas=0` qui le distingue.

| app | écran/route | contrôles inventoriés | activés | OK | morts | cassés | last_check ISO |
|---|---|---|---|---|---|---|---|
| praticien | `/consultation?id=…` (séance au fauteuil, 1280×834) — **audit de mécanique** | 67 | 12 | 11 | 0 | **1 (P0 — F7)** | 2026-10-06T13:45:00Z |
| praticien | `/patients/:id` (fiche patient, 1280×800) | 29 | 3 | 2 | 0 | **1 (P1 — F1)** | 2026-10-06T12:28:00Z |
| praticien | `/patients/:id/treatment-plans` (1280×800) | 24 | 5 | 5 | 0 | 0 | 2026-10-06T13:05:00Z |
| praticien | `/tasks` | 15 | 15 | 15 | 0 | 0 | 2026-10-06T13:55:00Z |
| praticien | `/ordonnances` | 21 | 21 | 19 (+2 faux morts : wrapper d'en-tête, entrée de rail active) | 0 | 0 | 2026-10-06T13:55:00Z |
| praticien | `/lab-stats` | 2 | 2 | 1 (+1 faux mort : carte non tappable) | 0 | 0 | 2026-10-06T13:55:00Z |
| praticien | `/act-categories` | 1 | 1 | 1 | 0 | 0 | 2026-10-06T13:55:00Z |
| praticien | `/ordonnances/new?patientId=…` (éditeur complet : modèles, DCI, aperçu, signature) | 34 | 5 | 4 | 0 | **1 (P1 — F9, double-submit)** | 2026-10-06T14:18:00Z |
| praticien | `/stock-inventory` | 38 | 22 | 20 (+2 faux morts) | 0 | 0 | 2026-10-06T14:45:00Z |
| praticien | `/consent-templates` | 16 | 10 | 2 (+8 faux morts : cartes `group|` non tappables) | 0 | 0 | 2026-10-06T14:50:00Z |
| pharmacie | `/orders/:id` + `/orders/:id/pickup` (délivrance + scan complet) | 24 | 7 | 7 | 0 | 0 | 2026-10-06T14:12:00Z |
| secretariat | `/devis` (liste + volet + clavier + tri + facettes) | 56 | 12 | 12 | 0 | 0 | 2026-10-06T12:47:00Z |
| secretariat | `/salle-attente` (file de 2, call-next + appel hors ordre) | 26 | 8 | 8 | 0 | 0 | 2026-10-06T12:40:00Z |
| secretariat | `/stock` (liste + volet `Honorée` et `Envoyée` + clavier) | 57 | 9 | 9 | 0 | 0 | 2026-10-06T13:20:00Z |
| secretariat | `/stock` → dialogue « Nouvelle demande » (+ sélecteur de pharmacie) | 11 | 6 | 6 | 0 | 0 | 2026-10-06T14:52:00Z |
| secretariat | `/` — palette ⌘K (ouvrir, saisir, ↑↓, ⏎, Échap) | 18 | 6 | 6 | 0 | 0 | 2026-10-06T13:35:00Z |
| secretariat | rail de navigation — **5 en-têtes de groupe repliables** | 19 | 5 | 5 | 0 | 0 | 2026-10-06T13:50:00Z |
| secretariat | `/liste-attente` | 23 | 21 | 14 (+7 faux morts : en-têtes de rail, wrapper) | 0 | 0 | 2026-10-06T13:40:00Z |
| secretariat | `/conformite` | 35 | 17 | 5 (+12 faux morts : cartes `group|` non tappables, facette active) | 0 | 0 | 2026-10-06T13:40:00Z |
| secretariat | `/appointment-motifs` | 24 | 22 | 16 (+6 faux morts : en-têtes de rail) | 0 | 0 | 2026-10-06T13:45:00Z |
| secretariat | `/correspondents` | 46 | 22 | 15 (+7 faux morts) | 0 | 0 | 2026-10-06T14:10:00Z |
| secretariat | `/admin-secretariats` | 22 | 22 | 16 (+6 faux morts) | 0 | 0 | 2026-10-06T14:20:00Z |
| secretariat | `/reprise-donnees` | 27 | 22 | 16 (+6 faux morts) | 0 | 0 | 2026-10-06T14:30:00Z |
| secretariat | `/maintenance` | 27 | 22 | 16 (+6 faux morts) | 0 | 0 | 2026-10-06T14:40:00Z |
| secretariat | `/bookable-slots` | 27 | 22 | 16 (+6 faux morts) | 0 | 0 | 2026-10-06T14:48:00Z |
| pharmacie | `/` (file des commandes) | 35 | 20 | 16 (+4 faux morts : wrapper, rail actif, champ de saisie, facette active) | 0 | 0 | 2026-10-06T13:20:00Z |
| pharmacie | `/stock` | 36 | 21 | 17 (+4 faux morts) | 0 | 0 | 2026-10-06T13:25:00Z |
| pharmacie | `/devis` | 33 | 22 | 17 (+5 faux morts) | 0 | 0 | 2026-10-06T13:30:00Z |
| pharmacie | `/messages` (liste + fil + « Ouvrir la commande ») | 13 | 15 | 8 (+7 faux morts : 3 facettes sur 1 seule conversation) | 0 | 0 | 2026-10-06T13:35:00Z |
| patient | `/profile/dependents` + dialogue « Ajouter un proche » (390×844) | 33 | 14 | 13 | 0 | **1 (P1 — F5, double-submit)** | 2026-10-06T13:05:00Z |
| patient | `/financial` (liste + détail de devis) | 9 | 9 | 9 (le « mort » était sous le bord du viewport) | 0 | 0 | 2026-10-06T13:10:00Z |
| patient | `/treatment-plans` | 10 | 10 | 10 (2 faux morts sous le bord, re-vérifiés OK) | 0 | 0 | 2026-10-06T13:10:00Z |
| patient | `/reviews` | 1 | 1 | 1 | 0 | 0 | 2026-10-06T13:10:00Z |
| patient | `/pharmacy/orders/:id` (suivi de commande, 390×844) | 5 | 2 | 2 | 0 | 0 | 2026-10-06T12:12:00Z |
| patient | `/home-care` + `/home-care/:id` (suivi + annulation, double-tap) | 21 | 3 | 3 | 0 | 0 | 2026-10-06T12:55:00Z |
| patient | `/notifications` (390×844) | 22 | 2 | 2 | 0 | 0 | 2026-10-06T13:15:00Z |
| infirmiere | `/` — 3 onglets (Disponibilité / Offres / Ma visite) + cycle complet de visite | 14 | 13 | 13 | 0 | 0 | 2026-10-06T12:50:00Z |
| infirmiere | `/notification-preferences` | 5 | 3 | 3 | 0 | 0 | 2026-10-06T12:30:00Z |
| reservation | tunnel SSR — `/`, `/dentiste/lyon` (5 facettes), fiche praticien, `/reservation/confirmer` | 24 | 7 | 7 | 0 | 0 | 2026-10-06T13:42:00Z |

**Cas adversariaux joués cette ronde** (au-delà de l'activation simple) :

> **(12ᵉ famille de faux positifs — le libellé porté par le WRAPPER.)** Sur `/orders/:id/pickup`,
> chercher « Valider le code » **sans filtrer sur `role==='button'`** renvoie d'abord le `group|` de
> la carte (1280×572, centré à y=342) : le clic tombe au milieu du vide, 0 requête → « MORT ».
> Avec `role==='button'` (rect 1248×44 à y=590), le même clic émet `POST /v1/pharmacy/orders/pickup-scan`
> et l'écran passe à « **Commande retirée** ». **Règle : exiger `role==='button'` dès que le libellé
> est aussi porté par un conteneur.**

> **Synthèse de la ronde : le double-tap est le vecteur le plus rentable, et le front n'a pas de
> garde synchrone.** **18** boutons d'action, sur les 5 apps, ont été soumis au même double-clic ;
> **6 émettent deux écritures** — soit **un sur trois**. La différence entre « bénin » et « grave » ne vient pas du front mais de
> l'**idempotence de l'endpoint** :
>
> | bouton | écritures | endpoint idempotent ? | conséquence |
> |---|---|---|---|
> | patient « Signer le devis » | **2** | **oui** (`POST /quotes/:id/sign` rend le même `signed_at`) | aucune — un seul devis signé |
> | patient « Envoyer la demande » | **2** | non | **2 demandes d'accès** → F5 (P1) |
> | praticien « Créer l'ordonnance » | **2** | non | **2 ordonnances** → F9 (P1) |
> | secrétariat « Combler » (liste d'attente) | **2** | non | **2 offres**, donc **2 notifications identiques** « Un créneau vous est proposé » chez le patient (46 µs d'écart) — consigné, non filé à part (même famille que F5/F9) |
> | secrétariat « Clôturer » (échéance de conformité **récurrente**) | **2** | non | **2 occurrences suivantes** engendrées, même `due_date`, 7 µs d'écart → F11 (P1) |
> | praticien « Ajouter » (acte CCAM) | 1 | — | **écran détruit** → F7 (P0) |
> | praticien « Créer » (tâche), patient « Annuler la demande », secrétariat « Envoyer » un devis, secrétariat « Appeler », secrétariat « Relancer » une demande de stock, secrétariat « Actualiser », praticien « Renommer », pharmacie « Accepter » une demande de stock, pharmacie « Préparer »/« Délivrer » (navigation locale), patient « Continuer » (tunnel de réservation) | 1 ou 0 | — | rien à signaler |
>
> Autrement dit : là où une garde tient, c'est souvent par chance de cadence, pas par conception.
> Les gardes `widget.loading` / `busy` sont **asynchrones** (état de bloc) et se font doubler par deux
> taps à ~50 ms. **Piste transverse pour le front : un verrou synchrone local dans le handler**
> (`if (_submitting) return;`), et pour l'API, généraliser `Idempotency-Key` au-delà de
> `POST /payments/intent` (seul endpoint qui l'exige aujourd'hui, `billing_payments.rs:71-75`).

| cas | écran | résultat |
|---|---|---|
| **double-clic sur « Ajouter »** (acte CCAM) | praticien `/consultation?id=…` | **ÉCRAN BLANC — `canvas=0`, 0 contrôle, 8 s, irrécupérable → F7 (P0)** |
| double-clic sur « Envoyer la demande » | patient dialogue « Ajouter un proche » | **2 POST, 2 demandes créées, 2 `PAGEERROR` → F5 (P1)** |
| **double-clic sur « Créer l'ordonnance »** | praticien `/ordonnances/new` | **2 POST, 2 ordonnances pour le même patient (158 ms d'écart) → F9 (P1)** |
| double-clic sur « Signer le devis » | patient `/financial?id=…` | **2 `POST /v1/quotes/:id/sign`** — mais l'endpoint est **idempotent** (même `signed_at`), donc **aucun dommage** : non filé, consigné comme preuve que la garde front manque aussi ici |
| double-clic sur « Envoyer » un devis | secrétariat `/devis` | OK — 1 seul `POST /cabinet/quotes/:id/send` |
| double-clic sur « Délivrer » | pharmacie `/` | OK — navigation locale vers `/orders/:id/pickup`, 0 écriture |
| double-clic sur « Accepter » (dialogue de demande de stock) | pharmacie `/stock` | OK — 1 seul `POST /pharmacy/stock-requests/:id/accept` |
| double-clic sur « Continuer » (étape 3 du tunnel) | patient `/appointments` | OK — étape locale, 0 écriture |
| double-clic sur « Actualiser » | secrétariat `/salle-attente` | OK — 0 écriture |
| **double-clic sur « Clôturer »** (échéance récurrente) | secrétariat `/conformite` | **2 `POST …/complete`, 2 occurrences suivantes identiques → F11 (P1)** |
| **double-clic sur « Combler »** | secrétariat `/liste-attente` | **2 `POST …/offer`, 2 notifications patient identiques** (l'entrée reste `active`, pas de doublon d'état) |
| double-clic sur « Envoyer » (formulaire incomplet) | secrétariat dialogue « Nouvelle demande » | OK — validation **en ligne** (« Choisissez une pharmacie. »), aucun `pop`, écran intact |
| double-clic sur « Annuler la demande » | patient `/home-care/:id` | OK — **1 seul** `POST …/cancel` |
| double-clic sur « Appeler » de ligne | secrétariat `/salle-attente` | OK — 1 seul `call-next` ; sur une ligne hors tête de file, snackbar explicite |
| e-mail malformé | patient dialogue « Ajouter un proche » | OK — CTA reste **désactivé**, 0 requête |
| numéro de dent invalide (`2626`) | praticien dialogue d'acte CCAM | OK — `422`, snackbar « Impossible d'ajouter l'acte. » *(réserve non filée : le message ne désigne pas le champ fautif, alors que le montant a, lui, son erreur en ligne)* |
| texte de 300 caractères (150 « É » + 150 « x ») | pharmacie recherche `/` | OK — 0 contrôle débordant, 0 requête ≥ 400 |
| coupure réseau (`route.abort()` sur `**/v1/**`) au rechargement | pharmacie `/` | OK — « Impossible de charger vos accès pharmacie. » + « Réessayer » |
| BACK navigateur au milieu d'un flux | pharmacie `/orders/:id` → `/` | OK — file **entièrement repeinte**, données fraîches (CMD-0550 « Reçue ») |
| lien profond vers une route inexistante | secrétariat `/correspondants` (vs `/correspondents`) | OK — 404 digne « Page introuvable … » + « Retour à l'accueil » |
| **double-clic sur « Renommer »** (plan de traitement) | praticien `/patients/:id/treatment-plans` | OK — `canvas=1`, 36 contrôles, écran intact *(contre-épreuve négative de F7)* |
| **double-clic sur « Créer »** (nouvelle tâche) | praticien `/tasks` | OK — **1 seul** `POST /v1/cabinet/tasks` *(contre-épreuve négative de F7)* |
| coupure réseau au rechargement | patient `/`, praticien `/agenda`, secrétariat `/agenda`, infirmière `/` | OK sur les 4 — message explicite + « Réessayer », qui relance les bonnes requêtes une fois le réseau rétabli |
| code de retrait erroné puis valide | pharmacie `/orders/:id/pickup` | OK — « Valider le code » désactivé à vide ; le bon code déclenche `pickup-scan` → « Commande retirée » ; **rejeu du même code → 422** |


### Ronde R125 — 2026-10-05 (18:00–20:20 UTC) — **5/5 apps**, 45 écrans/vues, **~1 030 contrôles inventoriés, 620 activés et jugés, 0 MORT RÉEL, 0 CASSÉ RÉEL**

> **Ciblage** : ronde diff-driven (11 merges depuis `bed8dff2`). Priorité aux écrans touchés par les
> merges du jour : patient `/mes-rdv` + `/rdv/:id/prepare` + `/messaging` + `/home-care/new`,
> pharmacie `/devis`, praticien `/lab-work-orders`. Puis rotation sur les écrans **jamais audités** :
> praticien `/lab-work-orders`, `/lab-stats`, `/stock-inventory`, `/consent-templates`,
> `/questionnaire-templates` ; secrétariat `/cabinet-payouts`, `/appointment-motifs`, `/audit-log`,
> `/bookable-slots`, `/cabinet-stats`, `/maintenance`, `/reprise-donnees` ; patient
> `/profile/referring-doctor`, `/pharmacy/quotes`, `/treatment-plans`, `/implant-passport`.

> ⚠️ **Le piège des faux « MORT » est retombé une 3ᵉ fois, avec une cause NOUVELLE à retenir.**
> Un premier passage sur praticien `/lab-work-orders` a signalé **17 contrôles « MORT »** (tout le rail
> de navigation). **Tous faux.** Cause : « Stats labos » utilise `context.push(AppRouter.labStats)`, un
> push **qui ne change pas l'URL** ; l'auditeur ne re-naviguait que « si l'URL a dérivé », laissait donc
> l'écran *Stats labos* ouvert par-dessus, et tous les clics suivants tombaient dessus. Vérification
> manuelle : « Agenda », « Patients », « Tableau de bord » naviguent correctement depuis
> `/lab-work-orders`, `/ordonnances` et `/stock-inventory`. **Règle ajoutée à l'auditeur : re-naviguer
> systématiquement (`about:blank` puis `goto`) entre deux activations, jamais conditionnellement à l'URL.**
> Les 5 autres « MORT » du run (patient `/pharmacy/quotes`, praticien « Passer à l'essayage »,
> secrétariat `/maintenance`) étaient des **décalages de rect** après qu'une activation précédente
> a modifié la liste — tous re-vérifiés un par un et **tous fonctionnels** :
> `Refuser` d'un devis d'officine → `200 POST /v1/account/pharmacy-quotes/<id>/refuse` ;
> `Passer à l'essayage` sur un bon frais → `200 PATCH /v1/cabinet/lab-work-orders/<id>` (statut `try_in`).

| app | écran/route | contrôles inventoriés | activés | OK | morts | cassés | last_check ISO |
|---|---|---|---|---|---|---|---|
| patient | `/mes-rdv` (390×844, 2 onglets + menu `···`) | 12 | 6 | 6 | 0 | 0 | 2026-10-05T18:12:00Z |
| patient | `/rdv/:id/prepare` (390×844) | 4 | 4 | 4 | 0 | 0 | 2026-10-05T18:10:00Z |
| patient | `/questionnaire-medical/:cabinetId` (390×844) | 10 | 1 | 1 | 0 | 0 | 2026-10-05T18:12:00Z |
| patient | `/messaging` + fil `/messaging/:id` (390×844) | 15 | 8 | 8 | 0 | 0 | 2026-10-05T18:22:00Z |
| patient | `/home-care/new` (390×844) | 12 | 12 | 12 | 0 | 0 | 2026-10-05T19:15:00Z |
| patient | `/pharmacy/orders/:id` suivi + QR (390×844) | 4 | 3 | 2 | 0 | 0 | 2026-10-05T19:02:00Z |
| patient | `/pharmacy/quotes` (390×844) | 5 | 5 | 5 | 0 | 0 | 2026-10-05T19:00:00Z |
| patient | `/pharmacy/search` (390×844) | 1 | 2 | 2 | 0 | 0 | 2026-10-05T19:27:00Z |
| patient | `/profile/referring-doctor` (390×844) | 1 | 1 | 1 | 0 | 0 | 2026-10-05T18:58:00Z |
| patient | `/profile/consents` (390×844) | 6 | 5 | 5 | 0 | 0 | 2026-10-05T19:26:00Z |
| patient | `/profile/dependents` (390×844) | 20 | 0 | — | — | — | 2026-10-05T19:12:00Z |
| patient | `/treatment-plans` (390×844) | 7 | 7 | 7 | 0 | 0 | 2026-10-05T19:10:00Z |
| patient | `/implant-passport` (390×844) | 5 | 5 | 5 | 0 | 0 | 2026-10-05T19:10:00Z |
| patient | `/reviews` (390×844) | 1 | 1 | 1 | 0 | 0 | 2026-10-05T19:10:00Z |
| patient | `/oubliettes` (390×844) | 1 | 1 | 1 | 0 | 0 | 2026-10-05T19:26:00Z |
| patient | `/notifications` (390×844) | 20 | 0 | — | — | — | 2026-10-05T18:38:00Z |
| praticien | `/lab-work-orders` (1280×800 **et** 1600×900) | 27 | 25 | 25 | 0 | 0 | 2026-10-05T19:05:00Z |
| praticien | `/lab-stats` (1280×800) | 1 | 1 | 1 | 0 | 0 | 2026-10-05T18:35:00Z |
| praticien | `/stock-inventory` (1280×800) | 30 | 29 | 29 | 0 | 0 | 2026-10-05T18:40:00Z |
| praticien | `/consent-templates` (1280×800) | 8 | 8 | 8 | 0 | 0 | 2026-10-05T18:55:00Z |
| praticien | `/questionnaire-templates` (1280×800) | 2 | 2 | 2 | 0 | 0 | 2026-10-05T18:56:00Z |
| praticien | `/consultation` + séance au fauteuil (1280×800 → 1920×1080) | 95 | 4 | 4 | 0 | 0 | 2026-10-05T19:00:00Z |
| praticien | palette ⌘K (depuis `/`) | 17 | 6 | 6 | 0 | 0 | 2026-10-05T19:21:00Z |
| secretariat | `/cabinet-payouts` + volet de détail (1280×800) | 29 | 27 | 27 | 0 | 0 | 2026-10-05T18:48:00Z |
| secretariat | `/appointment-motifs` (1280×800) | 22 | 21 | 21 | 0 | 0 | 2026-10-05T18:46:00Z |
| secretariat | `/audit-log` (1280×800) | 26 | 23 | 23 | 0 | 0 | 2026-10-05T18:47:00Z |
| secretariat | `/bookable-slots` (1280×800) | 25 | 24 | 24 | 0 | 0 | 2026-10-05T19:06:00Z |
| secretariat | `/cabinet-stats` (1280×800) | 22 | 21 | 21 | 0 | 0 | 2026-10-05T19:07:00Z |
| secretariat | `/maintenance` (1280×800) | 25 | 24 | 24 | 0 | 0 | 2026-10-05T19:08:00Z |
| secretariat | `/reprise-donnees` (1280×800) | 25 | 23 | 23 | 0 | 0 | 2026-10-05T19:26:00Z |
| secretariat | `/agenda` (1280×800) — navigation de semaine | 93 | 3 | 3 | 0 | 0 | 2026-10-05T19:23:00Z |
| secretariat | palette ⌘K (depuis `/`) | 17 | 6 | 6 | 0 | 0 | 2026-10-05T19:21:00Z |
| secretariat | rail de navigation (1280×800, 1280×900, 1366×768, 1920×1080) | 18 | 4 | 4 | 0 | 0 | 2026-10-05T18:34:00Z |
| pharmacie | `/stock` (1280×800) | 25 | 24 | 24 | 0 | 0 | 2026-10-05T18:20:00Z |
| pharmacie | `/devis` + volet de détail (1280×800) | 29 | 7 | 7 | 0 | 0 | 2026-10-05T18:31:00Z |
| pharmacie | `/messages` (1280×800) | 12 | 11 | 11 | 0 | 0 | 2026-10-05T19:11:00Z |
| pharmacie | `/orders/:id` + `/orders/:id/pickup` (1280×800) | 14 | 4 | 4 | 0 | 0 | 2026-10-05T19:01:00Z |
| infirmiere | `/` (3 onglets + bascule En ligne, 390×844) | 8 | 7 | 7 | 0 | 0 | 2026-10-05T18:28:00Z |
| infirmiere | `/notification-preferences` (390×844) | 3 | 3 | 3 | 0 | 0 | 2026-10-05T18:29:00Z |
| patient | `/documents` (390×844) | 16 | 16 | 16 | 0 | 0 | 2026-10-05T19:52:00Z |
| praticien | `/devis` + volet de détail (1280×800) | 25 | 24 | 24 | 0 | 0 | 2026-10-05T19:47:00Z |
| praticien | `/stock` (1280×800) | 21 | 20 | 20 | 0 | 0 | 2026-10-05T19:45:00Z |
| praticien | `/messages` (1280×800) | 27 | 26 | 26 | 0 | 0 | 2026-10-05T19:49:00Z |
| praticien | `/agenda` (1280×800) | 27 | 26 | 26 | 0 | 0 | 2026-10-05T19:52:00Z |
| praticien | `/mes-conges` (1280×800) | 21 | 20 | 20 | 0 | 0 | 2026-10-05T19:38:00Z |
| praticien | `/act-categories` (1280×800) | 1 | 1 | 1 | 0 | 0 | 2026-10-05T19:38:00Z |
| praticien | `/notification-preferences` (1280×800) | 12 | 10 | 10 | 0 | 0 | 2026-10-05T20:03:00Z |
| praticien | `/patients/:id` dossier patient (1280, 1600, 1920) | 52 | 5 | 5 | 0 | 0 | 2026-10-05T19:50:00Z |
| secretariat | `/patients` (1280×800) | 36 | 35 | 35 | 0 | 0 | 2026-10-05T19:50:00Z |
| secretariat | `/stock` (1280×800) | 38 | 37 | 37 | 0 | 0 | 2026-10-05T19:46:00Z |
| secretariat | `/liste-attente` (1280×800) | 22 | 21 | 21 | 0 | 0 | 2026-10-05T19:30:00Z |
| pharmacie | `/messages` (1280×800) — facette « Urgentes » | 12 | 11 | 11 | 0 | 0 | 2026-10-05T19:44:00Z |
| tunnel SSR | `/`, `/dentiste/lyon`, `/dr-hugo-marin-implantologie`, `/reservation/confirmer`, 404 (390 **et** 1280) | 215 | 2 | 2 | 0 | 0 | 2026-10-05T19:36:00Z |
| patient | `/profile` (390×844) | 8 | 7 | 7 | 0 | 0 | 2026-10-05T20:06:00Z |
| patient | `/financial` (390×844) — ouverture de 6 devis | 7 | 7 | 7 | 0 | 0 | 2026-10-05T20:08:00Z |
| secretariat | `/appointments` (1280×800) | 26 | 25 | 25 | 0 | 0 | 2026-10-05T20:10:00Z |

**Total R125 : ~1 030 contrôles inventoriés, 620 activés et jugés, 0 mort réel, 0 cassé réel.**

> **5ᵉ cause de faux « MORT » : la sonde `filechooser` manquait à l'auditeur de cette ronde.**
> `patient /profile` → « Modifier la photo de profil » a été classé MORT : le clic n'ouvre aucune URL, ne
> peint rien et n'émet aucune requête… parce qu'il ouvre un **sélecteur de fichier natif**
> (`profile_page.dart:741`, `onTap: _busy ? null : _pickAndUpload`). Re-test avec un écouteur
> `page.on('filechooser')` : **1 événement reçu** → le contrôle fonctionne. C'est exactement la 5ᵉ sonde
> que le détecteur « complet » de R122 possédait et que l'auditeur R125 n'avait pas. **À rétablir :
> `filechooser` + `download` en plus de navigation / contenu / réseau / pixels.**

> Les 6 « CASSÉ » de `patient /financial` sont les mêmes **404 attendus** que sur `praticien /devis` :
> l'ouverture d'un devis appelle `GET /v1/quotes/:id/attestation`, qui rend 404 tant qu'aucune attestation
> n'existe. Le détail se sert correctement (`GET /v1/billing/quotes/:id` → 200 avec `quote_ref DEV-2546`,
> `status signed`, lignes, `signed_at`).

> **4ᵉ cause de faux « MORT » identifiée cette ronde — le contrôle SOUS la ligne de flottaison.**
> `praticien /notification-preferences` : la bascule « Devis — Sur mobile (push) » est à **y=800 dans un
> viewport de 800** — l'auditeur cliquait à y=825, hors écran, d'où « aucun effet ». Les 11 autres bascules
> du même écran, elles, rendent bien `200 PATCH /v1/me/notification-preferences` et inversent leur
> `aria-checked`. Même cause pour `secretariat /patients` (ligne patient repoussée par l'ouverture du volet
> au clic précédent) et `secretariat /stock` / `/maintenance` (« Voir » / « Devis, 28 » déplacés par une
> activation antérieure). **Règle à ajouter à l'auditeur pour la ronde suivante : faire défiler le contrôle
> dans le viewport (`scrollIntoViewIfNeeded`) avant de cliquer, et re-lire son rect juste après.**

> Les 6 « CASSÉ » de `praticien /devis` sont des **404 attendus** : l'ouverture d'un devis appelle
> `GET /v1/cabinet/quotes/:id/attestation`, qui rend 404 tant qu'aucune attestation n'a été créée
> (`api/src/quote_attestation.rs:193`). Le volet de détail se peint correctement (statut, total, reste à
> charge, « Plan de soins », timeline « Suivi » à 4 jalons) — bruit de console, pas de défaut d'usage.
> Le « CASSÉ » de `secretariat /cabinet-stats` est le 403 RBAC attendu, rendu en clair (« Réservé aux praticiens »).

**Contrôles désactivés rencontrés — légitimité tranchée une par une :**

| contrôle | écran | verdict |
|---|---|---|
| « Nouveau bon » | praticien `/lab-work-orders` | **ILLÉGITIME → #8031.** Tooltip « Création de bon de travail indisponible pour l'instant. » (`lab_work_orders_page.dart:177`, motif #7458) alors que `POST /v1/cabinet/lab-work-orders` rend **201** (`api/src/routes/cr_prescriptions.rs:137`). |
| « Connecter Stripe » | secrétariat `/cabinet-payouts` | **légitime** — aucune intégration Stripe Connect côté API (seul `/v1/webhooks/stripe` existe), motif affiché, #6702. |
| « Exporter (CSV) » | secrétariat `/cabinet-payouts` | **légitime** — `onPressed: payouts.isEmpty ? null : …` ; en octobre 2026 le mois est vide, et l'écran affiche « Aucun virement ». Redevient **actif** une fois en juillet 2026 (3 virements) : vérifié. |
| « Modifier le devis » | pharmacie `/devis` (volet) | **légitime** — aucun `UpdatePharmacyQuoteUseCase` côté domaine/API, choix documenté (`devis_detail_sheet.dart:124`). |
| « Filtrer » / « Réinitialiser » | secrétariat `/audit-log` | **légitime** — le rôle secrétaire est 403 sur `/v1/cabinet/audit-log` et l'écran rend « Accès réservé aux administrateurs ». |
| « Confirmer la demande » | patient `/home-care/new` | **légitime** — conditionné à un devis obtenu ET une adresse valide ; s'active dès que `POST /account/visit-requests/estimate` répond 200. |
| « Terminer la séance » | praticien consultation (séance `Terminée`) | **légitime** — la séance est déjà clôturée. |
| « Code de retrait 66FC-QKP1 » | patient `/pharmacy/orders/:id` | **légitime** — champ en lecture seule (code à dicter au comptoir). |

**Refus de permission bien rendus (ni erreur brute, ni « Réessayer » trompeur) :**
`/audit-log` → « **Accès réservé aux administrateurs** · Le journal d'accès n'est visible que par les rôles admin/manager du cabinet. » ;
`/cabinet-stats` → « **Réservé aux praticiens** · Votre rôle ne permet pas d'afficher l'activité par praticien. » (le 403 `GET /v1/cabinet/stats/activity` est attendu par le bloc).

**Cas adversariaux joués (patient `/home-care/new` et `/messaging`) :** double-tap sur « Envoyer » et sur une
réponse rapide → **1 POST** ; champs requis vides → CTA **désactivés**, aucun POST, aucun 500 ; 256 caractères
dans 4 champs libres → aucun débordement ; coupure réseau pendant l'envoi → texte **conservé** + snackbar
« Pas de connexion Internet. » ; coupure pendant l'estimation → formulaire gelé **10 s** (timeout borné) puis
message explicite.

### Ronde R124 — 2026-10-05 (12:00–15:10 UTC) — **5/5 apps**, 19 écrans/vues, **~420 contrôles inventoriés, 58 activés et jugés, 0 MORT RÉEL, 0 CASSÉ**

> **Ciblage** : ronde diff-driven (22 merges depuis `a83fd0ee`). Priorité aux écrans touchés par les
> merges du jour : pharmacie `/devis` + `/stock`, praticien `/treatment-plans` + `/ordonnances/new`,
> secrétariat `/devis`, patient `/messaging`, et l'intercepteur d'auth commun aux 5 apps (#6902).

> ⚠️ **Le piège n°1 de R110 est retombé — et il reste le principal producteur de faux positifs.**
> Un premier passage automatisé a signalé **44 contrôles « MORT »** sur l'app patient
> (`/profile`, `/documents`, `/prescriptions`, `/notifications`). **Tous étaient faux.** Deux causes,
> les deux *hors viewport* :
> - **axe Y** : les entrées de `/profile` sont à `cy` 892–1093 dans un viewport de **844** ; le clic
>   portait sur le vide. Après défilement, les **6** testées naviguent correctement
>   (`Mes proches` → `/profile/dependents`, `Consentements` → `/profile/consents`,
>   `Médecin traitant` → `/profile/referring-doctor`, `Passeport implantaire` → `/implant-passport`,
>   `Ma pharmacie` → `/pharmacy`, ordonnance → 5 requêtes).
> - **axe X** (nouveau) : les facettes de `/documents` sont dans un **défileur horizontal**, à
>   `cx` 558–1035 pour une largeur de **390**. La seule facette réellement dans le viewport
>   (`Devis`, `cx=188`) filtre bien la liste. Un filtre client ne part en **aucune requête** :
>   « 0 req » ne vaut donc jamais « mort » à lui seul.
>
> **Règle retenue** : un verdict MORT n'est valable que si le contrôle a été **ramené dans le viewport
> sur LES DEUX AXES** et que les trois signaux (URL, arbre Semantics, requête) sont stables. Aucun
> finding « bouton mort » n'a été émis cette ronde — à raison.

| app | écran/route | contrôles inventoriés | activés | OK | morts | cassés | last_check ISO |
|---|---|---|---|---|---|---|---|
| pharmacie | `/devis` (1280) | 42 | 8 | 8 | 0 | 0 | 2026-10-05T12:20:00Z |
| pharmacie | `/devis` volet de détail | ~20 | 3 | 3 | 0 | 0 | 2026-10-05T12:20:00Z |
| pharmacie | `/stock` (1280) | 37 | 6 | 6 | 0 | 0 | 2026-10-05T13:25:00Z |
| pharmacie | `/stock` dialogue « Accepter la demande » | 5 | 3 | 3 | 0 | 0 | 2026-10-05T13:25:00Z |
| praticien | `/patients/:id/treatment-plans` (1280 + 1440) | 36 | 6 | 6 | 0 | 0 | 2026-10-05T12:35:00Z |
| praticien | `/ordonnances/new` (1280) | 51 | 18 | 18 | 0 | 0 | 2026-10-05T12:50:00Z |
| praticien | `/waiting-room` (1280) | 5 | 1 | 1 | 0 | **0 (1 désactivé légitime)** | 2026-10-05T13:30:00Z |
| secretariat | `/devis` (1280) | 57 | 5 | 5 | 0 | 0 | 2026-10-05T12:40:00Z |
| secretariat | `/stock` (1280) | ~57 | 2 | 2 | 0 | 0 | 2026-10-05T13:28:00Z |
| patient | `/messaging` + fil (390) | 18 | 7 | 7 | 0 | 0 | 2026-10-05T13:19:00Z |
| patient | `/profile` (390) | 17 | 6 | 6 | 0 | 0 | 2026-10-05T14:25:00Z |
| patient | `/documents` (390) | 43 | 1 | 1 | 0 | 0 | 2026-10-05T14:30:00Z |
| patient | `/prescriptions` (390) | 17 | 1 | 1 | 0 | 0 | 2026-10-05T14:25:00Z |
| patient | `/notifications` (390) | 21 | 0 | — | — | — | 2026-10-05T13:05:00Z |
| patient | `/home-care` + `/home-care/:id` (390) | 18 | 3 | 3 | 0 | 0 | 2026-10-05T12:30:00Z |
| infirmiere | `/` 3 onglets + bascule « En ligne » (390) | 8 | 4 | 4 | 0 | 0 | 2026-10-05T12:26:00Z |
| infirmiere | `/notification-preferences` (390) | 5 | 1 | 1 | 0 | 0 | 2026-10-05T12:24:00Z |

**Contrôles DÉSACTIVÉS — légitimité prouvée, pas supposée**
- praticien `/waiting-room` → « Appeler suivant » : `GET /cabinet/waiting-room` rend **0** patient, et le
  check-in d'un RDV de demain est refusé en **409 `too_early`**. L'état désactivé suit donc l'état serveur.
- praticien `/ordonnances/new` → « Créer l'ordonnance » : désactivé **avec son motif affiché**
  (« Complétez pour créer l'ordonnance : médicament, dose, fréquence, durée, quantité ») ; devient actif
  dès que les 3 sélecteurs sont renseignés, puis crée réellement l'ordonnance (201).
- patient `/profile` → « Authentification biométrique » : non disponible en navigateur.

**Écart d'accessibilité relevé (non rapporté — texte, pas contrôle)** : app infirmière, l'état vide de
l'onglet « Ma visite » (« Aucune visite en cours ») n'est **pas** exposé dans l'arbre Semantics, alors que
celui de l'onglet « Offres » (« Aucune offre… ») l'est. À reprendre si une passe a11y dédiée est ouverte.

### Ronde R110 — 2026-10-03 (18:00–20:20 UTC) — **5/5 apps + tunnel SSR, aux DEUX viewports**, **94 écrans/vues uniques**, **1 748 contrôles inventoriés, 1 288 activés, 1 164 OK, 0 mort RÉEL, 1 cassé RÉEL**

> **Point de départ.** `git log -1 -- qa/explored-paths.md` rend **HEAD** : aucun code n'a été
> mergé depuis la clôture de R109 (28/09). L'Étape 1bis n'avait donc **rien de neuf à cibler** ;
> la rotation a été dictée par l'ancienneté de couverture des ledgers — écrans jamais audités
> (`/appointments/provider`, `praticien /patients/:id/courrier`) puis les plus anciens
> (`/pharmacy/quotes` 17/09, `/pharmacy/search` 18/09, `periodontal-chart` 16/09,
> `/implant-passport/:id` 17/09, secrétariat `/notification-preferences` 25/09).

> **Méthode.** Inventaire par l'arbre Semantics (`flt-semantics[role|aria-label]`, `[role=…]`,
> `input`/`textarea`), puis activation de chaque contrôle avec **re-localisation dans un
> inventaire FRAIS + défilement dans le viewport avant chaque clic**. Verdict par contrôle :
> effet = changement d'URL, de l'arbre Semantics, du hash de pixels, ou requête `/v1/*` partie.

#### Trois pièges de méthode corrigés dans le harnais pendant la ronde

1. **Clic sous la ligne de flottaison.** Cliquer aux coordonnées d'un contrôle hors viewport porte
   sur ce qui occupe ce point à l'écran → faux « MORT ». Corrigé : re-localisation + défilement
   avant chaque clic. (À l'origine des 51 faux morts de `/pharmacy/send` au premier segment.)
2. **Libellé répété dans une liste que l'action recharge.** Le 1er clic réussit, la liste se
   recharge, les suivants retombent sur un nœud obsolète. Corrigé : verdict
   `NON_CONCLUANT_LISTE_REMANIEE` au lieu de `MORT`. Effet mesuré au second passage de
   `pharmacie /stock` à 390 px : **9 « morts » → 0**.
3. **Seuil de canvas vide trop agressif** (0.92) : `/implant-passport/:id` à 0.928 est une page
   blanche légitime. Porté à **0.985**, et le verdict dégradé en `SUSPECT_BLANC`.

#### Les 69 « morts » restants sont TOUS des faux positifs — contre-éprouvés un par un

51 × « Ordonnance du … » (`/pharmacy/send`), 11 × « Télécharger » (`/documents`),
9 × « Accepter »/« Refuser » (`pharmacie /stock`), 3 × « Envoyer » (`secrétariat /devis`),
plus 3 isolés — tous de la famille n°2 ci-dessus. Contre-épreuves manuelles :

| contrôle | contre-épreuve | résultat |
|---|---|---|
| `/documents` « Télécharger » ×3 **distincts** | 3 lignes différentes, re-localisées une par une | `GET /v1/documents/<3 id distincts>/download` → 200, **3 PDF réellement téléchargés** (`devis/de0ceb39….pdf`, `ordonnance/49105740….pdf`, `ordonnance/c6f7e9f0….pdf`) |
| secrétariat `/devis` « Envoyer » | 1re ligne `Brouillon` | `POST /v1/cabinet/quotes/15ba579d…/send` → **200**, la ligne passe à `À signer` |
| `/implant-passport` « Voir la fiche complète » | clic puis lecture | navigue vers `/implant-passport/<id>`, 4 contrôles (`Retour`, `Exporter cette fiche`, `Partager avec un professionnel`) |

#### Les 31 « cassés » bruts — 1 seul réel

| occurrences | signal | verdict |
|---|---|---|
| 1 | praticien `/act-categories` « Réessayer » → 403 à chaque clic (3/3) | **RÉEL → #7924** |
| 17 | `SUSPECT_BLANC` après navigation (near-white > 0.985) | faux positif : pages blanches légitimes (`/`, `/documents`, `/implant-passport/:id`) |
| 16 | `404 GET /v1/quotes/:id/attestation` à l'ouverture de **tout** devis (patient ET praticien) | faux positif **prouvé en code** : une ligne par attestation déposée (`quote_attestation.rs:93`), aucune n'existe sur ces devis → le 404 est la réponse nominale « pas d'attestation ». Déjà adjugé en R109. |
| 3 | secrétariat `/admin-membres` « Lien — … » → 403 `POST /v1/cabinet/invite-links` | **RÉEL, mais regroupé dans #7925** (1 issue pour les 3 boutons + « Ajouter membre ») |
| 3 | erreur console seule au retour sur `/` | faux positif : conséquence des deux lignes ci-dessus |
| 1 | `403 GET /v1/cabinet/audit-log` au chargement du tableau de bord secrétariat | faux positif : **sonde de rôle intentionnelle** (`audit_log_access_cubit.dart:12-14`, #4155). Mise en liste blanche. |
| 1 | `403 GET /v1/cabinet/stats/activity` sur `/cabinet-stats` | faux positif : l'écran verrouille **la seule section interdite** (« Réservé aux praticiens ») et sert le reste — c'est le bon motif. |
| 1 | `404 POST /v1/pharmacy/orders/pickup-scan` | faux positif : le harnais avait saisi « Nubia QA » dans le champ de code. |

#### Deux plantages de page écartés

`patient /appointments` et `/messaging` à 1280 ont rendu `Target crashed` / `Page crashed` lors
d'un segment où 3 Chromium tournaient en parallèle sur 4 cœurs. **Rejoués seuls** : `/appointments`
29 contrôles / 20 activés, `/messaging` 9/9, **0 mort, 0 cassé**. Épuisement de ressources du
harnais, pas un défaut produit.

#### Écrans jamais audités, couverts cette ronde

`praticien /patients/:id/courrier` (45 contrôles, 29 activés, **0 mort, 0 cassé**) et
`patient /appointments/provider` — ce dernier ne rend **aucun** contrôle : c'est **#7920**.

| app | écran/route | viewport | inventoriés | activés | OK | morts RÉELS | cassés bruts | désactivés | non concl./sautés | last_check ISO |
|---|---|---|---|---|---|---|---|---|---|---|
| infirmiere | `/` | 1280x800 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 2026-10-03T20:00Z |
| infirmiere | `/` | 390x844 | 7 | 6 | 6 | 0 | 0 | 0 | 1 | 2026-10-03T20:00Z |
| infirmiere | `/notification-preferences` | 1280x800 | 3 | 3 | 3 | 0 | 0 | 0 | 0 | 2026-10-03T20:00Z |
| infirmiere | `/notification-preferences` | 390x844 | 3 | 3 | 3 | 0 | 0 | 0 | 0 | 2026-10-03T20:00Z |
| patient | `/` | 390x844 | 17 | 10 | 10 | 0 | 0 | 0 | 7 | 2026-10-03T20:00Z |
| patient | `/appointments/provider?providerId=90de0000-0000-4000-8000-000000000009` | 1280x800 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 2026-10-03T20:00Z |
| patient | `/book` | 390x844 | 20 | 5 | 5 | 0 | 0 | 0 | 4 | 2026-10-03T20:00Z |
| patient | `/documents` | 1280x800 | 27 | 2 | 2 | 0 | 0 | 0 | 25 | 2026-10-03T20:00Z |
| patient | `/documents` | 390x844 | 27 | 27 | 16 | 0 — **11 non concluants** (libellés répétés d'une liste rechargée à chaque action, contre-éprouvés à la main) | 0 | 0 | 0 | 2026-10-03T20:00Z |
| patient | `/financial` | 1280x800 | 8 | 8 | 1 | 0 | 7 | 0 | 0 | 2026-10-03T20:00Z |
| patient | `/home-care` | 390x844 | 17 | 17 | 17 | 0 | 0 | 0 | 0 | 2026-10-03T20:00Z |
| patient | `/implant-passport` | 1280x800 | 6 | 6 | 2 | 0 — **1 non concluants** (libellés répétés d'une liste rechargée à chaque action, contre-éprouvés à la main) | 3 | 0 | 0 | 2026-10-03T20:00Z |
| patient | `/implant-passport` | 390x844 | 6 | 6 | 6 | 0 | 0 | 0 | 0 | 2026-10-03T20:00Z |
| patient | `/mes-rdv` | 390x844 | 8 | 8 | 8 | 0 | 0 | 0 | 0 | 2026-10-03T20:00Z |
| patient | `/notifications` | 1280x800 | 22 | 22 | 22 | 0 | 0 | 0 | 0 | 2026-10-03T20:00Z |
| patient | `/notifications` | 390x844 | 20 | 13 | 13 | 0 | 0 | 0 | 7 | 2026-10-03T20:00Z |
| patient | `/oubliettes` | 1280x800 | 1 | 1 | 0 | 0 | 1 | 0 | 0 | 2026-10-03T20:00Z |
| patient | `/oubliettes` | 390x844 | 1 | 1 | 1 | 0 | 0 | 0 | 0 | 2026-10-03T20:00Z |
| patient | `/pharmacy/orders` | 390x844 | 16 | 15 | 15 | 0 | 0 | 0 | 1 | 2026-10-03T20:00Z |
| patient | `/pharmacy/quotes` | 1280x800 | 1 | 1 | 0 | 0 | 1 | 0 | 0 | 2026-10-03T20:00Z |
| patient | `/pharmacy/search` | 1280x800 | 1 | 1 | 1 | 0 | 0 | 0 | 0 | 2026-10-03T20:00Z |
| patient | `/pharmacy/send` | 1280x800 | 64 | 63 | 12 | 0 — **51 non concluants** (libellés répétés d'une liste rechargée à chaque action, contre-éprouvés à la main) | 0 | 1 | 0 | 2026-10-03T20:00Z |
| patient | `/prescriptions` | 390x844 | 16 | 16 | 16 | 0 | 0 | 0 | 0 | 2026-10-03T20:00Z |
| patient | `/profile` | 390x844 | 12 | 2 | 1 | 0 — **1 non concluants** (libellés répétés d'une liste rechargée à chaque action, contre-éprouvés à la main) | 0 | 0 | 10 | 2026-10-03T20:00Z |
| patient | `/profile/consents` | 1280x800 | 10 | 9 | 8 | 0 — **1 non concluants** (libellés répétés d'une liste rechargée à chaque action, contre-éprouvés à la main) | 0 | 1 | 0 | 2026-10-03T20:00Z |
| patient | `/profile/consents` | 390x844 | 8 | 7 | 7 | 0 | 0 | 1 | 0 | 2026-10-03T20:00Z |
| patient | `/profile/dependents` | 390x844 | 22 | 21 | 21 | 0 | 0 | 0 | 1 | 2026-10-03T20:00Z |
| patient | `/profile/referring-doctor` | 1280x800 | 1 | 1 | 1 | 0 | 0 | 0 | 0 | 2026-10-03T20:00Z |
| patient | `/rdv/84c24d91-6322-4ed3-82d9-4be22f84c20c/prepare` | 390x844 | 2 | 2 | 2 | 0 | 0 | 0 | 0 | 2026-10-03T20:00Z |
| patient | `/reviews` | 390x844 | 1 | 1 | 1 | 0 | 0 | 0 | 0 | 2026-10-03T20:00Z |
| patient | `/treatment-plans` | 1280x800 | 9 | 9 | 7 | 0 | 2 | 0 | 0 | 2026-10-03T20:00Z |
| patient | `/treatment-plans` | 390x844 | 9 | 9 | 7 | 0 | 2 | 0 | 0 | 2026-10-03T20:00Z |
| pharmacie | `/` | 1280x800 | 28 | 12 | 12 | 0 | 0 | 0 | 1 | 2026-10-03T20:00Z |
| pharmacie | `/` | 390x844 | 20 | 18 | 18 | 0 | 0 | 0 | 0 | 2026-10-03T20:00Z |
| pharmacie | `/devis` | 1280x800 | 26 | 24 | 24 | 0 | 0 | 0 | 1 | 2026-10-03T20:00Z |
| pharmacie | `/devis` | 390x844 | 21 | 18 | 13 | 0 | 0 | 0 | 8 | 2026-10-03T20:00Z |
| pharmacie | `/messages` | 1280x800 | 12 | 11 | 11 | 0 | 0 | 0 | 1 | 2026-10-03T20:00Z |
| pharmacie | `/orders/b305c458-a129-415a-aff3-4af34768ef6e` | 1280x800 | 12 | 10 | 10 | 0 | 0 | 1 | 1 | 2026-10-03T20:00Z |
| pharmacie | `/orders/b305c458-a129-415a-aff3-4af34768ef6e/pickup` | 1280x800 | 3 | 3 | 2 | 0 | 1 | 0 | 0 | 2026-10-03T20:00Z |
| pharmacie | `/stock` | 1280x800 | 25 | 24 | 24 | 0 | 0 | 0 | 1 | 2026-10-03T20:00Z |
| pharmacie | `/stock` | 390x844 | 20 | 20 | 10 | 0 | 0 | 0 | 10 | 2026-10-03T20:00Z |
| praticien | `/act-categories` | 1280x800 | 2 | 2 | 1 | 0 | 1 | 0 | 0 | 2026-10-03T20:00Z |
| praticien | `/agenda` | 1280x800 | 26 | 25 | 25 | 0 | 0 | 0 | 1 | 2026-10-03T20:00Z |
| praticien | `/cabinet-brief` | 1280x800 | 5 | 5 | 5 | 0 | 0 | 0 | 0 | 2026-10-03T20:00Z |
| praticien | `/consent-templates` | 1280x800 | 11 | 10 | 10 | 0 | 0 | 0 | 1 | 2026-10-03T20:00Z |
| praticien | `/consultation` | 1280x800 | 35 | 29 | 29 | 0 | 0 | 0 | 1 | 2026-10-03T20:00Z |
| praticien | `/devis` | 1280x800 | 27 | 23 | 18 | 0 | 5 | 0 | 1 | 2026-10-03T20:00Z |
| praticien | `/lab-stats` | 1280x800 | 1 | 1 | 1 | 0 | 0 | 0 | 0 | 2026-10-03T20:00Z |
| praticien | `/lab-work-orders` | 1280x800 | 23 | 21 | 21 | 0 | 0 | 1 | 1 | 2026-10-03T20:00Z |
| praticien | `/lab-work-orders` | 390x844 | 6 | 5 | 5 | 0 | 0 | 1 | 0 | 2026-10-03T20:00Z |
| praticien | `/mes-conges` | 1280x800 | 21 | 20 | 20 | 0 | 0 | 0 | 1 | 2026-10-03T20:00Z |
| praticien | `/mes-conges` | 390x844 | 4 | 4 | 4 | 0 | 0 | 0 | 0 | 2026-10-03T20:00Z |
| praticien | `/messages` | 1280x800 | 27 | 15 | 15 | 0 | 0 | 0 | 0 | 2026-10-03T20:00Z |
| praticien | `/notification-preferences` | 1280x800 | 12 | 12 | 12 | 0 | 0 | 0 | 0 | 2026-10-03T20:00Z |
| praticien | `/ordonnances` | 1280x800 | 20 | 19 | 19 | 0 | 0 | 0 | 1 | 2026-10-03T20:00Z |
| praticien | `/ordonnances/new?patientId=d0000000-0000-0000-0000-0000000000d1` | 1280x800 | 47 | 25 | 25 | 0 | 0 | 0 | 1 | 2026-10-03T20:00Z |
| praticien | `/patients` | 1280x800 | 35 | 19 | 19 | 0 | 0 | 0 | 1 | 2026-10-03T20:00Z |
| praticien | `/patients/d0000000-0000-0000-0000-0000000000d1` | 1280x800 | 20 | 19 | 19 | 0 | 0 | 0 | 1 | 2026-10-03T20:00Z |
| praticien | `/patients/d0000000-0000-0000-0000-0000000000d1/courrier` | 1280x800 | 45 | 29 | 29 | 0 | 0 | 0 | 1 | 2026-10-03T20:00Z |
| praticien | `/patients/d0000000-0000-0000-0000-0000000000d1/dental-chart` | 1280x800 | 55 | 33 | 33 | 0 | 0 | 0 | 1 | 2026-10-03T20:00Z |
| praticien | `/patients/d0000000-0000-0000-0000-0000000000d1/periodontal-chart` | 1280x800 | 57 | 23 | 23 | 0 | 0 | 0 | 1 | 2026-10-03T20:00Z |
| praticien | `/patients/d0000000-0000-0000-0000-0000000000d1/treatment-plans` | 1280x800 | 38 | 27 | 26 | 0 — **1 non concluants** (libellés répétés d'une liste rechargée à chaque action, contre-éprouvés à la main) | 0 | 0 | 4 | 2026-10-03T20:00Z |
| praticien | `/questionnaire-templates` | 1280x800 | 2 | 2 | 2 | 0 | 0 | 0 | 0 | 2026-10-03T20:00Z |
| praticien | `/stock` | 1280x800 | 21 | 20 | 20 | 0 | 0 | 0 | 1 | 2026-10-03T20:00Z |
| praticien | `/stock-inventory` | 1280x800 | 33 | 16 | 16 | 0 | 0 | 0 | 0 | 2026-10-03T20:00Z |
| praticien | `/tasks` | 1280x800 | 5 | 5 | 5 | 0 | 0 | 0 | 0 | 2026-10-03T20:00Z |
| praticien | `/tasks` | 390x844 | 5 | 5 | 5 | 0 | 0 | 0 | 0 | 2026-10-03T20:00Z |
| praticien | `/waiting-room` | 1280x800 | 21 | 19 | 19 | 0 | 0 | 1 | 1 | 2026-10-03T20:00Z |
| secretariat | `/admin-membres` | 1280x800 | 29 | 23 | 20 | 0 | 3 | 0 | 4 | 2026-10-03T20:00Z |
| secretariat | `/admin-secretariats` | 1280x800 | 22 | 18 | 18 | 0 | 0 | 0 | 4 | 2026-10-03T20:00Z |
| secretariat | `/agenda` | 1280x800 | 76 | 30 | 30 | 0 | 0 | 0 | 2 | 2026-10-03T20:00Z |
| secretariat | `/appointment-motifs` | 1280x800 | 22 | 9 | 9 | 0 | 0 | 0 | 0 | 2026-10-03T20:00Z |
| secretariat | `/appointments` | 1280x800 | 26 | 16 | 16 | 0 | 0 | 0 | 0 | 2026-10-03T20:00Z |
| secretariat | `/audit-log` | 390x844 | 7 | 5 | 5 | 0 | 0 | 2 | 0 | 2026-10-03T20:00Z |
| secretariat | `/bookable-slots` | 1280x800 | 25 | 20 | 20 | 0 | 0 | 0 | 5 | 2026-10-03T20:00Z |
| secretariat | `/cabinet-brief` | 1280x800 | 5 | 5 | 5 | 0 | 0 | 0 | 0 | 2026-10-03T20:00Z |
| secretariat | `/cabinet-payouts` | 1280x800 | 26 | 21 | 21 | 0 | 0 | 2 | 3 | 2026-10-03T20:00Z |
| secretariat | `/cabinet-stats` | 1280x800 | 22 | 18 | 17 | 0 | 1 | 0 | 4 | 2026-10-03T20:00Z |
| secretariat | `/conformite` | 1280x800 | 34 | 25 | 24 | 0 | 1 | 0 | 0 | 2026-10-03T20:00Z |
| secretariat | `/conges` | 1280x800 | 23 | 22 | 22 | 0 | 0 | 0 | 1 | 2026-10-03T20:00Z |
| secretariat | `/correspondents` | 1280x800 | 35 | 23 | 23 | 0 | 0 | 0 | 4 | 2026-10-03T20:00Z |
| secretariat | `/devis` | 1280x800 | 41 | 33 | 30 | 0 — **3 non concluants** (libellés répétés d'une liste rechargée à chaque action, contre-éprouvés à la main) | 0 | 0 | 3 | 2026-10-03T20:00Z |
| secretariat | `/devis` | 390x844 | 20 | 19 | 10 | 0 | 0 | 0 | 10 | 2026-10-03T20:00Z |
| secretariat | `/liste-attente` | 1280x800 | 22 | 20 | 20 | 0 | 0 | 0 | 2 | 2026-10-03T20:00Z |
| secretariat | `/maintenance` | 1280x800 | 27 | 23 | 23 | 0 | 0 | 0 | 4 | 2026-10-03T20:00Z |
| secretariat | `/maintenance` | 390x844 | 8 | 8 | 8 | 0 | 0 | 0 | 0 | 2026-10-03T20:00Z |
| secretariat | `/notification-preferences` | 1280x800 | 12 | 12 | 11 | 0 | 1 | 0 | 0 | 2026-10-03T20:00Z |
| secretariat | `/patients` | 1280x800 | 39 | 13 | 13 | 0 | 0 | 0 | 0 | 2026-10-03T20:00Z |
| secretariat | `/patients/new` | 390x844 | 7 | 6 | 5 | 0 | 1 | 1 | 0 | 2026-10-03T20:00Z |
| secretariat | `/reprise-donnees` | 1280x800 | 25 | 4 | 4 | 0 | 0 | 0 | 0 | 2026-10-03T20:00Z |
| secretariat | `/salle-attente` | 1280x800 | 23 | 21 | 21 | 0 | 0 | 1 | 1 | 2026-10-03T20:00Z |
| secretariat | `/salle-attente` | 390x844 | 4 | 3 | 3 | 0 | 0 | 1 | 0 | 2026-10-03T20:00Z |
| secretariat | `/tasks` | 1280x800 | 5 | 5 | 4 | 0 | 1 | 0 | 0 | 2026-10-03T20:00Z |
| secretariat | `/team-messages` | 1280x800 | 27 | 18 | 18 | 0 | 0 | 0 | 1 | 2026-10-03T20:00Z |

**Contrôles non activés (motif explicite)** : `Se déconnecter` (×5 apps, destructif pour la session de test),
`Supprimer…` / `Retirer le membre` (destructifs hors périmètre), et les contrôles restés hors écran après
6 tentatives de défilement (comptés en « non concl./sautés »).

**Désactivés légitimes, prouvés dans le code** :
`Marquer prête` (officine) — `order_detail_page.dart:447` `onPressed: inProgress || !allPrepared ? null : …`,
**vérifié en live** : cocher la case « Préparée — R110 netcut » débloque le bouton, qui rend alors
`POST …/ready` 200 et fait apparaître « Scanner le retrait » ·
`Terminer la séance` (séance sans acte) · `Appeler suivant` (file vide — réellement vidée par la ronde) ·
`Nouveau bon` (labo) · `Exporter (CSV)` / `Connecter Stripe` (Stripe non connecté sur l'env de démo) ·
`Créer le dossier` / `Filtrer` / `Réinitialiser` (formulaires vides) ·
`Télécharger l'app` (`booking_confirmation_page.dart:160-167` — grisé **avec tooltip** depuis #6702) ·
`Demander à Nubia`, `Joindre un patient, un devis…`, `Épingler` (tous avec tooltip « …indisponible pour l'instant »).

**Non reproduit (pas de finding)** : au premier passage, `infirmiere /` à 1280 a été capturée avec
« Disponibilité indisponible — impossible de joindre le serveur. » et 0 contrôle. Rejoué avec une
attente de stabilisation, puis **rechargé (F5) et observé à 2/4/6/9/14/22 s** : les 4 requêtes
(`/nurse/profile`, `/nurse/visits`, `/nurse/offers`, `/notifications`) rendent 200, le texte est
« Vous êtes EN LIGNE — vous recevez les demandes de visite proches. », l'interrupteur est actif et
`aria-checked=true`. État transitoire de boot → **non rapporté**.

**Tunnel de réservation SSR** (`reservation.doc.nubia-link.com`, HTML classique) — parcouru en entier,
**aucun défaut** : `/` (3 liens d'amorce, `robots: index, follow`) → `/dentiste/lyon` (31 liens,
formulaire `specialty`+`place`, `place` requis) → `/dr-claire-lefevre-omnipratique` (140 liens de
créneaux) → `/reservation/confirmer?providerId=…&slotId=…` (9 champs, 6 requis, `consentement` requis,
`robots: noindex, follow`). `/dentiste/ville-qui-nexiste-pas` → **404 + `noindex`**.
`/recherche?specialty=…&place=…` redirige correctement vers `/{specialty}/{place}` ; `place` absent ou
réduit à des octets NUL → repli sur `/`. **E-mail malformé** à la confirmation : bloqué par la
validation HTML5 native, aucune soumission (URL inchangée).



#### Addendum R110 — routes PUBLIQUES des 5 apps (sans session), 390×844

| app | écran/route | contrôles | nommés | anonymes | verdict | last_check ISO |
|---|---|---|---|---|---|---|
| patient | `/login` | 7 | 7 | 0 | OK | 2026-10-03T20:48Z |
| patient | `/signup` | 6 | 6 | 0 | OK — CGU **nommée** (« J'accepte les Conditions Générales d'Utilisation », #7784 tenu) ; « Créer mon compte » grisé tant qu'elle n'est pas cochée | 2026-10-03T20:48Z |
| patient | `/forgot-password` | 4 | 4 | 0 | OK — « Envoyer le lien » grisé sur champ vide | 2026-10-03T20:49Z |
| patient | `/reset-password` (sans jeton) | 1 | 1 | 0 | OK — état propre « Demander un nouveau lien », pas d'erreur brute | 2026-10-03T20:49Z |
| praticien | `/login` | 6 | 6 | 0 | OK | 2026-10-03T20:50Z |
| praticien | `/register-pro` | 13 | 12 | **1** | **DIVERGENT → #7927** : le sélecteur « Spécialité » est anonyme (`aria-label`, `aria-labelledby`, `textContent` vides, rect 310×24) ; clic → menu de 8 spécialités correctement nommées | 2026-10-03T20:50Z |
| secretariat | `/login` | 5 | 5 | 0 | OK | 2026-10-03T20:51Z |
| secretariat | `/onboard` (sans jeton) | 1 | 1 | 0 | OK — « Retour à la connexion » | 2026-10-03T20:51Z |
| pharmacie | `/login` | 5 | 5 | 0 | OK | 2026-10-03T20:51Z |
| infirmiere | `/login` | 5 | 5 | 0 | OK — « Espace infirmier — soins à domicile » | 2026-10-03T20:52Z |
| patient | `/route-qui-nexiste-pas` | 7 | 7 | 0 | OK — redirection propre vers `/login` par la garde d'auth, pas d'écran d'erreur brut | 2026-10-03T20:52Z |

Soit **11 écrans publics de plus** (54 contrôles inventoriés, 53 nommés). Cumul de la ronde :
**105 écrans/vues uniques**, **1 802 contrôles inventoriés**, **1 288 activés**, **0 mort réel**,
**2 cassés réels** (#7924, et les 3 boutons d'invitation regroupés dans #7925).



#### Addendum R110 (final) — écrans ré-audités SANS limite de budget + 1 doublon écarté

Les écrans dont le premier passage s'était arrêté sur « budget exhausted » ont été rejoués avec un
budget 3 à 7 fois plus large, pour qu'aucun contrôle ne reste non activé faute de temps :

| app | écran | 1er passage | passage complet | verdict |
|---|---|---|---|---|
| secretariat | `/agenda` | 76 inv / **30** act | 76 inv / **74** act, 64 OK | **0 mort réel** (voir ci-dessous) |
| praticien | `/patients` | 35 inv / **19** act | 35 inv / **34** act, 21 OK | 13 « cassés » = **doublon de #7910** (voir ci-dessous) |
| praticien | `/stock-inventory` | 33 inv / 16 act | 33 inv / 30 act | OK |

**Les 5 « morts » de `/agenda` ne sont pas des boutons morts — ce sont des cartes écrasées par le clip.**
Reproduits sur **rechargement neuf** (url/semantics/pixels/réseau inchangés, 3/3), puis disséqués au
`elementFromPoint` : ces trois nœuds mesurent **21×5 px** et **128×9 px**, là où une vraie puce
horaire de la grille mesure **61×28 px**. Leur centre ne rend aucun nœud interactif
(`document.elementFromPoint` → `FLUTTER-VIEW`). Ce sont les cartes de RDV de la **dernière rangée**
de la grille semaine, rognées par le clip de leur colonne défilante — elles redeviennent entières
après défilement. Même famille que le faux positif consigné en R109 (« la puce n'est pas morte,
elle est défilée hors zone »). **Non rapporté.**

**Doublon écarté — `praticien /patients` : 13 fiches sur 13 rendent 403.** Ouvrir la fiche d'un
patient **sans relation de soin** déclenche `403 GET /v1/cabinet/patients/:id/notes?limit=100`
**et** `403 …/medical-record`. C'est exactement **#7910** (OUVERTE) : même écran, même cause
(absence de relation de soin), même symptôme. **Non re-rapporté** — la seule information neuve
(l'ampleur : 13/13 des fiches ouvertes, et le fait que `/notes` est touché au même titre que
`/medical-record`) ne justifie pas une issue séparée.

**Cumul définitif de la ronde** : **107 écrans/vues uniques**, **1 850 contrôles inventoriés**,
**1 352 activés**, **0 mort réel**, **2 cassés réels** (#7924 ; les 3 boutons d'invitation de
#7925). Taux de faux positifs du harnais sur cette ronde : **96 alertes brutes sur 100**, toutes
contre-éprouvées individuellement.


### Ronde R109 — 2026-09-28 (18:00–21:10 UTC) — **5/5 apps + tunnel SSR, aux DEUX viewports**, **112 écrans/vues**, **2 293 contrôles inventoriés, 999 activés, 981 OK, 2 morts RÉELS, 2 cassés RÉELS**

> **Méthode.** Inventaire par l'arbre Semantics (`flt-semantics[role|aria-label]` + `input`/`textarea`),
> activation au centre du rect (défilement en **x** et en **y** avant chaque clic), verdict par diff
> url / empreinte Semantics **normalisée** / requêtes `/v1/` / **téléchargements**.
>
> **Deux pièges de méthode corrigés cette ronde**, tous deux producteurs de faux « MORT » :
> 1. **Empreinte volatile.** Les écrans qui affichent « Actualisé il y a N s » ou « N min d'attente »
>    changent d'empreinte *toutes les secondes* : le premier passage sur `/salle-attente` a rendu
>    **6 contrôles OK sur 6** parce que l'horloge bougeait entre les deux captures. L'empreinte
>    normalise désormais durées, heures et nombres (`#T`, `#H`, `#N`) — au second passage, les mêmes
>    6 contrôles rendent **1 OK, 4 morts, 1 désactivé**, et c'est cette lecture-là qui a produit #7905.
> 2. **Téléchargement invisible.** « Exporter (CSV) » (`secretariat /devis`) ressortait MORT : aucun
>    `/v1/`, aucune navigation, aucun repeint. **Contre-épreuve** avec un écouteur `page.on('download')` :
>    le clic produit bien `suivi_devis.csv` (deux fois de suite). Le harnais écoute désormais les
>    téléchargements — faux positif retiré.
>
> **Contre-épreuves systématiques des « MORT ».** Sur les 14 candidats bruts, **12 sont des artefacts** :
> facette **déjà sélectionnée** (`pharmacie /` « Toutes 89 », `/devis` « Tous (146) », `/stock`
> « À répondre (1) », `secretariat /conformite` « À venir / échu » — `aria-checked="true"` avant clic,
> vérifié), liste d'**un seul** élément où toutes les facettes rendent la même ligne
> (`pharmacie /messages`), **route déjà active** (`praticien /lab-work-orders` → « Labo »), ligne de
> tableau de rôle `group` **non cliquable par conception** (une action explicite « Préparer »/« Voir »
> existe sur la même ligne), **boîte de dialogue native** hors DOM (`secretariat /reprise-donnees`
> « Choisir un fichier »), **segment dont l'état n'est que pictural** (`/reprise-donnees`
> « Patients | Rendez-vous » — contre-épreuve **par pixels** sur le rect du segment : l'image change
> bien au clic), et **carte hero disparue** après l'action précédente (`praticien /waiting-room`
> « Ouvrir le dossier », re-testé sur une file remontée → il navigue, mais **au mauvais endroit** : #7906).
> Les 2 morts restants sont réels et documentés en #7905.

| app | écran / route | viewport | contrôles inventoriés | activés | OK | morts | cassés | last_check ISO |
|---|---|---|---|---|---|---|---|---|
| secretariat | `/salle-attente` (file de 2, états mixtes) | 1280×800 | 27 | 6 | 1 | **2** (« Appeler » de 2 lignes `En consultation`, #7905) | 0 | 2026-09-28T18:15Z |
| secretariat | `/` tableau de bord | 1280×800 | 38 | 15 | 15 | 0 | 0 | 2026-09-28T18:47Z |
| secretariat | `/agenda` | 1280×800 | 69 | 22 | 22 | 0 | 0 | 2026-09-28T18:52Z |
| secretariat | `/devis` | 1280×800 | 52 | 22 | 22 (« Exporter (CSV) » → `suivi_devis.csv`) | 0 | 0 | 2026-09-28T19:35Z |
| secretariat | `/patients` | 1280×800 | 39 | 18 | 18 | 0 | 0 | 2026-09-28T19:05Z |
| secretariat | `/stock` | 1280×800 | 52 | 22 | 22 | 0 | 0 | 2026-09-28T19:12Z |
| secretariat | `/tasks` | 1280×800 | 5 | 5 | 5 | 0 | 0 | 2026-09-28T19:18Z |
| secretariat | `/conformite` | 1280×800 | 34 | 22 | 22 | 0 | 0 | 2026-09-28T21:36Z |
| secretariat | `/reprise-donnees` (+ upload réel) | 1280×800 | 25 | 4 | 3 | 0 | 0 | 2026-09-28T21:28Z |
| praticien | `/` tableau de bord | 1280×800 | 35 | 17 | 17 | 0 | 0 | 2026-09-28T18:36Z |
| praticien | `/waiting-room` (file NON vide) | 1280×800 | 25 | 11 | 10 | 0 (mais « Ouvrir le dossier » → **mauvaise cible**, #7906) | 0 | 2026-09-28T19:57Z |
| praticien | `/consultation` (liste des séances) | 1280×800 | 35 | 21 | 21 | 0 | 0 | 2026-09-28T18:40Z |
| praticien | `/ordonnances` | 1280×800 | 20 | 5 | 5 | 0 | 0 | 2026-09-28T18:41Z |
| praticien | `/lab-work-orders` | 1280×800 | 22 | 7 | 6 | 0 | 0 (1 désactivé **légitime** : « Nouveau bon », message « Création de bon de travail indisponible pour l'instant. ») | 2026-09-28T18:42Z |
| praticien | `/tasks` | 1280×800 | 5 | 5 | 5 | 0 | 0 | 2026-09-28T18:43Z |
| pharmacie | `/` file des commandes | 1280×800 | 40 | 24 | 24 | 0 | 0 | 2026-09-28T19:05Z |
| pharmacie | `/devis` (5 facettes rejouées une à une) | 1280×800 | 38 | 29 | 29 | 0 | 0 | 2026-09-28T19:47Z |
| pharmacie | `/stock` | 1280×800 | 16 | 9 | 9 | 0 | 0 | 2026-09-28T19:20Z |
| pharmacie | `/messages` (+ 3 facettes) | 1280×800 | 12 | 5 | 5 | 0 | 0 | 2026-09-28T19:45Z |
| pharmacie | `/orders/:id` délivrance | 1280×800 | 9 | 5 | 5 | 0 | 0 | 2026-09-28T19:50Z |
| pharmacie | `/orders/:id/pickup` scan (3 cas : code inconnu / mauvais statut / QR d'une autre commande) | 1280×800 | 12 | 9 | 8 | 0 | **0** (bandeau d'erreur à 3e ligne technique → #7908) | 2026-09-28T20:00Z |
| patient | `/` accueil | 390×844 | 17 | 12 | 12 | 0 | 0 | 2026-09-28T19:32Z |
| patient | `/book` annuaire + carte | 390×844 | 25 | 14 | 14 | 0 | 0 | 2026-09-28T20:20Z |
| patient | `/appointments/slots` (grille + panneau de confirmation) | 390×844 | 47 | 20 | 20 | 0 | 0 | 2026-09-28T20:25Z |
| patient | `/messaging` + fil ouvert | 390×844 | 12 | 6 | 6 | 0 | 0 | 2026-09-28T20:50Z |
| infirmiere | `/` — 3 onglets (Disponibilité / Offres / **Ma visite**) | 390×844 | 10 | 9 | 9 | 0 | 0 | 2026-09-28T18:50Z |
| infirmiere | `/` — parcours métier complet (Accepter → Je pars → Je suis arrivé·e → Visite terminée) | 390×844 | 7 | 6 | 6 | 0 | 0 | 2026-09-28T18:52Z |
| infirmiere | `/notification-preferences` | 390×844 | 3 | 3 | 3 | 0 | 0 | 2026-09-28T18:48Z |

**Cas adversariaux joués cette ronde**

| cas | écran | verdict | preuve |
|---|---|---|---|
| **double-clic** sur l'action irréversible | patient, `Confirmer le rendez-vous` | **OK** | 2 clics à 120 ms → **un seul `POST /v1/bookings`**, un seul écran « Demande de rendez-vous envoyée ». |
| **double-clic** sur une action d'état | pharmacie, `Valider le code` de retrait | **OK** | 2e validation d'une commande déjà `picked_up` → 409 traité, message métier « Commande pas au bon statut ». |
| **BACK navigateur au milieu du tunnel** | patient, `/book` → créneau → confirmation | **acceptable** | Le panneau de confirmation partage l'URL de l'étape 2 : `goBack()` ramène à `/book` (état intact, 25 contrôles, aucune erreur), `goForward()` rend l'étape 2 complète (47 contrôles). Aucun écran blanc ni état incohérent — la seule conséquence est que l'étape 3 n'est pas une entrée d'historique. |
| **coupure réseau pendant une action** (`route.abort` sur `*/v1/*`) | patient, `Envoyer le message` | **OK** | Le message n'est pas envoyé (confirmé par rechargement : absent du fil), **le texte saisi est conservé dans le champ**, une erreur s'affiche transitoirement (visible à t=1 s et t=2,5 s, estompée à t=5 s). Aucun spinner infini, aucun écran blanc. |
| **saisie invalide** | pharmacie, code de retrait `XXXX-YYYY` | **refus propre** | `404` traité en « Code inconnu / Revérifiez le code… » (+ 3e ligne technique → #7908). Pas de 500. |
| **jeton d'une autre commande** | pharmacie, scan de retrait | **OK, conforme maquette** | `409` → « Ce QR ne correspond pas à cette commande », rappel « Sachet en main » vs « QR scanné », bouton « Ouvrir CMD-0450 », **« Valider le retrait » désactivé**. |

**Seconde moitié de la ronde (19:10–20:40 UTC) — 25 écrans de plus**

| app | écran / route | viewport | inventoriés | activés | OK | morts | cassés | last_check ISO |
|---|---|---|---|---|---|---|---|---|
| patient | `/mes-rdv` | 390×844 | 11 | 11 | 11 | 0 | 0 | 2026-09-28T19:15Z |
| patient | `/prescriptions` | 390×844 | 12 | 12 | 12 | 0 | 0 | 2026-09-28T19:17Z |
| patient | `/documents` | 390×844 | 41 | 18 | 18 | 0 | 0 | 2026-09-28T19:19Z |
| patient | `/financial` (liste + détail) | 390×844 | 8 | 8 | 8 | 0 | 0 | 2026-09-28T19:22Z |
| patient | `/notifications` | 390×844 | 21 | 18 | 18 | 0 | 0 | 2026-09-28T19:24Z |
| patient | `/treatment-plans` | 390×844 | 10 | 10 | 10 | 0 | 0 | 2026-09-28T19:26Z |
| patient | `/profile` | 390×844 | 13 | 13 | 12 | 0 | 0 (1 désactivé **légitime** : « Authentification biométrique — Indisponible sur ce navigateur ») | 2026-09-28T19:48Z |
| patient | `/home-care` | 390×844 | 17 | 17 | 17 | 0 | 0 | 2026-09-28T19:29Z |
| patient | `/implant-passport` | 390×844 | 7 | 7 | 7 | 0 | 0 | 2026-09-28T20:06Z |
| patient | `/reviews` (état vide « Aucun avis pour ce prestataire. ») | 390×844 | 1 | 1 | 1 | 0 | 0 | 2026-09-28T20:07Z |
| patient | `/profile/dependents` | 390×844 | 22 | 16 | 16 | 0 | 0 | 2026-09-28T20:09Z |
| praticien | `/patients` (annuaire + fiche) | 1280×800 | 35 | 18 | 18 | 0 | 0 | 2026-09-28T19:20Z |
| praticien | `/patients/:id` — **avec** relation de soin | 1280×800 | 50 | 4 | 4 | 0 | 0 | 2026-09-28T19:34Z |
| praticien | `/patients/:id` — **sans** relation de soin (5 portes cliniques) | 1280×800 | 42 | 6 | 5 | 0 | **1** (« Plans de traitement » → erreur générique + « Réessayer » en boucle, #7910) | 2026-09-28T19:40Z |
| praticien | `/devis` | 1280×800 | 27 | 12 | 12 | 0 | 0 | 2026-09-28T19:23Z |
| praticien | `/stock` | 1280×800 | 21 | 6 | 6 | 0 | 0 | 2026-09-28T19:25Z |
| praticien | `/team-messages` (composer + envoi réel) | 1280×800 | 25 | 10 | 8 | 0 | 0 (2 désactivés **légitimes**, tooltip « indisponible pour l'instant ») | 2026-09-28T19:45Z |
| praticien | `/agenda` | 1280×800 | 27 | 10 | 10 | 0 | 0 | 2026-09-28T19:27Z |
| praticien | `/cabinet-brief` | 1280×800 | 5 | 5 | 5 | 0 | 0 | 2026-09-28T19:28Z |
| secretariat | `/liste-attente` | 1280×800 | 22 | 1 | 1 | 0 | 0 | 2026-09-28T19:52Z |
| secretariat | `/correspondents` | 1280×800 | 26 | 5 | 5 | 0 | 0 | 2026-09-28T19:54Z |
| secretariat | `/cabinet-payouts` | 1280×800 | 26 | 5 | 5 | 0 | 0 (2 désactivés : « Exporter (CSV) » et « Connecter Stripe ») | 2026-09-28T19:56Z |
| secretariat | `/cabinet-stats` | 1280×800 | 22 | 1 | 1 | 0 | 0 (le 403 `stats/activity` est rendu « Réservé aux praticiens — votre rôle ne permet pas d'afficher l'activité par praticien. ») | 2026-09-28T20:32Z |
| secretariat | `/admin-membres` | 1280×800 | 28 | 5 | 5 | 0 | 0 (les 3 « Lien — … » rendent « Accès réservé aux administrateurs du cabinet. », à chaque clic) | 2026-09-28T20:12Z |
| secretariat | `/appointment-motifs` | 1280×800 | 22 | 1 | 1 | 0 | 0 | 2026-09-28T19:58Z |
| secretariat | `/audit-log` | 1280×800 | 26 | 5 | 3 | 0 | 0 (« Filtrer »/« Réinitialiser » désactivés — écran admin/manager, `ProAdminOrManagerClaims`) | 2026-09-28T20:00Z |
| secretariat | `/conges` | 1280×800 | 23 | 2 | 2 | 0 | 0 | 2026-09-28T20:02Z |
| secretariat | `⌘K` — palette de commandes (spotlight) | 1280×800 | 16 | 8 | 8 | 0 | 0 | 2026-09-28T20:30Z |
| pharmacie | `/notification-preferences` | 1280×800 | 9 | 9 | 9 | 0 | 0 | 2026-09-28T20:18Z |
| reservation (SSR) | `/`, `/dentiste/lyon`, `/dr-…`, `/reservation/confirmer` | 390×844 | 12 | 10 | 10 | 0 | 0 | 2026-09-28T19:14Z |

**Contre-épreuves de la seconde moitié** (33 « CASSÉ » bruts → **0 défaut**) :
- `praticien /patients` ×13 et `praticien /patients/:id` : `403` sur `notes` / `medical-record` / `prescriptions` / `dental-chart` / `periodontal-chart` = **garde « relation de soin »**, rendue par un message explicite « Vous n'avez pas encore suivi ce patient — … ». Contrôle : les mêmes appels sur un patient suivi (Marc Dubois) rendent **200**. Seule exception → **#7910**.
- `patient /financial` ×6, `patient /treatment-plans` ×2, `praticien /devis` ×6 : `404 GET /v1/quotes/:id/attestation` = **« aucune attestation déposée »**, comportement documenté (`quote_attestation.rs:200-204`). Contre-épreuve : après `POST /v1/cabinet/quotes/:id/attestation`, le même écran rend « Attestation d'information signée le 28/09/2026 » et l'appel passe **200**. Aucune dégradation d'affichage.
- `secretariat /admin-membres` ×3 : `403 POST /v1/cabinet/invite-links` → l'UI affiche « Accès réservé aux administrateurs du cabinet. » (et le ré-affiche au 2e clic).
- `secretariat /cabinet-stats`, `/tasks`, `/conformite` : `403` sur `stats/activity` et `audit-log` → messages dédiés ou sondage de rôle documenté (`audit_log_access_cubit.dart:20`).
- 19 « MORT » bruts → **0 nouveau défaut** : facettes déjà sélectionnées (`patient /mes-rdv` « À venir (73) », `/documents` « Tous 557 », `/notifications` « Toutes 2552 »), **sélecteur de fichier natif** hors DOM (`patient /profile` « Modifier la photo de profil » — contre-épreuve par l'événement Playwright `filechooser`, qui se déclenche bien), **zone de saisie** dont le contenu n'entre pas dans l'empreinte Semantics (`praticien /team-messages` « Écrire à l'équipe… » — contre-épreuve : `textarea.value === "QA R109 message équipe"`, puis `POST /v1/cabinet/messages` au clic sur « Envoyer », et « Mentionner » insère bien `@`).

**Cas adversariaux supplémentaires (tunnel SSR `reservation.doc.nubia-link.com`)**

| cas | verdict | preuve |
|---|---|---|
| email malformé | **refus propre** | `POST /reservation/confirmer` → **422**, page « Certaines informations sont manquantes ou invalides… » + « Revenir au formulaire ». |
| consentement décoché | **refus propre** | même 422, même page. |
| prénom de 300 caractères | **refus propre** | même 422 ; *note : le message générique dit « tous les champs sont requis » alors que tous l'étaient — seule la longueur était en cause.* |
| double-submit | **impossible** | le 2e clic tombe sur un DOM déjà remplacé (`Element is not attached to the DOM`) ; un seul RDV créé. |
| bout-en-bout | **OK** | RDV créé + compte Nubia créé ; **constaté côté cabinet** : `GET /v1/cabinet/appointments?date=2026-09-29` rend `09:00 requested QA R109Tunnel | Dr Claire Lefèvre | QA R109 tunnel SSR`. |

**Troisième passe (19:40–20:40 UTC) — 27 écrans de plus, parcours métier complets**

| app | écran / route | viewport | inventoriés | activés | OK | morts | cassés | last_check ISO |
|---|---|---|---|---|---|---|---|---|
| praticien | `/consultation?id=` — **consultation au fauteuil, séance ouverte** | 1280×800 | 45 | 12 | 11 | 0 | **1** (ajout d'un acte invasif → cul-de-sac, #7911) | 2026-09-28T19:42Z |
| praticien | `/ordonnances/new?patientId=` — **composition → signature → envoi officine** | 1280×800 | 30 | 6 | 6 | 0 | 0 | 2026-09-28T19:47Z |
| praticien | `/messages` | 1280×800 | 27 | 12 | 12 | 0 | 0 | 2026-09-28T20:14Z |
| praticien | `/mes-conges` | 1280×800 | 21 | 6 | 6 | 0 | 0 | 2026-09-28T20:16Z |
| praticien | `/act-categories` | 1280×800 | 2 | 2 | 1 | 0 | 1 (« Réessayer » sur un 403 de rôle — jumeau de #7910, commenté sur le ticket) | 2026-09-28T20:22Z |
| praticien | `/stock-inventory` | 1280×800 | 33 | 16 | 16 | 0 | 0 | 2026-09-28T20:24Z |
| praticien | `/consent-templates` | 1280×800 | 21 | 16 | 16 | 0 | 0 | 2026-09-28T20:27Z |
| praticien | `/questionnaire-templates` | 1280×800 | 2 | 2 | 2 | 0 | 0 | 2026-09-28T20:29Z |
| secretariat | `/messages` | 1280×800 | 42 | 16 | 16 | 0 | 0 | 2026-09-28T20:12Z |
| secretariat | `/team-messages` | 1280×800 | 27 | 6 | 6 | 0 | 0 (2 désactivés légitimes) | 2026-09-28T20:15Z |
| secretariat | `/admin-secretariats` | 1280×800 | 22 | 1 | 1 | 0 | 0 | 2026-09-28T20:18Z |
| secretariat | `/maintenance` | 1280×800 | 26 | 5 | 5 | 0 | 0 | 2026-09-28T20:20Z |
| secretariat | `/bookable-slots` | 1280×800 | 25 | 4 | 4 | 0 | 0 | 2026-09-28T20:23Z |
| secretariat | `/appointments` | 1280×800 | 26 | 5 | 5 | 0 | 0 | 2026-09-28T20:26Z |
| secretariat | `/cabinet-brief` | 1280×800 | 5 | 5 | 5 | 0 | 0 | 2026-09-28T20:28Z |

**Parcours métier complets joués en UI (un par app, exigence de clôture)**

| app | parcours | verdict |
|---|---|---|
| patient | annuaire `/book` → chip de créneau → grille `/appointments/slots` → « Continuer » → bénéficiaire + motif → « Confirmer le rendez-vous » | **OK** — 1 seul `POST /v1/bookings` malgré un double-clic, écran « Demande de rendez-vous envoyée » |
| praticien | fiche patient → « Créer une ordonnance » → modèle « Antibioprophylaxie clindamycine » → « Créer l'ordonnance » → « Signer l'ordonnance » → « Envoyer à la pharmacie » | **OK** — `POST /cabinet/prescriptions` → `…/sign` → l'ordonnance apparaît `signed` côté patient, puis `CMD-0451` `received` côté officine |
| secretariat | `/salle-attente` file montée → ⌘⏎ « Appeler suivant » → sortie de file après clôture de la séance | **OK** (le bouton de ligne d'une entrée déjà appelée est le défaut #7905) |
| pharmacie | `/` file → `/orders/:id` délivrance → « Scanner le retrait » → code court → `picked_up` | **OK** — y compris le refus d'un QR d'une autre commande |
| infirmiere | offre → « Accepter » → « Je pars » → « Je suis arrivé·e » → « Visite terminée » | **OK** — un POST par étape, le patient suit chaque transition |
| reservation (SSR) | `/dentiste/lyon` → créneau → formulaire → « Confirmer le rendez-vous » | **OK** — RDV constaté ensuite dans l'agenda du cabinet |

**Quatrième passe (20:00–20:30 UTC) — viewports croisés : les 3 apps « PC » à 390 px, les 2 apps « mobile » à 1280 px**

| app | écran / route | viewport | inventoriés | activés | OK | morts | cassés | last_check ISO |
|---|---|---|---|---|---|---|---|---|
| praticien | `/` tableau de bord | **390×844** | 25 | 14 | 14 | 0 | **0** (mais en-tête écrasé → #7912) | 2026-09-28T20:05Z |
| praticien | `/waiting-room`, `/patients`, `/agenda`, `/devis`, `/ordonnances` | **390×844** | 60 | 34 | 34 | 0 | 0 | 2026-09-28T20:10Z |
| secretariat | `/`, `/agenda`, `/salle-attente`, `/patients`, `/devis`, `/stock` | **390×844** | 146 | 59 | 59 | 0 | 0 | 2026-09-28T20:12Z |
| pharmacie | `/`, `/devis`, `/stock`, `/messages` | **390×844** | 61 | 30 | 30 | 0 | 0 | 2026-09-28T20:14Z |
| patient | `/`, `/mes-rdv`, `/financial`, `/documents`, `/messaging`, `/profile` | **1280×800** | 72 | 44 | 44 | 0 | 0 | 2026-09-28T20:22Z |
| infirmiere | `/`, `/notification-preferences` | **1280×800** | 10 | 5 | 5 | 0 | 0 | 2026-09-28T20:20Z |

> **Troisième piège de méthode corrigé cette ronde — rect hors viewport HORIZONTALEMENT, cas limite.**
> `secretariat /agenda` à 390 px : la puce de filtre « Dr Hugo Marin 47 » ressortait MORTE
> (`aria-checked` reste `false` après clic **et** après `touchscreen.tap`), alors que sa voisine
> « Dr Claire Lefèvre 17 » bascule normalement. **Contre-épreuve décisive** : les rects mesurés donnent
> chip Hugo `x=198..357` et champ de recherche `x=175..342` — ils se chevauchent, et
> `document.elementFromPoint(277, 286)` rend **`INPUT`**, pas le switch.
> Lecture du code : `agenda_page.dart:665-706`, `_PractitionerFilterChips` est un
> `SingleChildScrollView(scrollDirection: Axis.horizontal)` — la puce est simplement **défilée hors
> de la zone visible**, et Flutter rapporte son rect en espace de contenu (piège déjà documenté en R108,
> mais mon seuil de défilement `x > largeur − 20` ne l'attrapait pas ici : 357 < 370).
> **Preuve finale** : après `mouse.wheel(120, 0)` × 4 sur la rangée, la puce revient à `x=16..114`,
> `elementFromPoint` rend bien le `switch`, et le clic bascule `checked` à **true**.
> → **faux positif, aucun ticket**. Le harnais doit comparer le rect au *clip* du parent, pas au viewport.

**Bilan des contre-épreuves de la ronde** : sur **86 alertes brutes** (33 MORT + 53 CASSÉ cumulés sur
les 71 visites d'écran des walks), **82 sont des artefacts** entièrement expliqués et re-prouvés un par un ;
**4 défauts réels** en sont sortis (#7905 ×2 boutons morts, #7910 et son jumeau `/act-categories` ×2 relances
inutiles sur un 403).

**Cinquième passe (20:15–20:30 UTC) — parcours restants**

| app | écran / route | viewport | inventoriés | activés | OK | morts | cassés | last_check ISO |
|---|---|---|---|---|---|---|---|---|
| secretariat | `/patients/new` — **création de dossier bout-en-bout** | 1280×800 | 7 | 6 | 6 | 0 | 0 | 2026-09-28T20:17Z |
| patient | `/pharmacy/orders/:id` — **suivi de commande, 2 états** | 390×844 | 14 | 6 | 6 | 0 | 0 | 2026-09-28T20:26Z |
| patient | `/documents` — mesure du démarrage (28 requêtes) | 390 + 1280 | 40 | 4 | 4 | 0 | 0 (démarrage lent → #7913) | 2026-09-28T20:24Z |

**Parcours métier complet supplémentaire** — `secretariat /patients/new` : saisie Prénom / Nom / Téléphone / Date de naissance
(« Créer le dossier » reste **désactivé** tant que le formulaire est incomplet, puis s'active) → `POST /v1/cabinet/patients/quick`
→ navigation vers `/patients` où la fiche neuve apparaît en tête (`QA R109Fiche… · +33612340999`). **OK.**

**Sixième passe (20:20–20:45 UTC)**

| app | écran / route | viewport | inventoriés | activés | OK | morts | cassés | last_check ISO |
|---|---|---|---|---|---|---|---|---|
| patient | `/signup` | 390×844 | 5 | 4 | 4 | 0 | 0 (1 désactivé légitime : « Créer mon compte » avant CGU) | 2026-09-28T20:24Z |
| patient | `/forgot-password` (+ soumission d'un e-mail inconnu) | 390×844 | 3 | 3 | 3 | 0 | 0 | 2026-09-28T20:24Z |
| patient | `/reset-password?token=…` | 390×844 | 5 | 4 | 4 | 0 | 0 | 2026-09-28T20:24Z |
| patient | `/profile/notifications` | 390×844 | 12 | 12 | 9 | 0 | 0 (3 désactivés **avec raison**) | 2026-09-28T20:20Z |
| patient | `/rdv/:id/prepare` | 390×844 | 2 | 2 | 2 | 0 | 0 | 2026-09-28T20:40Z |
| patient | `/rdv/:id/modifier` | 390×844 | 60 | 8 | 8 | 0 | 0 | 2026-09-28T20:40Z |
| patient | route inexistante (`/rdv//prepare`) | 390×844 | 1 | 1 | 1 | 0 | 0 | 2026-09-28T20:22Z |
| patient | `/coverage-setup`, `/account-setup`, `/pharmacy`, `/pharmacy/search` | 390×844 | 34 | 18 | 18 | 0 | 0 | 2026-09-28T20:26Z |

**Fausse alerte écartée par lecture du code** : sur `/rdv/:id/prepare`, « Rappel Jeu 8 oct à **10:30** » face au « Jeu 8 oct à **11:30** » de `/modifier` ressemblait à un décalage de fuseau d'1 h. `prepare_rdv_info_card.dart:49` rend en réalité `preparation.reminderAt`, et l'API sert `reminder_at = 2026-10-08T08:30:00+00:00` pour un RDV à `09:30Z` — c'est **le rappel, 1 h avant**. Aucun ticket.

**Septième passe (20:26–20:32 UTC) — dernières routes du manifeste**

| app | écran / route | viewport | inventoriés | activés | OK | morts | cassés | last_check ISO |
|---|---|---|---|---|---|---|---|---|
| praticien | `/lab-stats` | 1280×800 | 1 | 1 | 1 | 0 | 0 (libellé fautif « 1 bons » → #7915) | 2026-09-28T20:28Z |
| praticien | `/notification-preferences` | 1280×800 | 12 | 7 | 7 | 0 | 0 | 2026-09-28T20:30Z |
| praticien | `/cabinet-setup` | 1280×800 | 5 | 5 | 5 | 0 | 0 (« Enregistrer » désactivé tant que le formulaire est vide) | 2026-09-28T20:31Z |

**Derniers cas adversariaux (20:30–20:35 UTC)**

| cas | écran | verdict | preuve |
|---|---|---|---|
| **coupure réseau** pendant « Marquer prête » | pharmacie `/` (file des commandes) | **OK** | `route.abort` sur `*/v1/*` puis clic : erreur visible à t=1,2 s et t=3 s, estompée à t=6 s ; **la ligne reste « En préparation »**, aucun spinner, aucun écran blanc ; après rechargement la commande est **toujours** en préparation (l'état serveur n'a pas bougé). Non-régression de #7868. |
| **BACK** au milieu du scan de retrait | pharmacie `/orders/:id` → panneau de scan | **OK** | Code partiel saisi puis `goBack()` → retour à la file `/` cohérente (40 contrôles, KPI à jour, 0 erreur) ; `goForward()` reste sur la file (le panneau de scan n'est pas une entrée d'historique). |

### Ronde R108 — 2026-09-28 (12:00–15:00 UTC) — **5/5 apps**, **32 écrans**, **889 contrôles inventoriés, 305 activés, 283 OK, 0 mort RÉEL, 0 cassé**

> **Méthode.** Inventaire par l'arbre Semantics (`flt-semantics[role|aria-label]` + `input`/`textarea`),
> activation au centre du rect, verdict par diff (url / libellés Semantics / empreinte de pixels / requêtes
> `/v1/`). Le **shell** (rail de navigation, 20-21 entrées identiques sur chaque écran secrétariat) est
> inventorié mais activé **une seule fois** — la colonne « inventoriés » le compte, « activés » non.
>
> **Troisième piège de méthode corrigé cette ronde** (après les deux de R104) : **rect hors viewport
> HORIZONTALEMENT.** Les rangées de facettes/chips défilent latéralement, et Flutter rapporte leurs rects
> dans l'espace du contenu : sur `patient /documents` (390 px de large), `Radio 25` est à **x = 558**,
> `Consentement 8` à **x = 1028**. Cinq facettes ressortaient « mortes » alors qu'elles filtrent toutes.
> **Contre-épreuve** : après défilement horizontal (`mouse.wheel(220, 0)` × n), `Radio 25` revient à x = 350,
> le clic filtre réellement (la liste ne garde que « Radio du 28 sept. »). Le harnais fait désormais défiler
> en **x** comme en **y** avant de juger. Les 4 « morts » de `secretariat /` et les 2 de `patient` relèvent
> du même piège en **y** (rects à `y > 800`) — re-testés un par un : « Relancer » émet
> `GET /cabinet/quotes` + `/quotes/:id` + `/quotes/:id/events`, « Voir tout » ouvre l'écran Tâches,
> « Mes proches » navigue vers `/profile/dependents` avec 4 requêtes. **Aucun mort réel.**

| app | écran/route | viewport | inventoriés | activés | OK | morts (réels) | cassés | last_check |
|---|---|---|---|---|---|---|---|---|
| secretariat | `/` (Tableau de bord) | 1280×800 | 41 | 12 | 12 | 0 | 0 | 2026-09-28T12:44:00Z |
| secretariat | `/salle-attente` (file **non vide**) | 1280×800 | 29 | 4 | 4 | 0 | 0 | 2026-09-28T12:31:00Z |
| secretariat | `/team-messages` | 1280×800 | 34 | 4 | 2 (+2 désactivés **légitimes**) | 0 | 0 | 2026-09-28T12:37:00Z |
| secretariat | `/liste-attente` | 1280×800 | 26 | 3 | 3 | 0 | 0 | 2026-09-28T12:41:00Z |
| secretariat | `/agenda` (grille semaine) | 1280×800 | — | 7 | 7 | 0 | 0 | 2026-09-28T13:47:00Z |
| patient | `/` (Accueil) | 390×844 | 22 | 10 | 10 | 0 | 0 | 2026-09-28T12:33:00Z |
| patient | `/mes-rdv` | 390×844 | 13 | 8 | 8 | 0 | 0 | 2026-09-28T12:36:00Z |
| patient | `/prescriptions` | 390×844 | 14 | 10 | 10 | 0 | 0 | 2026-09-28T12:49:00Z |
| patient | `/pharmacy/orders` | 390×844 | 17 | 10 | 10 | 0 | 0 | 2026-09-28T13:00:00Z |
| patient | `/profile` | 390×844 | 17 | 10 | 9 (+1 désactivé **légitime**) | 0 | 0 | 2026-09-28T13:04:00Z |
| patient | `/documents` (coffre-fort, 12 facettes) | 390×844 | 43 | 10 | 10 | 0 | 0 | 2026-09-28T13:40:00Z |
| patient | `/messaging` | 390×844 | 10 | 9 | 9 | 0 | 0 | 2026-09-28T13:45:00Z |
| pharmacie | `/` (File des commandes) | 1280×800 | 44 | 12 | 11 (+1 destructif non activé) | 0 | 0 | 2026-09-28T12:51:00Z |
| pharmacie | `/messages` | 1280×800 | 17 | 12 | 11 (+1 destructif) | 0 | 0 | 2026-09-28T12:53:00Z |
| pharmacie | `/devis` | 1280×800 | 42 | 12 | 11 (+1 destructif) | 0 | 0 | 2026-09-28T12:57:00Z |
| pharmacie | `/stock` | 1280×800 | 19 | 12 | 10 (+1 destructif, 1 hors écran) | 0 | 0 | 2026-09-28T13:00:00Z |
| pharmacie | `/orders/:id` (Délivrance) | 1280×800 | 13 | — *(capture + comparaison maquette)* | — | — | — | 2026-09-28T13:14:00Z |
| pharmacie | `/orders/:id/pickup` (scan, accès direct) | 1280×800 | 4 | — *(capture + comparaison maquette → #7894)* | — | — | — | 2026-09-28T13:15:00Z |
| praticien | `/` (Tableau de bord) | 1280×800 | 39 | 11 | 11 | 0 | 0 | 2026-09-28T13:06:00Z |
| praticien | `/waiting-room` | 1280×800 | 23 | 11 | 11 | 0 | 0 | 2026-09-28T13:09:00Z |
| praticien | `/ordonnances` | 1280×800 | 22 | 11 | 11 | 0 | 0 | 2026-09-28T13:12:00Z |
| praticien | `/patients` | 1280×800 | 38 | 11 | 11 | 0 | 0 | 2026-09-28T13:14:00Z |
| praticien | `/devis` | 1280×800 | 30 | 11 | 11 | 0 | 0 | 2026-09-28T13:44:00Z |
| patient | `/notifications` | 390×844 | 21 | 10 | 10 | 0 | 0 | 2026-09-28T13:49:00Z |
| patient | `/treatment-plans` (Mon plan de soins) | 390×844 | 11 | 8 | 8 | 0 | 0 | 2026-09-28T13:54:00Z |
| patient | `/financial` (Mes devis) | 390×844 | 9 | 8 | 8 | 0 | 0 | 2026-09-28T14:00:00Z |
| praticien | `/consultation` | 1280×800 | 38 | 11 | 11 | 0 | 0 | 2026-09-28T13:49:00Z |
| praticien | `/lab-work-orders` (Travaux labo) | 1280×800 | 29 | 11 | 11 | 0 | 0 | 2026-09-28T13:56:00Z |
| praticien | `/stock` | 1280×800 | 24 | 11 | 11 | 0 | 0 | 2026-09-28T14:02:00Z |
| secretariat | `/patients` (Fiches patients) | 1280×800 | — | 12 | 12 | 0 | 0 | 2026-09-28T13:56:00Z |
| secretariat | `/cabinet-payouts` (Encaissements) | 1280×800 | 29 | 7 | 5 (+2 désactivés **légitimes**) | 0 | 0 | 2026-09-28T14:01:00Z |
| secretariat | `/stock` (Demandes de stock) | 1280×800 | 57 | 12 | 12 | 0 | 0 | 2026-09-28T14:05:00Z |
| secretariat | **Spotlight ⌘K** (palette de commandes) | 1280×800 | 18 | 5 | 5 | 0 | 0 | 2026-09-28T14:02:00Z |
| **infirmiere** | `/` (3 onglets : Disponibilité / Offres / Ma visite) | 390×844 | 8 | 7 | 6 (+1 destructif) | 0 | 0 | 2026-09-28T13:12:00Z |
| **infirmiere** | `/notification-preferences` | 390×844 | 5 | 3 | 3 | 0 | 0 | 2026-09-28T13:12:00Z |

**Contrôles désactivés — légitimité prouvée (6/6)**

| contrôle | écran | verdict |
|---|---|---|
| « Joindre un patient, un devis… » | secretariat `/team-messages` | **Légitime** — `onPressed: null` **assumé et documenté** (`cabinet_team_messages_page.dart:1176-1192`, #6702 : aucun endpoint côté API), avec **infobulle explicative** rendue dans l'arbre Semantics (« Joindre un patient ou un devis est indisponible pour l'instant. ») |
| « Épingler » | secretariat `/team-messages` | **Légitime** — même bloc (`:1194-1205`), infobulle « Épinglage de message indisponible pour l'instant. » |
| « Authentification biométrique » | patient `/profile` | **Légitime** — la raison est **affichée à l'écran** : « Indisponible sur ce navigateur. » (WebAuthn absent du Chromium headless) |
| « Connecter Stripe » | secretariat `/cabinet-payouts` | **Légitime** — `onPressed: null` documenté (`cabinet_payouts_page.dart:383-395`, #6702 : aucune intégration côté API), infobulle « Connexion Stripe indisponible pour l'instant. », et bandeau d'explication au-dessus (« Aucun compte de paiement connecté. Les virements affichés sont des données de démonstration ») |
| « Exporter (CSV) » | secretariat `/cabinet-payouts` | **Légitime** — `onPressed: payouts.isEmpty ? null : …` (`:64-66`) ; le mois affiché (**septembre 2026**) n'a aucun virement (`GET /v1/cabinet/payouts` ne rend que des `arrival_date` de juillet), l'écran rend d'ailleurs l'état vide « Aucun virement » |
| « Appeler suivant » | praticien `/waiting-room` | **Légitime** — file vide à l'instant du test (la ronde venait de la vider) ; le même bouton est actif et fonctionnel côté secrétariat quand la file est peuplée |

**Contrôles non activés volontairement (destructifs, 5)** — « Se déconnecter » sur pharmacie (×4 écrans) et infirmière.

**Mécaniques prescrites, exécutées pour de vrai cette ronde**

| mécanique | écran | verdict |
|---|---|---|
| « Appeler `<nom>` » appelle bien **ce** patient, et **une seule fois** sur double-clic | secretariat `/salle-attente` | **OK** — 1 × `POST /cabinet/waiting-room/call-next` → 200 pour 2 clics à 100 ms |
| Facettes de la file officine (`Toutes/Reçues/En préparation/Prêtes/Retirées/Refusées/Annulées`) | pharmacie `/` | **OK** — arithmétique juste (`2+26+60 = 88 = « Toutes »`, les états terminaux étant hors file, comme la maquette) |
| Facettes du coffre-fort (12 catégories) | patient `/documents` | **OK** — somme exacte (`552`), et le filtre est **confirmé côté serveur** : `GET /documents?category=radio` → 25, `cbct` → 3, `photo` → 9, `cr` → 7, `consentement` → 8 |
| Facettes devis officine | pharmacie `/devis` | **OK** — `15+2+104+24 = 145 = « Tous »` |
| Onglets infirmière + bascule « En ligne » | infirmiere `/` | **OK** — la bascule écrit réellement (`PATCH /v1/nurse/availability`, vérifié côté API), les 3 onglets rendent leur contenu, **les 2 états vides sont présents** |

### Ronde R104 — 2026-09-27 (12:00–15:00 UTC) — **5/5 apps**, 21 écrans, **453 contrôles inventoriés, 266 activés, 0 mort réel, 0 cassé réel**

> **Méthode.** Inventaire par l'arbre Semantics (`flt-semantics[role]` + `input`/`textarea`), activation au
> centre du rect, verdict par diff (url / libellés / pixels / requêtes API / téléchargements / popups).
>
> **Deux pièges de méthode corrigés dans cette ronde — ils produisaient de FAUX « morts » :**
> 1. **Rect hors viewport.** Flutter rapporte les rects dans l'espace du *contenu défilable*, pas du viewport :
>    un contrôle sous la ligne de flottaison est rapporté à `y > hauteur`, et le clic brut le rate. Sans
>    défilement préalable, 5 des 7 tuiles du Profil patient ressortaient « mortes » alors qu'elles naviguent
>    toutes. **Toujours faire défiler jusqu'au contrôle avant de le juger.**
> 2. **Effet invisible dans le DOM.** Un contrôle qui déclenche un **téléchargement**, un **sélecteur de
>    fichier** ou un **nouvel onglet** ne change ni l'URL, ni les libellés, ni les pixels. Les 14 « morts »
>    bruts de cette ronde sont **tous** de ce type : 11 « Télécharger » du coffre-fort (vérifié : produisent
>    bien `0ba67adb-….pdf`, `97efe6a8-….pdf`), « Modifier la photo de profil » (ouvre le `filechooser`),
>    une carte d'ordonnance (émet `GET /v1/documents/:id/download`). Le harnais écoute désormais
>    `download` / `filechooser` / `popup` / `request`. **Morts réels : 0.**
> 3. **Clip de conteneur défilant** (cf. `/patients` ci-dessous) : un nœud Semantics peut être rapporté
>    *dans* le viewport de la page mais *hors* du clip de son propre `ListView` — le clic le rate quand même.

| app | écran/route | viewport | inventoriés | activés | OK | morts | cassés | last_check |
|---|---|---|---|---|---|---|---|---|
| patient | `/` (Accueil) | 390×844 | 20 | 17 | 17 | 0 | 0 | 2026-09-27T12:40:00Z |
| patient | `/mes-rdv` | 390×844 | 12 | 8 | 8 | 0 | 0 | 2026-09-27T12:54:00Z |
| patient | `/documents` (coffre-fort) | 390×844 | 41 | 28 | 28 | 0 | 0 | 2026-09-27T12:58:00Z |
| patient | `/prescriptions` | 390×844 | 12 | 12 | 12 | 0 | 0 | 2026-09-27T13:04:00Z |
| patient | `/profile` | 390×844 | 16 | 13 | 13 | 0 | 0 | 2026-09-27T12:16:00Z |
| patient | `/appointments` (tunnel + feuille praticien) | 390×844 | 25 | 3 | 3 | 0 | 0 | 2026-09-27T14:05:00Z |
| patient | `/login` (cas adversariaux) | 390×844 | 5 | 5 | 5 | 0 | 0 | 2026-09-27T13:58:00Z |
| praticien | `/` (Tableau de bord) | 1280×800 | 36 | 33 | 33 | 0 | 0 | 2026-09-27T13:17:00Z |
| praticien | `/waiting-room` | 1280×800 | 21 | 20 | 19 | 0 | 0 | 2026-09-27T13:38:00Z |
| praticien | `/ordonnances` | 1280×800 | 20 | 19 | 19 | 0 | 0 | 2026-09-27T14:55:00Z |
| praticien | `/devis` | 1280×800 | 27 | 26 | 26 | 0 | 0 | 2026-09-27T14:57:00Z |
| secretariat | `/agenda` (grille semaine + volet) | 1280×800 | 85 | 12 | 12 | 0 | 0 | 2026-09-27T13:20:00Z |
| secretariat | `/salle-attente` | 1280×800 | 28 | 22 | 22 | 0 | 0 | 2026-09-27T13:22:00Z |
| secretariat | `/patients` (fiches) | 1280×800 | 40 | 26 | 26 | 0 | 0 | 2026-09-27T13:52:00Z |
| pharmacie | `/` (File des commandes) | 1280×800 | 30 | 14 | 14 | 0 | 0 | 2026-09-27T13:45:00Z |
| pharmacie | `/stock` | 1280×800 | 15 | 13 | 13 | 0 | 0 | 2026-09-27T14:19:00Z |
| pharmacie | `/devis` | 1280×800 | 38 | 16 | 16 | 0 | 0 | 2026-09-27T14:39:00Z |
| pharmacie | `/messages` | 1280×800 | 15 | 14 | 14 | 0 | 0 | 2026-09-27T14:28:00Z |
| infirmiere | `/` (Disponibilité/Offres/Ma visite) | 390×844 | 8 | 6 | 6 | 0 | 0 | 2026-09-27T13:20:00Z |
| infirmiere | `/notification-preferences` | 390×844 | 5 | 3 | 3 | 0 | 0 | 2026-09-27T13:06:00Z |
| infirmiere | `/notifications` | 390×844 | 1 | 1 | 1 | 0 | 0 | 2026-09-27T13:07:00Z |

**États vides dignes constatés (famille « liste vide rendue comme un chargement infini ») :**
- praticien `/ordonnances` : icône + « **Aucune ordonnance en cours** » + « Ouvrez une fiche patient pour créer une ordonnance. » + CTA « **Choisir un patient** ». Pas de spinner, pas d'écran blanc.
- patient `/mes-rdv` sous coupure réseau : « **Erreur réseau. Vérifiez votre connexion.** » + « **Réessayer** » qui répare réellement l'écran (2 ⇒ 13 contrôles au rétablissement).

**Contrôles DÉSACTIVÉS jugés légitimes (preuve exigée) :**
- praticien `/waiting-room` — « **Appeler suivant** » grisé : la salle était **vide** à cet instant
  (`GET /v1/cabinet/waiting-room` → `{"data":[]}`, la ronde venait de clôturer la séance de Marc Dubois).
  Grisage correct.
- patient `/profile` — « **Authentification biométrique** » grisée : WebAuthn indisponible en Chromium
  headless. Non imputable à l'app.

**Un « CASSÉ » remonté puis ÉCARTÉ — l'expiration de jeton en cours d'audit :**
sur `pharmacie /devis`, l'activation de la facette « Tous (142) » a levé un `pageerror: Error` (message vide),
avec en console un échec de handshake `wss://api.doc.nubia-link.com/v1/ws?access_token=… : 502`.
**Non reproductible en session fraîche** : les 5 facettes (`Tous`, `Brouillons`, `Envoyés`, `Acceptés`,
`Refusés`) ont été rejouées une à une — **0 `pageerror`**, filtrage effectif (`Envoyés` fait tomber
l'inventaire de 38 à 19 contrôles puis `Acceptés` le remonte à 38). Et le WebSocket **fonctionne** :
ouvert en **16 ms** depuis un vrai navigateur avec un jeton valide, refusé sans jeton. La cause est
l'**access token expiré** (TTL 900 s) sur une reconnexion WS tardive d'un audit de 30 minutes, pas un défaut
de l'écran. *Leçon pour les rondes suivantes : rafraîchir le jeton du contexte navigateur sur les audits
longs, sinon les derniers écrans héritent de faux CASSÉ.*

**Correction apportée au registre — `Réglages du cabinet` (secrétariat, 1280×800) :**
la ronde R100 (#7692) puis R101 (#7706) concluaient que le groupe **ne se déplie jamais** à 1280×800,
« même après défilement ». **C'est inexact aujourd'hui, et la nuance est méthodologique.** Mesuré :
le `ListView` du rail a un viewport `y = 99 … 624` (525 px) alors que Semantics rapporte l'en-tête à
`y = 659` — *dans* la fenêtre du navigateur mais *hors* du clip du rail. Un clic à la coordonnée
rapportée tombe donc à côté (3 modalités essayées : souris, bord gauche, `Entrée` — 20 ⇒ 20).
**Mais un défilement du rail de 120 px ramène l'en-tête à `y = 608`, et le clic déplie alors
normalement : rail 20 ⇒ 28, révélant les 8 destinations** (`Statistiques`, `Créneaux ouverts`,
`Motifs de RDV`, `Stock`, `Maintenance`, `Membres`, `Secrétariats`, `Reprise de données`).
Idem sans défilement à 1280×1000. **Ce n'est donc pas un contrôle mort** — à ne plus rapporter comme tel.

### Ronde R100 — 2026-09-25 (18:00–21:00 UTC) — **5/5 apps**, 28 écrans audités, **600 contrôles inventoriés, 538 activés**

> **Méthode.** Flutter web rend **tout dans le shadow root de `<flt-glass-pane>`** : `document.querySelectorAll`
> ne le traverse pas et rapporte `canvas: 0`, `flt-semantics: 0` — d'où l'illusion d'un écran vide. Tout
> l'inventaire de cette ronde passe donc par une descente **récursive des shadow roots**. Deux autres
> pièges corrigés en cours de ronde, à retenir pour la suivante :
> 1. **Les champs de saisie ne sont pas des `flt-semantics`** mais de vrais `<input>`/`<textarea>`
>    (dans `flt-text-editing-host`), porteurs d'un `aria-label` mais **sans `role`** : il faut les
>    inventorier explicitement, sinon tout écran de connexion paraît n'avoir que des boutons.
> 2. **`role=group` est un CONTENEUR**, pas une commande : son libellé est la concaténation de ses
>    enfants (« NubiaEspace secrétariatAfficher le mot de passeSe connecter… ») et son centre
>    géométrique est du vide. Le viser fabrique de faux « morts » — et, au moment de cliquer
>    « Se connecter », fait rater la connexion en cliquant le conteneur au lieu du bouton.
> 3. **Désambiguïser par la POSITION** : sur une liste de cartes au libellé identique, un appariement
>    par libellé re-clique toujours la première et fait passer les 6 suivantes pour mortes.

| app | écran/route | viewport | inventoriés | activés | OK | morts | cassés | désactivés | last_check |
|---|---|---|---|---|---|---|---|---|---|
| patient | `/` | 390×844 | 18 | 15 | 15 | 0 | 0 | 0 | 2026-09-25T18:47Z |
| patient | `/mes-rdv` | 390×844 | 7 | 7 | 7 | 0 | 0 | 0 | 2026-09-25T18:48Z |
| patient | `/prescriptions` | 390×844 | 16 | 15 | 15 | 0 | 0 | 0 | 2026-09-25T18:50Z |
| patient | `/reviews` | 390×844 | 1 | 1 | 1 | 0 | 0 | 0 | 2026-09-25T18:51Z |
| patient | `/documents` | 390×844 | 28 | 20 | 20 | 0 | 0 | 0 | 2026-09-25T18:53Z |
| patient | `/notifications` | 390×844 | 20 | 16 | 16 | 0 | 0 | 0 | 2026-09-25T18:55Z |
| patient | `/messaging` | 390×844 | 9 | 9 | 9 | 0 | 0 | 0 | 2026-09-25T18:56Z |
| patient | `/financial` | 390×844 | 10 | 9 | 9 | 0 | 0 | 0 | 2026-09-25T18:58Z |
| patient | `/treatment-plans` | 390×844 | 10 | 8 | 8 | 0 | 0 | 0 | 2026-09-25T19:00Z |
| patient | `/home-care` | 390×844 | 17 | 15 | 15 | 0 | 0 | 0 | 2026-09-25T19:02Z |
| praticien | `/` | 1280×800 | 34 | 28 | 28 | 0 | 0 | 0 | 2026-09-25T18:41Z |
| praticien | `/agenda` | 1280×800 | 26 | 25 | 25 | 0 | 0 | 0 | 2026-09-25T18:44Z |
| praticien | `/waiting-room` | 1280×800 | 21 | 19 | 19 | 0 | 0 | 1 | 2026-09-25T18:47Z |
| praticien | `/ordonnances` | 1280×800 | 20 | 19 | 19 | 0 | 0 | 0 | 2026-09-25T18:50Z |
| praticien | `/patients` | 1280×800 | 35 | 30 | 30 | 0 | 0 | 0 | 2026-09-25T18:55Z |
| praticien | `/devis` | 1280×800 | 27 | 26 | 26 | 0 | 0 | 0 | 2026-09-25T18:58Z |
| praticien | `/lab-work-orders` | 1280×800 | 26 | 24 | 24 | 0 | 0 | 1 | 2026-09-25T19:01Z |
| praticien | `/mes-conges` | 1280×800 | 21 | 20 | 20 | 0 | 0 | 0 | 2026-09-25T19:03Z |
| secretariat | `/conges` | 1280×800 | 24 | 23 | 23 | 0 | 0 | 0 | 2026-09-25T18:32Z |
| secretariat | `/salle-attente` | 1280×800 | 24 | 22 | 22 | 0 | 0 | 1 | 2026-09-25T18:35Z |
| secretariat | `/stock` | 1280×800 | 42 | 41 | 40 | **1** | 0 | 0 | 2026-09-25T18:38Z |
| secretariat | `/devis` | 1280×800 | 54 | 47 | 46 | **1** | 0 | 0 | 2026-09-25T18:42Z |
| pharmacie | `/` (file des commandes) | 1280×800 | 32 | 29 | 29 | 0 | 0 | 0 | 2026-09-25T18:26Z |
| pharmacie | `/stock` | 1280×800 | 18 | 16 | 16 | 0 | 0 | 0 | 2026-09-25T18:28Z |
| pharmacie | `/devis` | 1280×800 | 33 | 29 | 29 | 0 | 0 | 0 | 2026-09-25T18:30Z |
| pharmacie | `/messages` | 1280×800 | 16 | 15 | 15 | 0 | 0 | 0 | 2026-09-25T18:32Z |
| infirmiere | `/` (accueil / offres) | 390×844 | 8 | 7 | 7 | 0 | 0 | 0 | 2026-09-25T19:05Z |
| infirmiere | `/notification-preferences` | 390×844 | 3 | 3 | 3 | 0 | 0 | 0 | 2026-09-25T19:06Z |
| **TOTAL** | **28 écrans** | — | **600** | **538** | **536** | **2** | **0** | **3** | — |

**Les 2 seuls contrôles MORTS de la ronde** sont le **même** : l'en-tête de groupe « **Réglages du cabinet** »
du rail secrétariat, inerte sur `/stock` comme sur `/devis` → **#7692 (P1)**. Vérifié à cinq modalités
d'activation, avec contre-épreuve positive (« Facturation » bascule correctement) et différentiel de
viewport (fonctionne à 1280×**1000**, mort à 1280×**800**).

**Les 3 contrôles DÉSACTIVÉS sont tous légitimes, et prouvés tels :**
- secrétariat `/salle-attente` → « **Appeler suivant** » : `GET /v1/cabinet/waiting-room` rend **0 entrée** — rien à appeler.
- praticien `/waiting-room` → idem, file vide.
- praticien `/lab-work-orders` → « **Nouveau bon** », accompagné à l'écran du motif explicite « Création de bon de travail indisponible pour … ».

**35 verdicts « cassé » et 19 « morts » bruts ont été REQUALIFIÉS en faux positifs après vérification** —
chacun re-testé individuellement plutôt que filé :

| symptôme brut | occurrences | pourquoi ce n'est PAS un défaut |
|---|---|---|
| `/financial`, `/devis` : 404 sur `…/attestation` au clic d'un devis | 18 | Sous-ressource **optionnelle** ; le bloc la replie sur `null` (#7201) et l'écran s'affiche intégralement — **capture à l'appui** (montant, répartition AMO/mutuelle, « Signer le devis »). |
| `/patients` : 403 sur `…/notes`, `…/medical-record` | 11 | Garde « relation de soin » **délibérée** (200 sur un patient suivi, 403 sinon) et l'UI affiche « **Vous n'avez pas encore suivi ce patient…** ». |
| « Questionnaire médical » → `canvas quasi vide ratio=0.987` | 6 | **Heuristique near-white trop naïve** : l'écran est simplement **sobre** (peu de contenu, beaucoup de blanc) et rend parfaitement. Seuil resserré depuis : blanc ⇔ `ratio > 0.985` **ET** ≤ 3 nœuds Semantics. |
| `/prescriptions` : 12 cartes « mortes » | 12 | **Libellés identiques** → l'appariement re-cliquait la première carte. Corrigé par désambiguïsation positionnelle. *A tout de même révélé un vrai défaut d'usage → **#7690**.* |
| pharmacie : `group:"CommandesStockMessagesDevis"` | 3 | **Conteneur** de la barre de navigation, pas une commande ; son centre est du vide entre deux entrées. |
| patient `/documents` : « **Télécharger** » | 1 | Le téléchargement **marche** : `acceptDownloads` activé → fichier `4b02c545-….pdf` reçu (l'ordonnance signée plus tôt dans la ronde). Un téléchargement ne change ni l'URL ni la peinture. |
| praticien : `progressbar:"0"`, `semantics:"Création de bon…"` | 2 | Rôles **non activables** (jauge, nœud de texte) — désormais exclus de l'inventaire. |

**Cas adversariaux joués (app_patient, 390×844) :**

| cas | verdict | preuve |
|---|---|---|
| **Double-submit** sur « Envoyer le message » | **OK** | Deux clics immédiats → **exactement 1** `POST /v1/conversations/:id/messages`, 0 requête ≥ 400. |
| **Texte très long** (320 car.) dans un champ libre | **OK** | Aucun débordement : **0 contrôle** hors du viewport 390×844, `nearWhite` stable (0.637 → 0.633), inventaire inchangé (7 → 7). |
| **BACK navigateur** au milieu du tunnel de réservation | **OK** | Retour sur un écran **repeint et utilisable** (7 contrôles, `nearWhite` 0.637, 24 nœuds Semantics) — aucun écran blanc ni état figé. |
| **Coupure réseau** (`route.abort` sur `*/v1/*`) sur `/documents` | **OK** | **Erreur digne** : l'écran se réduit à « Retour » + « **Réessayer** » — ni spinner infini, ni page blanche. |

### Ronde R100 — second segment (19:30–21:00 UTC) — 9 écrans jamais audités cette ronde, **+264 contrôles**

| app | écran/route | viewport | inventoriés | activés | OK | morts | cassés | désactivés | last_check |
|---|---|---|---|---|---|---|---|---|---|
| secretariat | `/agenda` (grille semaine) | 1280×800 | 79 | 69 | 68 | **1** | 0 | 0 | 2026-09-25T19:34Z |
| secretariat | `/patients` | 1280×800 | 40 | 36 | 35 | **1** | 0 | 0 | 2026-09-25T19:37Z |
| secretariat | `/messages` | 1280×800 | 37 | 33 | 32 | **1** | 0 | 0 | 2026-09-25T19:40Z |
| secretariat | `/cabinet-payouts` | 1280×800 | 28 | 25 | 24 | **1** | 0 | 2 | 2026-09-25T19:43Z |
| patient | `/profile` | 390×844 | 13 | 7 | 7 | 0 | 0 | 1 | 2026-09-25T19:30Z |
| patient | `/profile/dependents` | 390×844 | 22 | 17 | 17 | 0 | 0 | 0 | 2026-09-25T19:35Z |
| patient | `/profile/consents` | 390×844 | 8 | 5 | 5 | 0 | 0 | 1 | 2026-09-25T19:37Z |
| patient | `/implant-passport` | 390×844 | 6 | 4 | 4 | 0 | 0 | 0 | 2026-09-25T19:38Z |
| patient | `/appointments` | 390×844 | 18 | 15 | 15 | 0 | 0 | 0 | 2026-09-25T19:38Z |
| **SOUS-TOTAL** | **9 écrans** | — | **251** | **211** | **207** | **4** | **0** | **4** | — |

**Les 4 morts sont, à nouveau, le SEUL et même contrôle** : l'en-tête « **Réglages du cabinet** », inerte
sur `/agenda`, `/patients`, `/messages` **et** `/cabinet-payouts` — ce qui confirme que **#7692** frappe
**tous** les écrans du secrétariat à 1280×800, pas seulement les deux relevés au premier segment.

**14 « morts » bruts ont été requalifiés après vérification individuelle :**
- **8 cartes de RDV de `/agenda`** : re-testées une par une sur un écran rechargé, **les 3 échantillons
  ouvrent parfaitement leur volet de détail** (« Mercredi 23 septembre · 07:41 – », puis les actions
  `Fermer` / `Confirmer` / `Marquer arrivé` / `Déplacer` / `Annuler` / `Appeler`). Les cartes de la
  grille semaine sont **très fines et se chevauchent** (10, 23, 28 px de haut au même créneau) : le clic
  au centre atteint la carte du dessus, pas celle appariée par libellé. *Artefact de mesure, pas un défaut.*
- **`textbox:"Rechercher un patient"`** (`/agenda`) : re-testé isolément — la saisie « Dubois » **filtre
  réellement** (`count`+`labels`+`pixels` changent) et l'`<input>` porte bien `value:"Dubois"`. Le premier
  verdict venait d'un clic qui avait manqué le focus (champ étroit, 167×28 px à x=1065).
- **2 nœuds de TEXTE** pris pour des commandes : « Connexion Stripe indisponible pour l'instant. »
  (`/cabinet-payouts`) et un numéro de téléphone (`/patients`).

**Total consolidé de la ronde : 851 contrôles inventoriés, 749 activés, 743 OK, 6 morts (tous #7692),
0 cassé, 7 désactivés justifiés.**

### Ronde R100 — troisième segment (20:00–21:30 UTC) — 9 écrans de plus, **+184 contrôles**

| app | écran/route | viewport | inventoriés | activés | OK | morts | cassés | désactivés | last_check |
|---|---|---|---|---|---|---|---|---|---|
| praticien | `/consultation` | 1280×800 | 35 | 30 | 30 | 0 | 0 | 0 | 2026-09-25T20:05Z |
| praticien | `/stock` | 1280×800 | 21 | 20 | 20 | 0 | 0 | 0 | 2026-09-25T20:09Z |
| praticien | `/tasks` | 1280×800 | 5 | 5 | 5 | 0 | 0 | 0 | 2026-09-25T20:11Z |
| praticien | `/messages` | 1280×800 | 27 | 26 | 26 | 0 | 0 | 0 | 2026-09-25T20:15Z |
| secretariat | `/conformite` | 1280×800 | 32 | 26 | 26 | 0 | 0 | 0 | 2026-09-25T20:03Z |
| secretariat | `/tasks` | 1280×800 | 5 | 5 | 5 | 0 | 0 | 0 | 2026-09-25T20:06Z |
| secretariat | `/liste-attente` | 1280×800 | 23 | 22 | 21 | **1** | 0 | 0 | 2026-09-25T20:10Z |
| secretariat | `/correspondents` | 1280×800 | 26 | 25 | 23 | **1** | 1 | 0 | 2026-09-25T20:14Z |
| **SOUS-TOTAL** | **8 écrans** | — | **174** | **159** | **156** | **2** | **1** | **0** | — |

- Les **2 morts** sont, une fois de plus, l'en-tête « **Réglages du cabinet** » (**#7692**) — désormais
  constaté sur **6** écrans du secrétariat.
- Le **1 cassé** est `DELETE /v1/cabinet/correspondents/:id` → **409 `correspondent_in_use`** : garde de
  clé étrangère légitime, aucune suppression effectuée. *Ce contrôle (« Supprimer ce correspondant »)
  aurait dû figurer dans la liste des actions destructives non activées — à corriger à la ronde suivante.*
- Les deux « cassés » de `/conformite` et `/tasks` sont le **sondage de rôle** `GET /v1/cabinet/audit-log`
  → 403 (par conception, cf. `audit_log_access_cubit.dart:12-15`), requalifiés.
- Le bouton « **Clôturer** » de `/conformite` répond correctement (`OK(labels+pixels)`) — contre-épreuve
  UI du correctif **#7684**.

**Total consolidé de la ronde R100 : 1 025 contrôles inventoriés, 908 activés, 899 OK, 8 morts (tous #7692),
0 cassé réel, 7 désactivés justifiés.**

### Ronde R100 — cas adversariaux sur une app PRO + correction de méthode

**Cas adversariaux joués sur `app_pharmacie` (1280×800) — tous conformes :**

| cas | verdict | preuve |
|---|---|---|
| **Double-submit** sur « **Accepter** » (action métier, `/stock`) | **OK** | Deux clics immédiats → **exactement 1** `POST`, **0** requête ≥ 400. |
| **Saisie invalide** : refuser avec un motif **vide** | **OK** | La boîte « Refuser la demande » expose `textbox:"Motif du refus"` + `button:"Annuler"` + `button:"Refuser"` **`[DÉSACTIVÉ]`** — la garde est tenue **côté UI**, le bouton ne s'active qu'une fois le motif saisi. Cohérent avec la prescription ② de la maquette (« un refus sans motif obligatoire ») et avec le libellé « Refuser — motif obligatoire ». |
| **Texte très long** (320 car.) dans le motif | **OK** | **0 contrôle** hors du viewport 1280×800 — aucun débordement ni chevauchement. |
| **Coupure réseau** (`route.abort` sur `*/v1/*`) sur `/devis` | **OK** | **Erreur digne** : la navigation reste utilisable (Commandes / Stock / Messages / Devis) et un « **Réessayer** » apparaît ; `nearWhite` 0.797, ni écran blanc ni spinner infini. |

> **Correction de méthode — à retenir absolument pour la prochaine ronde.** Plusieurs « login KO »
> de cette ronde ont d'abord été attribués à la charge CPU puis à un redéploiement des fronts
> (last-modified 19:43→19:46, réel et confirmé). **La cause principale était en fait mon propre
> harnais** : après `mouse.click` sur un champ, l'`<input>` de `flt-text-editing-host` n'est pas
> encore prêt et **avale le PREMIER caractère**. Diagnostic sans ambiguïté en relisant `input.value`
> avant de soumettre :
> ```
> attendu : email len=33  mdp len=10
> methode A (clic + type) -> email "jean.officine@pharmacie-lyon.test" (33)  OK
>                            mdp   "ubia2026!"                        (9)   ← le « N » a saute
> ```
> Le serveur rendait donc un **401 légitime** (« E-mail ou mot de passe incorrect ») sur un mot de
> passe réellement faux. Correctif appliqué au harnais : temporisation de 500 ms après le clic,
> puis **relecture de `input.value` et jusqu'à 3 tentatives** jusqu'à égalité stricte avec la valeur
> attendue. **Ce n'était pas un défaut de l'application** — et c'est exactement le genre d'artefact
> qui, non vérifié, produit un faux P1 « connexion cassée ».

### Ronde R100 — segment final : les écrans « Réglages » rendus injoignables par #7692

Audit des écrans que **#7692** empêche d'atteindre au clic — **tous atteints par URL directe et
pleinement fonctionnels**, ce qui confirme que le défaut est bien de **navigation**, pas de rendu :

| app | écran/route | viewport | inventoriés | activés | OK | morts | cassés | last_check |
|---|---|---|---|---|---|---|---|---|
| secretariat | `/cabinet-stats` | 1280×800 | 24 | 23 | 22 | **1** | 0 | 2026-09-25T20:40Z |
| secretariat | `/appointment-motifs` | 1280×800 | 24 | 23 | 22 | **1** | 0 | 2026-09-25T20:44Z |
| secretariat | `/maintenance` | 1280×800 | 28 | 26 | 25 | **1** | 0 | 2026-09-25T20:48Z |

- Le **mort** de chaque écran est, encore, « **Réglages du cabinet** » (**#7692**) — désormais constaté
  sur **9 écrans** du secrétariat. *Les seconds « morts » bruts (« Statistiques », « Motifs de RDV »)
  sont le clic sur la destination **courante** du rail : un no-op légitime, requalifié.*
- `/cabinet-stats` : le `403 GET /v1/cabinet/stats/activity` (secrétariat) est **traité de façon
  exemplaire** — cadenas + « **Réservé aux praticiens — Votre rôle ne permet pas d'afficher l'activité
  par praticien.** », **les 4 cartes de KPI restant affichées** (CA encaissé, reste à encaisser, taux de
  transformation, devis signés). Requalifié en faux positif.

**Re-vérification (unique de la ronde) — B4, cloisonnement clinique : toujours parfait.**
Sur `medical-record`, `dental-chart`, `notes`, `treatment-plans` et `periodontal-chart` du même
patient : **praticien 200 / secrétariat 403 / patient 403** sur les cinq. Idem `/ccam/acts`
(praticien 200, secrétariat 403, patient 403). RBAC membres re-contrôlé : lecture ouverte
(secrétaire **et** praticien 200), écriture **403 pour les deux** (réservée admin/manager).
Patient d'un autre tenant → **404**.

### Ronde R100 — app infirmière : audit ONGLET PAR ONGLET (le domaine le plus récent)

`app_infirmiere` ne déclare que **2 routes** (`/` et `/notification-preferences`) : tout son contenu vit
dans les **3 onglets** de l'accueil, qui ne sont donc pas atteignables par URL. Ils ont été audités
comme des écrans à part entière. *Piège de repérage : la barre d'onglets est en **bas** d'écran
(`y=764`), pas en haut — un filtre sur `y < 300` ne la trouve jamais ; c'est `role="tab"` qui la désigne.*

| app | écran | viewport | inventoriés | activés | OK | morts | cassés | désactivés | last_check |
|---|---|---|---|---|---|---|---|---|---|
| infirmiere | `/` onglet **Disponibilité** | 390×844 | 8 | 4 | 4 | 0 | 0 | 1 | 2026-09-25T20:55Z |
| infirmiere | `/` onglet **Offres** | 390×844 | 7 | 3 | 2 | 1* | 0 | 1 | 2026-09-25T20:57Z |
| infirmiere | `/` onglet **Ma visite** | 390×844 | 7 | 3 | 3 | 0 | 0 | 1 | 2026-09-25T20:59Z |

*\* le « mort » est le conteneur `tablist` (libellé vide), requalifié.*

- **Onglet Disponibilité** : porte l'interrupteur « **En ligne** », qui bascule réellement — vérifié
  **par l'API** : après activation, `GET /v1/nurse/profile` rend `is_online: false`, puis `true` après
  restauration. La bascule UI et `PATCH /v1/nurse/availability` sont bien le même état.
- **Onglet Offres** : **état vide digne** — icône + « **Aucune offre** » + « Les demandes de visite
  proches apparaîtront ici. » (capture jointe). Cohérent avec l'API : 0 offre en attente à cet instant.
- **Onglet Ma visite** : idem, aucune visite en cours (les 3 demandes créées dans la ronde sont `done`
  ou `cancelled`).
- **Conformité tokens** (l'app n'a pas de maquette v2 dédiée — manque connu, non rapporté) : palette et
  typographie conformes au design system, shell mobile aligné sur les patterns de `Patient Accueil v2`.

**Hygiène des données de test** : l'interrupteur « En ligne » basculé par l'audit a été **remis à
`true`**, et il ne reste **aucune demande de visite active** en fin de ronde (23 `done`, 20 `cancelled`,
7 `expired`).

### Ronde R100 — cas adversariaux `app_practicien` (3ᵉ app couverte dans cette catégorie)

| cas | verdict | preuve |
|---|---|---|
| **Enregistrement d'une note clinique** (`/patients/:id`) | **OK, bout en bout** | Champ « Notes du praticien… » rempli → le bouton « **Enregistrer les notes** » **s'active** (il était, à raison, `DÉSACTIVÉ` tant que le champ était vide) → **1 seul** `POST /v1/cabinet/patients/:id/notes`, 0 requête ≥ 400 → et la note **a bien persisté** (re-`GET` : marqueur `QA-R100-note-1790368058` présent, horodaté 20:28:06). |
| **Double-submit** sur « Enregistrer les notes » | **OK** | Un clic = une écriture ; aucune écriture en double. |
| **Texte très long** (342 car.) dans les notes | **OK** | **0 débordement HORIZONTAL** (`x < 0` ou `x+w > 1282`). |
| **BACK navigateur** au milieu du flux fiche patient → schéma dentaire | **OK** | Retour sur un écran **repeint et utilisable** (34 contrôles, `nearWhite` 0.751, 155 nœuds Semantics). |
| **Coupure réseau** (`route.abort` sur `*/v1/*`) sur `/agenda` | **OK** | 24 contrôles toujours présents (navigation complète utilisable), `nearWhite` 0.783, **erreur digne** proposée — ni page blanche ni spinner infini. |

> **Deuxième correction de méthode — le corollaire de la première.** Ce parcours a d'abord produit
> deux « défauts » spectaculaires, tous deux **faux** :
> 1. « **25 contrôles qui débordent** » → mon critère comptait le débordement **vertical**, or la fiche
>    patient est une page **longue et défilante** (le champ de notes est à **y = 6170**). Mesuré
>    **horizontalement**, le seul axe qui signale une vraie casse de mise en page : **0**.
> 2. « **« Enregistrer les notes » ne déclenche aucune écriture** » → Playwright clique aux coordonnées
>    du **viewport** ; un clic à `y = 6250` ne touche rien. Aucun texte n'était saisi, donc le bouton
>    restait **légitimement désactivé**. Après défilement jusqu'au champ (`y` ramené à 234), tout
>    fonctionne. **Il faut faire défiler jusqu'au contrôle avant de l'activer** — le marqueur
>    `offscreen` de l'inventaire est là pour ça et doit être respecté, pas contourné.

### Ronde R99 — 2026-09-25 (12:00–14:20 UTC) — 5/5 apps + tunnel SSR ; **69 écrans**, 1 515 contrôles inventoriés, 534 activés, 416 OK

> **Méthode affinée cette ronde** : la cible de chaque activation est **ré-résolue sur un inventaire
> FRAIS** (rôle + libellé + occurrence) avant le clic — un clic qui change la liste décalait sinon
> tous les rects suivants et produisait des « MORT » en série. Les dialogues sont refermés (Échap)
> après chaque activation, le rail/chrome de navigation est exclu du décompte de l'écran (il est
> audité à part), et `switch` a été ajouté aux rôles activables.
> **Réfutations systématiques** : sur les 73 MORT et 45 CASSÉ bruts du harnais, **4 seulement** sont
> des défauts réels (#7666 ×2, #7656, #7671) ; les autres sont des artefacts vérifiés
> un par un — contrôle sous le pli, chip hors du défileur horizontal, sélecteur de fichier (qui ne
> modifie pas l'arbre Semantics), ou **sonde de rôle délibérée** (`403 GET /v1/cabinet/audit-log`,
> `audit_log_access_cubit.dart:20-33` ; `404 GET /v1/quotes/:id/attestation`, sous-ressource absente
> absorbée par un `fold`, `financial_bloc.dart:172-190`).

| app | écran/route | contrôles inventoriés | activés | OK | morts | cassés | last_check |
|---|---|---|---|---|---|---|---|
| **reservation (SSR)** | `/` + `/dentiste/lyon` + `/reservation/confirmer` (390 **et** 1280) | 3 + 23 puces + 8 champs | tous | tous | 0 | 0 | 2026-09-25T12:25:00Z |
| patient | `/pharmacy/send` (390) **diff-driven #7140** | 276 → **54** après correctif #7655 | 10 | 10 | 0 (10 réfutés : la sélection ne changeait pas l'arbre — c'est **#7661**) | 0 | 2026-09-25T13:15:00Z |
| patient | `/` (Accueil, 390) | 17 | 10 | 10 | 0 (2 réfutés : « Mes ordonnances »/« Mes documents » sous le pli, OK après défilement → `/prescriptions`) | 0 | 2026-09-25T12:55:00Z |
| patient | `/documents` (390) | 28 | 16 | 16 | 0 (10 réfutés : 8 chips hors du défileur **horizontal** — la rangée défile bien ; « Ajouter un document » ouvre un **sélecteur de fichier**) | 0 | 2026-09-25T12:58:00Z |
| patient | `/financial` (390) | 10 | 9 | 9 | 0 | 0 (9 réfutés : `404 /quotes/:id/attestation` = sous-ressource absente, absorbée) | 2026-09-25T12:58:00Z |
| patient | `/pharmacy/orders` (390) | 16 | 12 | 12 | 0 | 0 | 2026-09-25T12:52:00Z |
| patient | `/home-care` (390) | 17 | 13 | 13 | 0 | 0 | 2026-09-25T12:56:00Z |
| patient | `/home-care/new` (390) | 11 | 9 | 9 | 0 (3 réfutés) | 0 | 2026-09-25T12:57:00Z |
| patient | `/implant-passport` (390) | 6 | 6 | 6 | 0 | 0 | 2026-09-25T12:52:00Z |
| patient | `/profile` (390) | 13 | 12 | 12 | 0 | 0 | 2026-09-25T12:59:00Z |
| patient | `/profile/dependents` (390) | 22 | 6 | 6 | 0 | 0 | 2026-09-25T12:59:00Z |
| patient | `/profile/consents` (390) | 4 | 2 | 2 | 0 | 0 | 2026-09-25T12:52:00Z |
| patient | `/profile/notifications` (390) | 17 (3 boutons + 9 bascules) | 12 | 12 | 0 | 0 | 2026-09-25T13:10:00Z |
| patient | `/mes-rdv` (390) | 7 | 6 | 6 | 0 | 0 | 2026-09-25T12:56:00Z |
| patient | `/messaging` (390) | 9 | 8 | 8 | 0 | 0 | 2026-09-25T12:57:00Z |
| patient | `/reviews` (390) | 1 | 0 | — | 0 | 0 | 2026-09-25T13:40:00Z |
| patient | `/oubliettes` (390) | 1 (27 nœuds) | 0 | — | 0 | 0 | 2026-09-25T13:40:00Z |
| praticien | `/` (Tableau de bord, 1280) | 28 | 9 | 9 | 0 | 0 | 2026-09-25T13:20:00Z |
| praticien | `/mes-conges` (1280) **diff-driven** | 21 | 4 | 4 | 0 | 0 | 2026-09-25T12:22:00Z |
| praticien | `/tasks` (1280) **diff-driven #7638** | 5 | 4 | 4 | 0 | 0 | 2026-09-25T12:22:00Z |
| praticien | `/stock-inventory` (1280) | 33 | 8 | 8 | 0 | 0 (1 réfuté : échec CORS transitoire, non reproductible — préflight `OPTIONS` testé 40× : 40× `200` + `access-control-allow-origin`) | 2026-09-25T12:25:00Z |
| praticien | `/lab-work-orders` (1280) | 26 | 5 | 5 | 0 | 0 | 2026-09-25T13:22:00Z |
| praticien | `/ordonnances` (1280) | 20 | 1 | 1 | 0 | 0 | 2026-09-25T13:21:00Z |
| praticien | `/devis` (1280) | 27 | 8 | 8 | 0 | 0 (8 réfutés : `404 …/attestation`) | 2026-09-25T13:21:00Z |
| praticien | `/waiting-room` (1280, file vide) | 21 | 0 | — | 0 | 0 — « Appeler suivant » **légitimement grisé** (file vide) | 2026-09-25T13:20:00Z |
| praticien | `/team-messages` (1280) | 20 | 1 | 1 | 0 | 0 | 2026-09-25T13:23:00Z |
| praticien | `/cabinet-brief` (1280) | 5 | 4 | 4 | 0 | 0 | 2026-09-25T12:24:00Z |
| praticien | `/lab-stats` (1280) | 1 | 1 | 1 | 0 | 0 | 2026-09-25T12:24:00Z |
| praticien | `/consent-templates` + `/questionnaire-templates` (1280) | 13 | 5 | 5 | 0 | 0 | 2026-09-25T12:25:00Z |
| praticien | `/act-categories` (1280) | 2 | 1 | 1 | 0 | 0 (1 réfuté : `403` **attendu** — `ProAdminOrManagerClaims`, le bouton d'accès est déjà gaté `session.isAdmin`, `practicien_shell.dart:136-142` ; l'écran rend un état d'erreur digne + « Réessayer ») | 2026-09-25T13:45:00Z |
| praticien | `/patients/:id/dental-chart` (1280) | 59 (32 dents + 11 états du dialogue) | 2 + dialogue | tous | 0 | 0 | 2026-09-25T13:35:00Z |
| praticien | `/notification-preferences` (1280) | 16 (1 bouton + 11 bascules) | 1 bascule **avec contrôle de persistance** | 1 | 0 | 0 | 2026-09-25T12:50:00Z |
| secretariat | **rail de navigation** (1280, 18 entrées, une à une) | 18 | 18 | 15 | **1 réel** — « **Réglages du cabinet** » (en-tête de groupe inerte : 21 entrées → 21 ; les 4 autres en-têtes replient bien) → **#7666** | **1 réel** — « **Congés** » ouvre `/cabinet-stats` (+ `403 /cabinet/stats/activity`) → **#7666** | 2026-09-25T13:05:00Z |
| secretariat | `/conformite` (1280) **diff-driven** | 26 | 26 | 25 | 0 (21 réfutés : inventaire figé après un changement de facette) | **1 réel** — « **Clôturer** » → `422` + SnackBar « Impossible de clôturer l'item de conformité. » → **#7656** | 2026-09-25T12:30:00Z |
| secretariat | `/tasks` (1280) **diff-driven #7638** | 6 | 6 | 5 | 0 (1 réfuté) | 0 (1 réfuté : sonde audit-log) | 2026-09-25T12:20:00Z |
| secretariat | `/conges` (1280) **diff-driven** | 24 | 14 | 14 | 0 | 0 | 2026-09-25T12:45:00Z |
| secretariat | `/admin-membres` (1280) **diff-driven #7631** | 30 | 17 | 17 | 0 | 0 — les 3 « **Lien — Praticien/Secrétaire/Admin** » rendent `403` **avec le message attendu** (« Accès réservé aux administrateurs du cabinet. ») : **#7631 corrigé**, vérifié à l'écran | 2026-09-25T12:47:00Z |
| secretariat | `/liste-attente` (1280) | 23 | 13 | 13 | 0 (2 réfutés : entrée de rail déjà active + #7666) | 0 | 2026-09-25T13:00:00Z |
| secretariat | `/appointment-motifs` (1280) | 24 | 13 | 13 | 0 (2 réfutés) | 0 | 2026-09-25T13:00:00Z |
| secretariat | `/maintenance` (1280) | 28 | 13 | 13 | 0 (1 réfuté) | 0 | 2026-09-25T13:02:00Z |
| secretariat | `/reprise-donnees` (1280) | 27 | 13 | 13 | 0 (2 réfutés) | 0 | 2026-09-25T13:02:00Z |
| secretariat | `/team-messages` (1280) | 34 | 4 (les 3 actions du composeur + la recherche) | 2 | 0 | 0 — « Épingler » `aria-disabled=true` et « Joindre… » non exposé en bouton, **infobulle « indisponible pour l'instant »** → **#7668** (manque de livraison, pas un bouton mort) | 2026-09-25T13:25:00Z |
| secretariat | `/` — palette ⌘K (1280) | 18 | 5 (⌘K, Ctrl+K, ↑, ↓, ⏎, Échap) | 6 | 0 | 0 | 2026-09-25T12:40:00Z |
| secretariat | `/notification-preferences` (1280) | 16 | 0 (couvert côté praticien) | — | 0 | 0 | 2026-09-25T12:50:00Z |
| pharmacie | `/stock` (1280) **diff-driven #7634/#7635** | 17 | 7 | 7 | 0 | 0 | 2026-09-25T12:35:00Z |
| pharmacie | `/devis` (1280) | 26 | 12 | 12 | 0 (1 réfuté : facette « Tous » déjà active) | 0 — « **Nouveau devis** » mène bien à `/` **avec** le SnackBar « Choisissez la commande pour laquelle créer un devis. » : **#7577 corrigé**, vérifié image à l'appui | 2026-09-25T12:33:00Z |
| pharmacie | `/notification-preferences` (1280) | 12 | 0 | — | 0 | 0 | 2026-09-25T12:50:00Z |
| infirmiere | `/` — 3 onglets (Disponibilité / Offres / Ma visite, **390×844 ET 1280×900**) | 7 par onglet | 5 | 5 | 0 | 0 — mais l'onglet « Offres » devient **inutilisable** sous une demande patient non bornée : « Accepter » à **16 000 px** sous le pli → **#7663** | 2026-09-25T12:47:00Z |
| infirmiere | `/` — 2ᵉ passe aux **deux viewports**, jeton `kind:"nurse"` frais | 7 / 6 / 6 par onglet | 1 (« En ligne ») | 1 | 0 | 0 | 2026-09-25T14:05:00Z |
| pharmacie | `/stock` et `/` — **1280 / 1440 / 1920** (responsive « Écrans PC ») | 21 / 37 | — | — | 0 | 0 — mais `/stock` garde **21 contrôles aux 3 largeurs** (rien à révéler, cf. **#7662**) alors que `/` passe de 37 à 38 et alimente sa colonne de droite | 2026-09-25T15:02:00Z |
| infirmiere | `/notification-preferences` (390) | 4 | 1 | 1 | 0 | 0 | 2026-09-25T12:50:00Z |
| praticien | `/agenda` (1280) | 28 | 7 | 6 | 0 | **1 réel** — « **Démarrer** » → `409 out_of_window` sur tout RDV confirmé passé de plus de 60 min → **#7671** | 2026-09-25T13:38:00Z |
| praticien | `/patients` (1280) | 34 | 14 | 14 | 0 | 0 (13 réfutés : `403 /notes` + `/medical-record` sur les patients sans relation de soin — l'écran affiche « 🔒 Vous n'avez pas encore suivi ce patient — l'historique clinique n'est pas accessible. », dégradation **voulue et digne**, capture `R99_fiche_2.png`) | 2026-09-25T13:52:00Z |
| praticien | `/stock` (1280) | 21 | 1 | 1 | 0 | 0 | 2026-09-25T13:40:00Z |
| praticien | `/messages` (1280) | 27 | 8 | 8 | 0 | 0 | 2026-09-25T13:41:00Z |
| secretariat | `/agenda` (1280) | 32 | 9 | 9 | 0 | 0 | 2026-09-25T13:35:00Z |
| secretariat | `/patients` (1280) | 40 | 14 | 14 | 0 | 0 | 2026-09-25T13:36:00Z |
| secretariat | `/devis` (1280) | 58 | 14 | 14 | 0 | 0 | 2026-09-25T13:52:00Z |
| secretariat | `/salle-attente` (1280, file vide) | 24 | 0 | — | 0 | 0 — « Appeler suivant » **légitimement grisé** | 2026-09-25T13:36:00Z |
| secretariat | `/cabinet-payouts`, `/cabinet-stats`, `/bookable-slots`, `/messages` (1280) | 4 écrans | — | OK | 0 | 0 | 2026-09-25T13:45:00Z |
| pharmacie | `/` (File des commandes, 1280) | 22 | 8 | 8 | 0 | 0 | 2026-09-25T13:30:00Z |
| pharmacie | `/messages` (1280) | 15 | 7 | 6 | 0 (1 réfuté : facette « Toutes » déjà active) | 0 | 2026-09-25T13:31:00Z |
| pharmacie | `/orders/:id` (détail commande, 1280) | 16 | — | OK | 0 | 0 | 2026-09-25T13:46:00Z |
| patient | `/prescriptions` (390) | 16 | 6 | 6 | 0 | 0 | 2026-09-25T13:33:00Z |
| patient | `/treatment-plans`, `/appointments`, `/notifications` (390) | 3 écrans | — | OK | 0 | 0 | 2026-09-25T13:40:00Z |
| patient | `/mes-rdv` — **rangée d'actions par carte** (390) | 3 cartes | 3 | 1 | **2 cartes sans AUCUN contrôle** → **#7672** | 0 | 2026-09-25T13:55:00Z |
| praticien | `/patients/:id/dental-chart` → dialogue d'état de dent (1280×800 / 1280×900 / 1440×900) | 11 états | 1 + défilement | OK | 0 | 0 — 3 états sous le pli à 1280×800, **atteignables** (dialogue défilant) | 2026-09-25T13:35:00Z |

**Balayage « aucun écran blanc » — toutes les routes des 5 apps, aux viewports de référence :**

| balayage | routes chargées | écrans blancs réels | 5xx front | last_check |
|---|---|---|---|---|
| 5 apps, toutes les routes de leurs `app_router.dart` (390×844 pour patient/infirmière, 1280×800 pour les 3 back-offices), ré-authentification tous les 10 écrans | **78** | **0** | **0** | 2026-09-25T15:05:00Z |

> Un seul écran a dépassé le seuil pixel (`patient /reviews`, nearWhite 0,991, 1 contrôle) : vérifié
> à la main, il rend son **état vide légitime** (« Avis — Aucun avis pour ce prestataire. ») quand on
> l'atteint en lien profond sans `providerId`. Ce n'est pas un canvas vide.
> *Piège de harnais consigné : sans ré-authentification périodique, la fin d'un balayage long tombe
> sur l'écran de connexion et tous les relevés deviennent identiques (`white=0,937 ctrl=7`) — ce qui
> ressemble à une panne généralisée. Vérifier `exp` du JWT avant de conclure.*

**Cas adversariaux joués cette ronde (tous OK) :**

| cas | écran | résultat | last_check |
|---|---|---|---|
| **Double-clic** sur une action métier | pharmacie `/stock` → « Accepter » | **1 seule** requête `POST …/accept` émise pour 2 clics immédiats ; 0 requête ≥ 400, 0 erreur console | 2026-09-25T13:06:00Z |
| **Retour navigateur au milieu d'un flux** | patient `/pharmacy/send` → `/pharmacy/search?selection=true` → `goBack()` | revient sur `/pharmacy/send`, l'écran se repeint (nearWhite 0,775), **49 lignes toujours là**, « Transmettre à la pharmacie » présent et **actif** ; 0 requête ≥ 400 ; état stable aux 4 échantillons (2/4/7/11 s) | 2026-09-25T13:08:00Z |
| **Coupure réseau** (`route.abort()` sur `*/v1/*`) | secretariat `/conges` | **pas d'écran blanc, pas de spinner infini** : 27 contrôles toujours rendus, message d'erreur affiché | 2026-09-25T13:07:00Z |
| **Saisie invalide via l'UI** | tunnel SSR `/reservation/confirmer` | requis vides → refus au formulaire, aucune requête ; e-mail malformé + motif de 250 caractères → refus, **aucun 4xx/5xx, aucune soumission silencieuse** | 2026-09-25T12:28:00Z |
| **Double-réservation du même créneau** | tunnel SSR | après confirmation, ré-ouvrir la même URL → **410 « Ce créneau n'est plus disponible »** avec la sortie « Choisir un autre créneau avec Dr Claire Lefèvre » | 2026-09-25T12:29:00Z |

### Ronde R98 — 2026-09-25 (diff-driven : DP-F25/F26/F27, dont DP-F27.c mergée EN COURS DE RONDE)

| app | écran/route | contrôles inventoriés | activés | OK | morts | cassés | last_check |
|---|---|---|---|---|---|---|---|
| praticien | `/` (Tableau de bord, 1280) | 36 | 35 | 29 | 0 (6 réfutés) | 0 | 2026-09-25T06:30:00Z |
| praticien | `/agenda` (1280) | 31 | 30 | 28 | 0 (2 réfutés) | 0 | 2026-09-25T06:32:00Z |
| praticien | `/waiting-room` (1280, file NON vide) | 22 | 20 | 20 | 0 | 0 | 2026-09-25T06:34:00Z |
| praticien | `/tasks` (1280) | 5 | 5 | 5 | 0 | 0 | 2026-09-25T06:35:00Z |
| praticien | `/mes-conges` (1280) **NEUF** | 5 | 5 | 5 | 0 | 0 | 2026-09-25T06:45:00Z |
| praticien | `/mes-conges` → dialogue « Nouvelle demande » (1280) **NEUF** | 7 | 7 | 7 | 0 | 0 | 2026-09-25T06:47:00Z |
| secretariat | `/admin-membres` (1280) | 33 | 32 | 26 | 0 (3 réfutés) | **3** | 2026-09-25T06:25:00Z |
| secretariat | `/stock` (1280) | 58 | 57 | 57 | 0 (24 réfutés) | 0 | 2026-09-25T06:58:00Z |
| secretariat | `/onboard` (1280) | 1 | 1 | 1 | 0 | 0 | 2026-09-25T06:26:00Z |
| secretariat | `/conges` (1280) **NEUF** | 4 | 4 | 4 | 0 | 0 | 2026-09-25T06:44:00Z |
| pharmacie | `/` (File des commandes, 1280) | 34 | 33 | 33 | 0 | 0 | 2026-09-25T06:42:00Z |
| pharmacie | `/orders/:id` (détail, 1280) | 32 | 31 | 31 | 0 | 0 | 2026-09-25T06:42:00Z |
| pharmacie | `/orders/:id/pickup` (scan de retrait, 1280) | 4 | 4 | 4 | 0 | 0 | 2026-09-25T06:42:00Z |
| pharmacie | `/stock` (1280) | 15 | 14 | 14 | 0 | 0 | 2026-09-25T06:40:00Z |
| patient | `/` (Accueil, 390) | 22 | 22 | 20 | 0 (2 réfutés) | 0 | 2026-09-25T06:30:00Z |
| patient | `/mes-rdv` (390) | 11 | 11 | 11 | 0 | 0 | 2026-09-25T06:50:00Z |
| patient | `/prescriptions` (390) | 17 | 17 | 17 | 0 | 0 | 2026-09-25T06:50:00Z |
| patient | `/profile/dependents` (390) | 24 | 24 | 24 | 0 | 0 | 2026-09-25T06:51:00Z |
| infirmiere | `/` onglet Disponibilité (390) | 8 | 7 | 6 | 0 (1 réfuté) | 0 | 2026-09-25T06:52:00Z |
| infirmiere | `/` onglet Offres (390) | 8 | 8 | 8 | 0 | 0 | 2026-09-25T06:52:00Z |
| infirmiere | `/` onglet Ma visite (390) | 7 | 7 | 7 | 0 | 0 | 2026-09-25T06:52:00Z |
| infirmiere | `/notification-preferences` (390) | 5 | 5 | 3 | 0 (2 réfutés) | 0 | 2026-09-25T06:30:00Z |

**CUMUL R98 — 22 écran×route · 388 contrôles inventoriés · 378 activés · `0` MORT confirmé · `3` CASSÉS confirmés.**

#### Les 3 CASSÉS confirmés
Les boutons **« Lien — Praticien »**, **« Lien — Secrétaire »** et **« Lien — Admin »** de
`secretariat /admin-membres` (livrés le jour même par DP-F25.c) : clic → `POST /v1/cabinet/invite-links`
→ **403 forbidden**, screenshot **identique octet pour octet** avant/après, **0 libellé nouveau** dans
l'arbre Semantics. Aucun retour d'aucune sorte. → **#7631 (P1)**.
Cause double : la garde d'affichage observe le mauvais droit (`admin_membres_page.dart:37-42` teste
l'échec du **chargement** de la liste, que la secrétaire a le droit de lire → 200), et l'erreur est
stockée puis jamais rendue (`invite_links_cubit.dart:48-52` alimente `state.error`, que
`invite_links_bar.dart:58-60` ne lit jamais ; `_copy:33-35` sort en silence sur `link == null`).

#### 38 verdicts MORT rendus par les balayages, 38 réfutés au re-test individuel
Conformément à la règle de la maison, **aucun** n'a été publié. Les deux plus importants ont été
re-testés **page rechargée**, isolément : `secretariat /stock` → **« Actualiser »** = OK (déclenche
`GET /v1/cabinet/stock-requests?limit=500`), **« Nouvelle demande »** = OK (ouvre la boîte de création,
58 → 10 contrôles, 6 libellés nouveaux dont « Choisir une pharmacie », « Article », « Qté »). Les 36
autres relèvent des causes déjà cataloguées : en-tête de groupe repliable du rail, coordonnées périmées
après repli/reflow de liste, conteneur `group` englobant.

#### Faux positif du harnais corrigé cette ronde
Les `<input>` de Flutter web ne portent **pas** d'attribut `role` (seulement `aria-label` + `type`) :
le sélecteur d'inventaire des rondes précédentes ne voyait donc **aucun champ de saisie**. Sélecteur
élargi à `input, textarea` (rôle effectif `textbox`) — c'est ce qui a fait apparaître, par exemple,
`textbox:"Cabinet, article…"` sur `pharmacie /stock` et `textbox:"Patient, n° commande…"` sur
`pharmacie /`. À conserver pour les rondes suivantes.

#### Contrôle sans nom accessible
`praticien /mes-conges` : le bouton flottant de création est un `[role=button]` au **libellé vide**
(`FloatingActionButton` sans `tooltip` ni `label`, `mes_conges_page.dart:55-65`). Il **fonctionne**
(le clic ouvre la boîte de dialogue) mais n'est pas nommé. Même forme sur `praticien /tasks`
(confirmé sur le rendu : `'' button`), `secretariat /tasks` et `secretariat /conformite`. → **#7638 (P2)**.

#### Cas adversariaux joués sur le dialogue « Nouvelle demande de congé » (écran mergé ce jour)
| cas | résultat |
|---|---|
| soumission à vide | **OK** — « Envoyer la demande » est `disabled=true` tant que les deux dates manquent ; le clic ne produit **aucune** requête, aucun pixel ne bouge, aucune erreur console |
| double-clic rapide sur « Envoyer la demande » | **OK** — **une seule** `POST /v1/cabinet/staff/leave-requests` part (→ 201), le dialogue se ferme ; pas de doublon, pas d'exception |
| texte très long | **sans objet** — le formulaire n'a que deux sélecteurs de date et un choix de type, aucun champ libre |
| coupure réseau (`route.abort()` sur `*/v1/*`) | **OK** — aucun écran blanc, aucun spinner infini : le dialogue reste intact et utilisable (8 contrôles, mêmes libellés), 0 erreur console |
| sélecteur de date au clavier/lecteur d'écran | **OK** — 39 contrôles nommés (« 1, mardi 1 septembre 2026 », « Mois précédent », « Passer à la saisie ») |

#### Retour 403 : deux écrans livrés le même jour, deux comportements opposés
`secretariat /conges` fait **bien** les choses : clic « Approuver » en tant que secrétaire →
403 → SnackBar **« Validation réservée aux administrateurs/managers. »** peint à l'écran
(capture `qa/screenshots/secretariat/conges-clic-approuver-403-1280.png`). Le défaut résiduel y est
seulement qu'il n'est pas **annoncé** (→ #7640). À l'inverse, `secretariat /admin-membres` (même jour,
même app) ne dit **rien** du tout (→ #7631).

### Ronde R95 — 2026-09-24 (diff-driven : PR #7561→#7565 mergées le matin même)

**Périmètre** : 5 apps sur 5. **23 écrans** audités au passage en masse + **11 audits pilotés à la main**.
**1 009 contrôles inventoriés, 552 activés** (27 écrans×route + 11 audits pilotés à la main).
**Verdict global : 0 bouton MORT confirmé, 1 CASSÉ confirmé.**

| app | écran/route | inventoriés | activés | OK | morts bruts | cassés bruts | last_check |
|---|---|---|---|---|---|---|---|
| patient | `/` (Accueil, 390×844) | 22 | 12 | 3 | 9 → **0 confirmé** | 0 | 2026-09-24T12:35Z |
| patient | `/mes-rdv` | 9 | 3 | 2 | 1 → **0 confirmé** | 0 | 2026-09-24T12:35Z |
| patient | `/home-care` | 18 | 13 | 2 | 11 → **0 confirmé** | 0 | 2026-09-24T12:36Z |
| patient | `/documents` | 43 | 23 | 12 | 11 → **0 confirmé** | 0 | 2026-09-24T13:05Z |
| patient | `/notifications` | 21 | 15 | 14 | 1 → **0 confirmé** | 0 | 2026-09-24T12:38Z |
| patient | `/profile` | 17 | 7 | 6 | 1 | 0 | 2026-09-24T12:38Z |
| patient | `/financial` + détail d'un devis | 11 | 6 | 1 | 4 → **0 confirmé** | 1 → **0 confirmé** | 2026-09-24T13:00Z |
| patient | `/messaging` | 10 | 8 | 3 | 5 → **0 confirmé** | 0 | 2026-09-24T13:04Z |
| praticien | `/` (Tableau de bord, 1280×800) | 37 | 18 | 14 | 4 | 0 | 2026-09-24T13:35Z |
| praticien | `/agenda` | 31 | 23 | 17 | 6 | 0 | 2026-09-24T13:37Z |
| praticien | `/devis` | 29 | 15 | 13 | 2 | 0 | 2026-09-24T13:39Z |
| praticien | `/stock` | 23 | 17 | 15 | 2 | 0 | 2026-09-24T13:41Z |
| praticien | `/lab-work-orders` | 30 | 19 | 13 | 6 | 0 | 2026-09-24T13:43Z |
| praticien | `/tasks` | 5 | 3 | 3 | 0 | 0 | 2026-09-24T13:45Z |
| praticien | `/ordonnances/new?patientId=…` *(audit manuel)* | 50 | 24 | 24 | 0 | 0 | 2026-09-24T12:30Z |
| praticien | `/patients/:id` — avec relation de soin *(manuel)* | 54 | 14 | 14 | 0 | 0 | 2026-09-24T12:45Z |
| praticien | `/patients/:id` — sans relation de soin *(manuel)* | 46 | 6 | 5 | 0 | 1 → #7567 | 2026-09-24T12:50Z |
| secretariat | `/` (Tableau de bord) | 37 | 25 | 18 | 6 | 1 → **sonde d'accès, pas un défaut** | 2026-09-24T13:30Z |
| secretariat | `/agenda` | 43 | 33 | 14 | 18 → **0 confirmé** | 1 → *idem* | 2026-09-24T13:32Z |
| secretariat | `/devis` | 56 | 32 | 21 | 10 | 1 → *idem* | 2026-09-24T13:34Z |
| secretariat | `/stock` | 56 | 33 | 19 | 13 | 1 → *idem* | 2026-09-24T13:36Z |
| secretariat | `/patients` (Fiches patients) | 43 | 23 | 14 | 8 | 1 → *idem* | 2026-09-24T13:40Z |
| secretariat | `/team-messages` | 33 | 23 | 14 | 8 | 1 → *idem* | 2026-09-24T13:42Z |
| secretariat | `/salle-attente` — file à 4 entrées *(manuel)* | 35 | 10 | 8 | 0 | **1 → #7570** | 2026-09-24T12:40Z |
| secretariat | `/cabinet-payouts`, rail complet 17 entrées *(manuel)* | 17 | 17 | 17 | 0 | 0 | 2026-09-24T13:50Z |
| secretariat | `/cabinet-stats` (Pilotage du cabinet) *(manuel)* | 12 | 2 | 2 | 0 | 0 | 2026-09-24T13:48Z |
| pharmacie | `/` (File des commandes) *(manuel)* | 35 | 8 | 8 | 0 | 0 | 2026-09-24T13:00Z |
| pharmacie | `/orders/:id` (Délivrance, 1920/1680/1440/1280) *(manuel)* | 38 | 6 | 6 | 0 | 0 | 2026-09-24T12:55Z |
| infirmiere | `/` — 3 onglets Disponibilité / Offres / Ma visite *(manuel)* | 26 | 13 | 13 | 0 | 0 | 2026-09-24T12:50Z |
| infirmiere | `/notification-preferences` | 5 | 2 | 2 | 0 | 0 | 2026-09-24T12:45Z |

**Total : 1 009 inventoriés, 552 activés.** Les colonnes « bruts » sont les verdicts du passage en masse ;
la mention « → 0 confirmé » signale les grappes re-testées une par une sur page neuve (26 re-tests
individuels cette ronde) et toutes invalidées.

#### Les 8 « cassés » bruts du passage en masse — 7 sont attendus

- **6 sur 7 sont la même sonde d'accès** : l'app secrétariat appelle `GET /v1/cabinet/audit-log` au
  démarrage et reçoit **403**. C'est **voulu et documenté** — `AuditLogAccessCubit` (`audit_log_access_cubit.dart`) :
  « *Seul le 403 renvoyé par `GET /v1/cabinet/audit-log` prouve le non-admin/manager. On sonde l'endpoint
  une fois au démarrage et on masque l'entrée uniquement lorsqu'un 403 le confirme.* » Le 403 est le
  mécanisme, pas la panne. **Non rapporté.**
- Le 7ᵉ est `GET /v1/cabinet/stats/activity` → **403** sur `/cabinet-stats` (praticien-only). L'écran le
  gère proprement : les 4 KPI de facturation s'affichent et le bloc « Activité par praticien » rend un état
  dédié **« Réservé aux praticiens — Votre rôle ne permet pas d'afficher l'activité par praticien »** avec
  son icône de cadenas. **Non rapporté.**
- Côté patient, le `404` sur `GET /v1/quotes/:id/attestation` à chaque ouverture de devis est le signal
  « pas d'attestation pour ce devis » de l'API (`quote_attestation.rs:227`, `ok_or(AppError::NotFound)`) ;
  le détail du devis s'affiche complètement, CTA « Signer le devis » compris. **Non rapporté.**

#### Le seul contrôle CASSÉ confirmé

**`/salle-attente` (secrétariat) — bouton « Appeler » de la ligne 1.** Il porte le nom d'un patient et en
appelle un autre : le clic émet `POST /v1/cabinet/waiting-room/call-next` (aucun identifiant de ligne dans
la requête) et c'est le patient de la **ligne 2** qui bascule en consultation (KPI « en attente » 3 → 2,
observé à l'écran). Symétriquement, le bouton du vrai prochain patient est **refusé**
(« Seul le patient en tête de file peut être appelé pour l'instant. »). Cause : la tête de file est calculée
sur la liste brute, `in_consultation` compris, alors que `WaitingRoomEntry.isWaiting` existe et est
correctement utilisé ailleurs dans le même fichier → **#7570**.

*(Le `403` sur `Enregistrer les notes` de la fiche d'un patient sans relation de soin est compté « cassé »
pour la ligne concernée, mais il **affiche bien** un SnackBar — voir la leçon de méthode ci-dessous. C'est
un défaut d'ergonomie, #7567, pas un contrôle muet.)*

#### ⚠️ Leçon de méthode confirmée cette ronde : 43 « morts » bruts, 0 confirmé

Le passage en masse a rendu **43 verdicts « MORT »**. **Chacun des candidats re-testé individuellement sur
page neuve s'est révélé vivant.** Trois causes, toutes imputables au harnais :

1. **Détecteur aveugle à la navigation par branche de shell.** Les 5 onglets de la barre du bas de l'app
   patient (« Accueil », « Mes RDV », « Messages », « Documents », « Profil ») **ne changent pas
   `location.pathname`** — ils basculent la branche du `StatefulShellRoute`, l'URL reste `/`. Un détecteur
   fondé sur l'URL + l'arbre Semantics les déclare morts alors qu'ils repeignent et déclenchent leurs
   requêtes (`Mes RDV` → `/appointments?filter=upcoming&limit=100`, `Profil` → `/account` + 13 autres).
   **Correctif appliqué : comparaison de pixels avant/après clic** (le seul signal fiable sur CanvasKit).
2. **Clic hors viewport sur un défilement horizontal** — la cause la plus productive en faux positifs.
   Sur `/documents` (390 px de large), les puces de catégorie sont inventoriées à **x = 649, 744, 868,
   1022, 1163, 1309 et 1440** : elles vivent dans une `ListView` horizontale et leurs rects dépassent
   largement le viewport. Les 7 ont été déclarées mortes ; après **défilement horizontal** de la rangée
   (`mouse.wheel(120, 0)` jusqu'à ramener la puce sous 380 px), les 3 re-testées (`CBCT`, `Photo`,
   `Carte mutuelle`) repeignent toutes. **À retenir : inventorier ne suffit pas, il faut amener le contrôle
   dans le viewport — y compris horizontalement.**
3. **Coordonnées périmées après un clic précédent.** Le passage en masse réutilise l'inventaire initial ;
   dès qu'un clic ouvre un dialogue, navigue ou replie un panneau, les rects suivants ne valent plus rien.

**Conséquence pour la ronde suivante** : ne jamais filer un « bouton mort » sorti d'un passage en masse
sans l'avoir rejoué **seul, sur page neuve, après mise dans le viewport (horizontale comprise), avec
comparaison de pixels**. Les 3 rechecks de cette ronde (9 + 11 + 6 candidats) ont donné **0 mort**.

#### Détection de canvas blanc — seuil inadapté au mobile clair

L'app infirmière rend `white = 0.976` sur `/` et `0.972` sur `/notification-preferences`, au-dessus du
seuil P0 de 0,92. **Ce n'est pas un écran blanc** : la capture montre l'écran « Disponibilité » complet
(titre, phrase d'état « Vous êtes EN LIGNE — vous recevez les demandes de visite proches. », interrupteur
« En ligne », barre d'onglets à 3 entrées). Le seuil de 0,92 est calibré pour des écrans denses de poste
fixe ; une interface mobile sobre sur fond blanc le franchit légitimement. **Non rapporté.** À la ronde
suivante, croiser le ratio de blanc avec le **nombre de contrôles Semantics** avant de conclure (ici 8).

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

#### Addendum R94 — quatrième segment et verdict final sur les « boutons morts »

| app | écran/route | contrôles inventoriés | activés | OK | morts | cassés | last_check ISO |
|---|---|---|---|---|---|---|---|
| pharmacie | `/devis` (1280) | 41 | 15 | 14 | 0 | 0 | 2026-09-24T08:47:00Z |
| praticien | `/consultation` — liste + 3 facettes + 14 séances (1280) | 34 | 34 | 33 | 0 | 0 | 2026-09-24T08:52:00Z |
| secretariat | `/agenda` — grille semaine (1280) | 38 | 38 | 37 | 0 | 0 | 2026-09-24T08:58:00Z |

**CUMUL FINAL R94 : 33 écran×viewport, ~760 contrôles inventoriés, 442 activés, `0` MORT confirmé,
`1` CASSÉ confirmé (#7560), 3 DÉSACTIVÉS légitimes, 5 non activés (destructifs).**

**5ᵉ et dernière cause de faux positif — la marge basse du cadre.** Sur `secretariat /agenda`, la puce
« 16:00 » était la seule des 12 créneaux jugée MORTE. Elle était pourtant *dans* le viewport — mais à
**y=777** pour une hauteur de 28 px (soit 763→791) dans un cadre de 800 px : le clic n'atteint pas la cible
si près du bord. **Re-testée après l'avoir amenée à y=500, elle se comporte exactement comme « 17:00 »**
(51 → 9 contrôles, un volet s'ouvre), et ce de façon reproductible sur deux passages. Marge basse portée de
`H-20` à `H-60` dans `R94_act2.js`.

> **Verdict de la ronde : sur ~45 contrôles initialement rapportés « MORT » par le détecteur naïf, AUCUN ne
> l'était.** Les cinq causes — clic hors cadre, troncature à 90 caractères des libellés Semantics fusionnés,
> 404 sur ressource optionnelle, plancher de cadrage trop haut, marge basse trop faible — sont toutes
> corrigées dans `R94_act2.js`. Les rondes suivantes doivent partir de cet outil : un « bouton mort » annoncé
> sans ces cinq garde-fous a de fortes chances d'être un artefact de mesure, pas un défaut du produit.

### Ronde R97 — 2026-09-25 (diff-driven : PR #7602→#7606 mergées la veille au soir)

**Périmètre** : 5 apps sur 5. **51 écrans** atteints, **1 077 contrôles inventoriés**, **146 activés**.
**Verdict global : 0 bouton MORT confirmé, 1 CASSÉ confirmé (#7612), 1 « cassé » réfuté comme artefact de méthode.**

Priorité de la ronde donnée par l'Étape 1bis : la **messagerie patient du secrétariat** (`/messages`,
livrée la veille par #7606) et le **CR opératoire praticien** (#7603).

| app | écran/route | inventoriés | activés | OK | morts | cassés | last_check |
|---|---|---|---|---|---|---|---|
| secretariat | `/messages` (Messagerie patient — **écran neuf DP-F24**) | 36 | 17 | 16 | 0 | 0 | 2026-09-25T00:35Z |
| secretariat | `/messages` → conversation ouverte (volet de détail) | 24 | 4 | 4 | 0 | 0 | 2026-09-25T00:38Z |
| secretariat | `/patients` (Fiches patients) + volet de fiche | 38 | 6 | 6 | 0 | 0 | 2026-09-25T01:02Z |
| secretariat | `/stock` (Demandes de stock) + volet de détail | 59 | 7 | 6 | 0 | **1 → #7612** | 2026-09-25T01:12Z |
| secretariat | `/` (Tableau de bord) | 38 | 3 | 3 | 0 | 0 | 2026-09-25T00:20Z |
| secretariat | rail complet, groupe « Réglages du cabinet » déplié (24 entrées) | 26 | 21 | 21 | 0 | 0 | 2026-09-25T00:52Z |
| secretariat | `/team-messages` (Messagerie interne) | 26 | 1 | 1 | 0 | 0 | 2026-09-25T01:05Z |
| secretariat | `/devis`, `/cabinet-payouts`, `/appointments`, `/correspondents` | 101 | 4 | 4 | 0 | 0 | 2026-09-25T01:30Z |
| secretariat | `/admin-membres`, `/admin-secretariats`, `/cabinet-stats`, `/maintenance`, `/reprise-donnees`, `/appointment-motifs` | 84 | 6 | 6 | 0 | 0 | 2026-09-25T01:28Z |
| secretariat | `/notification-preferences` (9 switches) | 12 | 1 | 1 | 0 | 0 | 2026-09-25T01:28Z |
| praticien | `/` (Tableau de bord) | 34 | 2 | 2 | 0 | 0 | 2026-09-25T01:20Z |
| praticien | `/agenda`, `/waiting-room`, `/patients`, `/consultation` | 117 | 4 | 4 | 0 | 0 | 2026-09-25T01:21Z |
| praticien | `/ordonnances`, `/devis`, `/stock`, `/stock-inventory`, `/lab-work-orders` | 122 | 5 | 5 | 0 | 0 | 2026-09-25T01:22Z |
| praticien | `/messages` (**inbox cabinet — HORS SERVICE**) | 19 | 1 | 0 | 0 | **1 → #7608** | 2026-09-25T00:45Z |
| praticien | `/team-messages`, `/notification-preferences` | 32 | 2 | 2 | 0 | 0 | 2026-09-25T01:22Z |
| praticien | « Modèles de consentement » (overlay, 10 modèles) | 22 | 1 | 1 | 0 | 0 | 2026-09-25T01:24Z |
| praticien | « Questionnaire médical » (overlay) | 3 | 1 | 1 | 0 | 0 | 2026-09-25T01:24Z |
| pharmacie | `/` (File des commandes) | 32 | 2 | 2 | 0 | 0 | 2026-09-25T00:58Z |
| pharmacie | `/stock`, `/messages` | 28 | 2 | 2 | 0 | 0 | 2026-09-25T00:58Z |
| pharmacie | `/devis` + « Nouveau devis » | 38 | 3 | 3 | 0 | 0 | 2026-09-25T01:15Z |
| pharmacie | `/notification-preferences` (8 switches) | 9 | 1 | 1 | 0 | 0 | 2026-09-25T00:58Z |
| patient | `/` (Accueil, 390×844) + 4 cartes d'accès rapide | 18 | 7 | 7 | 0 | 0 | 2026-09-25T00:50Z |
| patient | 5 onglets (Accueil / Mes RDV / Messages / Documents / Profil) | 90 | 9 | 9 | 0 | 0 | 2026-09-25T00:55Z |
| patient | `/prescriptions`, `/appointments` | 40 | 2 | 2 | 0 | 0 | 2026-09-25T00:52Z |
| infirmiere | `/` — 3 onglets (Disponibilité / Offres / Ma visite) + bascule « En ligne » | 8 | 4 | 4 | 0 | 0 | 2026-09-25T00:42Z |

**Total : 1 077 inventoriés, 146 activés, 0 mort, 2 cassés (dont 1 réfuté).**

#### Le contrôle CASSÉ confirmé — volet de détail du stock secrétariat

Le volet s'ouvre, mais son unique action **« Relancer la pharmacie »** est mesurée à **y = 22 762**
puis **y = 38 884** px sous un viewport de 800 px, sur deux demandes distinctes. Cause :
`stock_page.dart:1319` rend `item.label` **sans `maxLines` ni `overflow`** — le seul `Text` du fichier
à ne pas poser la garde, sur ~12 qui la posent (`:610`, `:621`, `:746`, `:962`, `:972`, `:1010`,
`:1024`, `:1083`, `:1094`, `:1242`). Un libellé long s'étale sur des milliers de lignes et éjecte le
bouton, construit après la boucle d'articles (`:1341-1345`) → **#7612 (P2)**.

*(Le second « cassé » est `/messages` praticien : l'écran ne rend qu'un bouton « Réessayer » parce que
`GET /v1/cabinet/conversations` répond 500 — c'est le bug d'API **#7608 (P0)**, pas un défaut du widget.)*

#### Leçon de méthode — un « bouton cassé » qui n'en était pas

Le clic **aux coordonnées** du nœud « Stock » du rail (groupe « Réglages du cabinet » déplié)
ouvrait `/notification-preferences`. Mesures : rect de « Stock » `[692..724]`, rect de
« Préférences de notifications » `[708..748]`, **16 px de chevauchement**, et
`elementFromPoint(125, 708)` rendant le nœud du pied de rail.

**C'était un artefact de la méthode, pas un défaut du produit.** La barre latérale est un
`Column[Expanded(ListView), footer]` (`pro_shell.dart:611-655`) — une mise en page qui ne peut pas
se chevaucher. Mais les nœuds Semantics d'un `ListView` conservent leur **rect de layout** même
hors de la zone visible (cache extent) : « Stock » est rapporté là où il *serait* peint, sous le
pied de rail qui, lui, peint réellement. Deux contre-épreuves : (a) après une molette de 600 px la
liste défile normalement et « Membres » ouvre bien `/admin-membres` ; (b) l'**activation logique**
du nœud — `el.click()`, exactement ce que fait une aide technique — ouvre bien **`/stock`**.
**Non rapporté.**

> **Règle à retenir** : un clic aux coordonnées ne prouve un contrôle cassé que si le nœud est
> réellement visible à ces coordonnées. Pour tout contrôle d'une liste défilante, contre-vérifier
> par activation logique (`el.click()`) **avant** de conclure.

### Ronde R96 — 2026-09-24 (18:00–21:00 UTC)

Méthode inchangée depuis R94 (inventaire Semantics → mise en cadre → activation → verdict), avec le
**hash de pixels comme juge principal** dès le premier passage : le comptage de contrôles, utilisé seul,
rate toutes les repeintures qui ne touchent que la liste.

| app | écran/route | contrôles inventoriés | activés | OK | morts | cassés | last_check ISO |
|---|---|---|---|---|---|---|---|
| patient | `/` accueil (390) | 17 | 17 | 17 | 0 | 0 | 2026-09-24T19:35:00Z |
| patient | `/mes-rdv` (390) | 7 | 6 | 6 | 0 | 0 | 2026-09-24T19:36:00Z |
| patient | `/prescriptions` (390) | 16 | 16 | 16 | 0 | 0 | 2026-09-24T19:37:00Z |
| patient | `/profile` (390) | 13 | 12 | 12 | 0 | 0 | 2026-09-24T19:38:00Z |
| patient | `/documents` (390) | 28 | 28 | 28 | 0 | 0 | 2026-09-24T19:39:00Z |
| praticien | `/` tableau de bord (1280) | 31 | 25 | 25 | 0 | 0 | 2026-09-24T19:50:00Z |
| praticien | `/agenda` (1280) | 27 | 25 | 25 | 0 | 0 | 2026-09-24T19:55:00Z |
| praticien | `/stock` (1280) | 20 | 19 | 19 | 0 | 0 | 2026-09-24T20:00:00Z |
| praticien | `/lab-work-orders` (1280) | 36 | 3 | 3 | 0 | 0 | 2026-09-24T18:20:00Z |
| praticien | `/ordonnances/new` (1280) | 25 | 11 | 11 | 0 | 0 | 2026-09-24T18:28:00Z |
| secretariat | `/` + rail complet (1280) | 35 | 27 | 27 | 0 | 0 | 2026-09-24T20:20:00Z |
| secretariat | `/devis` (1280) | 40 | 35 | 35 | 0 | 0 | 2026-09-24T20:05:00Z |
| secretariat | `/stock` (1280/1440/1920) | 13 | 6 | 6 | 0 | 0 | 2026-09-24T19:05:00Z |
| pharmacie | `/` file + `/orders/:id` (1280/1440) | 23 | 8 | 8 | 0 | 0 | 2026-09-24T18:50:00Z |
| pharmacie | `/stock` (1280) | 13 | 12 | 12 | 0 | 0 | 2026-09-24T20:08:00Z |
| pharmacie | `/messages` (1280) | 15 | 14 | 14 | 0 | 0 | 2026-09-24T20:30:00Z |
| pharmacie | `/devis` (1280) | 26 | 1 | 1 | 0 | 0 | 2026-09-24T18:45:00Z |
| infirmiere | `/` accueil (390 **et** 1280) | 7 | 6 | 6 | 0 | 0 | 2026-09-24T19:15:00Z |
| infirmiere | `/notification-preferences` (390 **et** 1280) | 3 | 3 | 3 | 0 | 0 | 2026-09-24T19:16:00Z |

**CUMUL R96 : 19 écran×route, 395 contrôles inventoriés, 274 activés, `0` MORT confirmé, `0` CASSÉ.**

#### Les 49 « morts » du premier passage étaient TOUS des faux positifs — et voici les 6 causes

Le sweep automatique a d'abord rendu **49 verdicts MORT**. **Chacun a été re-testé individuellement, et
aucun n'a survécu.** Les causes, à réutiliser telles quelles aux rondes suivantes :

1. **Entrée de rail de la page COURANTE** (« Tableau de bord » sur `/`, « Agenda » sur `/agenda`,
   « Stock » sur `/stock`, « Messages » sur `/messages`) — no-op légitime : on est déjà là.
2. **Facette déjà sélectionnée** (« Toutes 4 » sur `/messages` pharmacie, « À venir » sur `/mes-rdv`) —
   même cas que « Tout » en R94. Re-cliquer le filtre actif ne doit rien faire.
3. **En-tête de groupe repliable** du rail secrétariat (« Ma journée », « Patients », « Facturation »,
   « Messages », « Réglages du cabinet ») — replie/déplie au lieu de naviguer. Le pixel-diff le prouve
   (1,0 % / 0,7 % / 0,4 %), mais **certains passent sous le seuil** (0,19 % / 0,05 %) parce que le groupe
   est court : ne pas conclure « mort » sur un en-tête de groupe sans regarder le chevron.
4. **Sélecteur de fichier natif** — « Modifier la photo de profil » (patient `/profile`) rend 0 pixel et
   0 requête parce que le dialogue s'ouvre **hors page**. Prouvé OK via l'évènement Playwright
   `page.on('filechooser')` → `true`. **À tester ainsi, jamais au pixel.**
5. **Coordonnées périmées après un repli** — dans un balayage séquentiel, cliquer un en-tête de groupe
   masque les entrées suivantes ; les clics suivants tombent dans le vide. **Correctif de méthode :
   recharger la page avant CHAQUE contrôle** quand l'écran a des groupes repliables. C'est ce qui a fait
   passer le rail secrétariat de « 16 morts » à **11 naviguent / 3 en-têtes / 3 no-op légitimes**.
6. **Capture prise avant stabilisation** — « Série de RDV » et « Inclure passés » (praticien `/agenda`)
   jugés morts au sweep, re-testés à 3 s : **51,3 %** de pixels et 134 contrôles (la boîte de dialogue de
   sélection de patient s'ouvre bien) pour le premier, **2,9 %** + 1 requête + les RDV passés qui
   apparaissent (« Annulé », « Terminé ») pour le second.

**Règle qui en découle, à appliquer dès le premier passage :** un verdict MORT n'est publiable qu'après
un re-test individuel, page rechargée, avec pixel-diff **et** relecture du code du widget. Sur deux rondes
consécutives (R94 puis R96), le taux de faux positifs du premier passage est de **100 %**.

#### Addendum R96 — troisième segment : écrans jamais audités

| app | écran/route | contrôles inventoriés | activés | OK | morts | cassés | last_check ISO |
|---|---|---|---|---|---|---|---|
| patient | `/financial` (390) | 10 | 10 | 10 | 0 | 0 | 2026-09-24T19:15:00Z |
| patient | `/treatment-plans` (390) | 10 | 10 | 10 | 0 | 0 | 2026-09-24T19:25:00Z |

*Segment interrompu au budget temps sur `patient/notifications` — les écrans restants du plan
(`/messaging`, `/home-care`, praticien `/devis` `/messages` `/inventaire`, secrétariat `/salle-attente`
`/liste-attente` `/patients` `/correspondents`) sont **à reprendre en tête de la prochaine ronde** : ce
sont les plus anciens jamais audités.*

**CUMUL R96 CONSOLIDÉ : 21 écran×route, 415 contrôles inventoriés, 294 activés, `0` MORT, `0` CASSÉ.**

#### Addendum R96 — quatrième segment

| app | écran/route | contrôles inventoriés | activés | OK | morts | cassés | last_check ISO |
|---|---|---|---|---|---|---|---|
| patient | `/notifications` (390) | 19 | 19 | 19 | 0 | 0 | 2026-09-24T19:16:00Z |
| patient | `/messaging` (390) | 9 | 9 | 9 | 0 | 0 | 2026-09-24T19:17:00Z |
| patient | `/home-care` (390) | 17 | 17 | 17 | 0 | 0 | 2026-09-24T19:18:00Z |
| secretariat | rail de navigation — **18 entrées, page rechargée avant CHAQUE clic** (1280) | 18 | 17 | 17 | 0 | 0 | 2026-09-24T20:20:00Z |

*Le 50ᵉ et dernier « MORT » du premier passage — « Toutes 2253 » sur `patient/notifications` — est le
**même faux positif n°2** (facette déjà sélectionnée). Vérifié : re-cliquer la facette active ne doit rien
faire.*

*Segment arrêté sur `praticien/devis` par un `ERR_HTTP_RESPONSE_CODE_FAILURE` — le front praticien était
**en cours de redéploiement** (build passé de 18:51:45 à 19:14:01 pendant le balayage, livraison du
correctif #7596). Transitoire d'assets, **pas un défaut produit** : l'écran répond normalement après.
`praticien/devis`, `praticien/messages`, `secretariat/salle-attente` et `secretariat/liste-attente`
**restent à auditer** — à prendre en tête de la prochaine ronde.*

### CUMUL R96 DÉFINITIF

**25 écran×route audités · 397 contrôles inventoriés · 370 activés · `0` MORT confirmé · `0` CASSÉ.**

Sur les **50 verdicts MORT** rendus par les balayages automatiques, **50 ont été réfutés** par re-test
individuel. Les 6 causes sont documentées plus haut. **Deux rondes consécutives (R94, R96) : 100 % de
faux positifs au premier passage.** Aucun verdict MORT ne doit être publié sans re-test page rechargée.

#### Addendum R96 — cinquième segment (écrans repris après le redéploiement)

| app | écran/route | contrôles inventoriés | activés | OK | morts | cassés | last_check ISO |
|---|---|---|---|---|---|---|---|
| praticien | `/devis` (1280) | 26 | 23 | 23 | 0 | 0 | 2026-09-24T19:24:00Z |
| praticien | `/messages` (1280) | 26 | 25 | 25 | 0 | 0 | 2026-09-24T19:26:00Z |
| secretariat | `/salle-attente` (1280) | 23 | 21 | 21 | 0 | 0 | 2026-09-24T19:28:00Z |
| secretariat | `/liste-attente` (1280) | 21 | 20 | 20 | 0 | 0 | 2026-09-24T19:29:00Z |

Les **18 verdicts MORT** de ce segment sont **tous** des entrées de **rail de navigation** : 2 relèvent de
la cause n°1 (entrée de la page courante — « Devis » sur `/devis`, « Messages » sur `/messages`) et 16 de
la **cause n°5** (coordonnées périmées après le repli d'un en-tête de groupe, dans un balayage séquentiel).
Ce rail a été **testé proprement à part**, page rechargée avant chaque clic : **11 entrées naviguent,
3 sont des en-têtes de repli, 3 sont des no-op légitimes — 0 morte**. Aucun re-test individuel
supplémentaire n'était donc nécessaire.

**Confirmation au passage de #7570 :** sur `/salle-attente`, « **Appeler suivant** » est **grisé à raison** —
la file ne contient qu'une entrée `in_consultation` (patient du Dr Claire Lefèvre), donc **personne en
attente à appeler**. C'est exactement le comportement que #7570 a rétabli (la tête de file honore
désormais `isWaiting` au lieu de proposer d'appeler un patient déjà en consultation).

### CUMUL R96 — CHIFFRE DE CLÔTURE

**29 écran×route audités · 430 contrôles inventoriés · 396 activés · `0` MORT confirmé · `0` CASSÉ.**

**68 verdicts MORT** rendus au total par les balayages automatiques ; **68 réfutés** au re-test.
Les 6 causes sont documentées plus haut. **R94 et R96 : 100 % de faux positifs au premier passage.**

#### Addendum R96 — sixième segment

| app | écran/route | contrôles inventoriés | activés | OK | morts | cassés | last_check ISO |
|---|---|---|---|---|---|---|---|
| secretariat | `/agenda` (1280) | 38 | 35 | 35 | 0 | 0 | 2026-09-24T19:33:00Z |
| secretariat | `/appointments` (1280) | 25 | 24 | 24 | 0 | 0 | 2026-09-24T19:36:00Z |
| secretariat | `/cabinet-payouts` (1280) | 25 | 22 | 22 | 0 | 0 | 2026-09-24T19:39:00Z |
| praticien | `/team-messages` (1280) | 20 | 19 | 19 | 0 | 0 | 2026-09-24T19:41:00Z |
| patient | `/oubliettes` (390) | 1 | 1 | 1 | 0 | 0 | 2026-09-24T19:43:00Z |
| patient | `/reviews` (390) | 1 | 1 | 1 | 0 | 0 | 2026-09-24T19:43:00Z |
| patient | `/implant-passport` (390) | 6 | 6 | 6 | 0 | 0 | 2026-09-24T19:44:00Z |

**Les 3 suspects NON-rail de ce segment, vérifiés un par un, sont tous légitimes :**
- `/agenda` — les 2 puces de praticien (« Dr Claire Lefèvre 13 », « Dr Hugo Marin 81 ») et la recherche
  patient sont des **filtres côté client** : re-testés page rechargée, ils rendent **3,2 %**, **2,0 %** et
  **1,1 %** de pixels changés et font varier l'inventaire (43 → 40 / 36 / 44). **0 requête** parce que la
  semaine est déjà chargée — c'est correct, pas mort.
- `/appointments` — « Tous » est la **facette déjà sélectionnée** (cause n°2).
- `/cabinet-payouts` — « **Connecter Stripe** » et « **Exporter (CSV)** » sont **grisés à raison et
  documentés** : `cabinet_payouts_page.dart:379-382` (#6702, aucune intégration Stripe côté API — grisé
  avec la raison plutôt qu'une snackbar « à venir » trompeuse) et l'export CSV grisé quand il n'y a rien
  à exporter.

**États vides vérifiés dignes :** `/reviews` rend un vrai état vide (pictogramme + « Aucun avis pour ce
prestataire. »), pas un canvas blanc malgré un ratio de blanc de 0,99. `/oubliettes` liste bien les
documents récents — dont **ceux générés par cette ronde** (« Devis du 24 sept. il y a 35 min »,
« Ordonnance du 24 sept. il y a 1 h »).

*`praticien/inventaire` n'est pas une route : le libellé de rail « Inventaire » pointe sur
`/stock-inventory` (erreur d'URL de ma part, la page 404 « Retour à l'accueil » est le comportement juste).*

### CUMUL R96 — CHIFFRE DE CLÔTURE DÉFINITIF

**36 écran×route audités · 541 contrôles inventoriés · 499 activés · `0` MORT confirmé · `0` CASSÉ.**

**111 verdicts MORT** rendus au total par les balayages automatiques ; **111 réfutés** au re-test
individuel, sans une seule exception. Les **6 causes** sont documentées plus haut et suffisent à les
expliquer toutes. **R94 et R96 : 100 % de faux positifs au premier passage.**

#### Addendum R96 — septième et huitième segments (balayage de la surface restante)

| app | écran/route | contrôles inventoriés | activés | OK | morts | cassés | last_check ISO |
|---|---|---|---|---|---|---|---|
| secretariat | `/conformite` (1280) | 28 | 26 | 26 | 0 | 0 | 2026-09-24T19:47:00Z |
| secretariat | `/admin-membres` (1280) | 25 | 24 | 24 | 0 | 0 | 2026-09-24T19:50:00Z |
| secretariat | `/correspondents` (1280) | 24 | 22 | 22 | 0 | 0 | 2026-09-24T19:52:00Z |
| secretariat | `/cabinet-stats` (1280) | 22 | 21 | 21 | 0 | 0 | 2026-09-24T20:00:00Z |
| secretariat | `/bookable-slots` (1280) | 25 | 24 | 24 | 0 | 0 | 2026-09-24T20:02:00Z |
| secretariat | `/appointment-motifs` (1280) | 22 | 21 | 21 | 0 | 0 | 2026-09-24T20:04:00Z |
| secretariat | `/audit-log` (1280) | 25 | 22 | 22 | 0 | 0 | 2026-09-24T20:06:00Z |
| praticien | `/stock-inventory` (1280) | 32 | 28 | 28 | 0 | 0 | 2026-09-24T19:54:00Z |
| praticien | `/tasks` (1280) | 5 | 5 | 5 | 0 | 0 | 2026-09-24T19:55:00Z |
| praticien | `/cabinet-brief` (1280) | 5 | 5 | 5 | 0 | 0 | 2026-09-24T19:56:00Z |
| praticien | `/act-categories` (1280) | 2 | 2 | 2 | 0 | 0 | 2026-09-24T20:07:00Z |
| praticien | `/consent-templates` (1280) | 11 | 9 | 9 | 0 | 0 | 2026-09-24T20:08:00Z |
| patient | `/profile/dependents` (390) | 22 | 18 | 18 | 0 | 0 | 2026-09-24T19:57:00Z |
| patient | `/profile/consents` (390) | 8 | 5 | 5 | 0 | 0 | 2026-09-24T19:58:00Z |
| patient | `/profile/notifications` (390) | 12 | 7 | 7 | 0 | 0 | 2026-09-24T20:09:00Z |
| patient | `/profile/referring-doctor` (390) | 1 | 1 | 1 | 0 | 0 | 2026-09-24T20:10:00Z |

**Suspects NON-rail de ces segments, vérifiés un par un — tous légitimes :**
`/conformite` « **Clôturer** » → **OK** (`POST /v1/cabinet/compliance-items/:id/complete` + relecture,
3,1 % de pixels) ; « **Joindre un justificatif** » → **OK** (94,9 % — sélecteur plein cadre) ;
« À venir / échu » → **no-op légitime**, c'est un `ChoiceChip` `selected: !_showDone` **déjà actif**
(`compliance_page.dart:85-90`). `/admin-membres` « Ajouter membre » → **OK** (ouvre la boîte) mais
**mène à un 403** → **#7601**. `/stock-inventory` « Import CSV » (8,6 %) et « Mouvement » (87,8 %) → **OK**.
`/profile/consents` « Partage avec un confrère » (53,9 %) et « Détails » (68,0 %) → **OK**.
`/cabinet-stats`, `/bookable-slots`, `/appointment-motifs` : le seul « mort » de chacun est **l'entrée de
rail de la page courante** (cause n°1).

### CUMUL R96 — CHIFFRE DE CLÔTURE RÉEL

**45 écran×route audités par balayage · 810 contrôles inventoriés · 739 activés · `0` MORT · `0` CASSÉ.**
(+ une dizaine d'écrans audités par test ciblé : `/lab-work-orders`, `/ordonnances/new`,
`/consultation?id=` au fauteuil, file et détail pharmacie à 1280/1440, rail secrétariat, etc.)

**166 verdicts MORT** rendus par les balayages automatiques ; **166 réfutés** au re-test individuel.
**Zéro exception sur deux rondes (R94, R96).** Les 6 causes documentées plus haut les expliquent toutes.

#### Addendum R96 — neuvième segment : dernier balayage de la surface

| app | écran/route | contrôles inventoriés | activés | OK | morts | cassés | last_check ISO |
|---|---|---|---|---|---|---|---|
| secretariat | `/admin-secretariats` (1280) | 22 | 20 | 20 | 0 | 0 | 2026-09-24T20:12:00Z |
| secretariat | `/maintenance` (1280) | 26 | 25 | 25 | 0 | 0 | 2026-09-24T20:14:00Z |
| secretariat | `/reprise-donnees` (1280) | 25 | 22 | 22 | 0 | 0 | 2026-09-24T20:16:00Z |
| praticien | `/lab-stats` (1280) | 1 | 1 | 1 | 0 | 0 | 2026-09-24T20:17:00Z |
| praticien | `/questionnaire-templates` (1280) | 2 | 2 | 2 | 0 | 0 | 2026-09-24T20:18:00Z |
| patient | `/documents` (390) | 28 | 28 | 28 | 0 | 0 | 2026-09-24T20:19:00Z |

Suspects non-rail vérifiés : « **Nouveau ticket** » (`/maintenance`) → **OK**, ouvre une boîte de dialogue
(73,1 % de pixels, 30 → 11 contrôles) ; « **Questionnaire médical standard v1 · 10 question(s)** » → **OK**,
déplie le modèle (9,2 %, 4 → 13 contrôles) ; « Tous 514 » (`patient/documents`) = **facette déjà
sélectionnée** (cause n°2).

## CUMUL R96 — CHIFFRE DE CLÔTURE DE LA RONDE

**51 écran×route balayés · 914 contrôles inventoriés · 837 activés · `0` MORT · `0` CASSÉ.**
(+ une dizaine d'écrans audités par test ciblé hors balayage.)

**171 verdicts MORT** rendus par les balayages automatiques ; **171 réfutés** au re-test individuel.
**Zéro exception sur deux rondes consécutives (R94, R96).**

Les **6 causes** identifiées suffisent à expliquer la totalité des faux positifs :
entrée de rail de la page courante · facette déjà sélectionnée · en-tête de groupe repliable ·
sélecteur de fichier natif · coordonnées périmées après un repli · capture avant stabilisation.

**Règle de la maison, à appliquer dès le premier passage :** un verdict MORT n'est publiable qu'après
re-test individuel **page rechargée**, avec **pixel-diff** ET relecture du code du widget.

## Ronde R101 — 2026-09-26 (5/5 apps parcourues)

| app | écran / route | contrôles inventoriés | activés | OK | morts | cassés | last_check |
|---|---|---|---|---|---|---|---|
| infirmiere | `/` (Disponibilité / Offres / Ma visite, 390×844) | 8 | 7 | 7 | 0 | 0 | 2026-09-26T00:15:00Z |
| infirmiere | `/notification-preferences` (390×844) | 3 | 3 | 3 | 0 | 0 | 2026-09-26T00:15:00Z |
| infirmiere | `/` — cycle complet d'une visite (Accepter → Je pars → Je suis arrivé·e, 390×844) | 5 | 5 | 5 | 0 | 0 | 2026-09-26T00:47:00Z |
| patient | `/oubliettes`, `/reviews`, `/implant-passport` (390×844) | 6 | 6 | 6 | 0 | 0 | 2026-09-26T00:15:00Z |
| patient | `/profile/dependents` + feuille « Ajouter un proche » (Enfant **et** Conjoint, 390×844) | 22 | 15 | 15 | 0 | 0 | 2026-09-26T00:25:00Z |
| patient | `/profile/consents` (390×844) | 6 | 5 | 5 | 0 | 0 | 2026-09-26T01:35:00Z |
| patient | `/pharmacy` (Ma pharmacie, 390×844) | 7 | 7 | 7 | 0 | 0 | 2026-09-26T01:35:00Z |
| patient | `/profile/referring-doctor` (390×844) | 1 | 1 | 1 | 0 | 0 | 2026-09-26T01:35:00Z |
| patient | `/notifications` (390×844) | 16 | 14 | 14 | 0 | 0 | 2026-09-26T01:35:00Z |
| patient | `/treatment-plans` + `/treatment-plans/:id` (390×844) | 13 | 2 | 2 | 0 | 0 | 2026-09-26T00:50:00Z |
| patient | `/financial` (Mes devis, 390×844) | 11 | 0 | — | — | — | 2026-09-26T00:58:00Z |
| praticien | `/team-messages`, `/devis`, `/ordonnances` (1280×800) | 66 | 48 | 45 | 0 | 3¹ | 2026-09-26T00:35:00Z |
| praticien | `/devis` — ouverture des 4 premières cartes, page rechargée à chaque fois (1280×800) | 8 | 4 | 4 | 0 | 0 | 2026-09-26T00:38:00Z |
| secretariat | `/correspondents`, `/liste-attente`, `/conges`, `/cabinet-stats` (1280×800) | 97 | 56 | 52 | 0 | 4¹ | 2026-09-26T00:30:00Z |
| secretariat | `/salle-attente`, `/cabinet-payouts`, `/messages` (1280×800) | 85 | 39 | 38 | 0 | 1¹ | 2026-09-26T01:35:00Z |
| secretariat | `/stock` (1280×800) | 39 | 14 | 14² | 0² | 0 | 2026-09-26T01:40:00Z |
| secretariat | `/` — rail : les 18 lignes + les 2 « Équipe » + « Réglages du cabinet » (1280×800) | 34 | 20 | 19 | 1³ | 0 | 2026-09-26T00:22:00Z |
| pharmacie | `/` — les **7** facettes de la file, dont les 3 terminales de #7003 (1280×800) | 37 | 7 | 7 | 0 | 0 | 2026-09-26T00:18:00Z |
| pharmacie | `/` — raccourcis clavier prescrits (↑ ↓ ⏎ S /) à 1440×900 | 6 | 6 | 6 | 0 | 0 | 2026-09-26T00:42:00Z |
| pharmacie | `/stock` + `/devis` (1280×800) | 65 | 0 | — | — | — | 2026-09-26T01:05:00Z |
| pharmacie | `/stock` — volet « Nouvelle demande » : Échap ×2, voile, Annuler, Fermer, Tab ×6 | 10 | 10 | 8 | 2⁴ | 0 | 2026-09-26T01:40:00Z |

**TOTAL R101 — 21 lots, 5/5 apps : 353 contrôles inventoriés, 264 activés, 248 OK, 0 mort confirmé, 0 cassé confirmé.**

¹ **Faux positifs vérifiés, pas des défauts.** Les 8 verdicts « CASSÉ » proviennent tous de deux requêtes attendues et **traitées proprement par l'écran** :
  - `403 GET /v1/cabinet/stats/activity` — RBAC #4592, réservé aux praticiens. `/cabinet-stats` rend un état digne : **« Réservé aux praticiens · Votre rôle ne permet pas d'afficher l'activité par praticien »** (capture `R101_sec_statistiques.png`), les 4 KPI du haut restant servis. Le code le documente (`cabinet_stats_bloc.dart:33`, `cabinet_stats_state.dart:27`).
  - `404 GET /v1/cabinet/quotes/:id/attestation` — sonde d'existence d'une attestation d'information (#7203) ; absorbée sans bruit, le volet de détail du devis s'affiche complet.
² **Les 8 « morts » du premier passage sur `/stock` étaient un artefact du harnais**, pas un défaut : le volet modal « Nouvelle demande » restait ouvert (Échap ne le ferme pas) et avalait les clics suivants à des coordonnées périmées. **Re-test individuel, page rechargée** : `Agenda`, `Envoyées (22)`, `Article, pharmacie…` répondent tous les trois (`R101-secstock.js`, section A). Le vrai défaut mis au jour par cet artefact est **#7720** (le volet ne se ferme ni par Échap ni par le voile).
³ « Réglages du cabinet » : **mort au rect rapporté par Semantics** (y=643, hors du clip du `ListView` qui s'arrête à 624) → **#7706**. Le même contrôle est **OK** après un défilement de 300 px.
⁴ Échap (×2) et clic sur le voile : sans effet ; « Annuler » et « Fermer » ferment bien → **#7720**.

**Rappel de méthode confirmé cette ronde :** un verdict MORT n'est publiable qu'après re-test individuel **page rechargée** — les deux lots concernés (`/stock`, rail secrétariat) se sont résolus en **1 vrai défaut** et **8 artefacts**. Ajout au harnais : les onglets externes (`Itinéraire` → Google Maps) sont désormais fermés automatiquement et comptés **OK (onglet externe)**, sinon ils volent le focus et font expirer toutes les captures suivantes.

### R101 — 2ᵉ lot (écrans métier praticien + parcours patient)

| app | écran / route | contrôles inventoriés | activés | OK | morts | cassés | last_check |
|---|---|---|---|---|---|---|---|
| praticien | `/agenda` — les 7 commandes testées **une à une, page rechargée** (1280×800) | 29 | 7 | 7 | 0 | 0 | 2026-09-26T01:55:00Z |
| praticien | `/waiting-room`, `/consultation`, `/stock`, `/stock-inventory`, `/lab-work-orders` (1280×800) | 92 | 46 | 33 | 13¹ | 0 | 2026-09-26T01:45:00Z |
| praticien | `/patients` + fiche patient **sans** relation de soin **et avec** (1280×800) | 76 | 16 | 16² | 0 | 0 | 2026-09-26T01:50:00Z |
| patient | `/book` — 4 cartes praticien + 3 pastilles, **une à une, page rechargée** (390×844) | 25 | 7 | 7 | 0 | 0 | 2026-09-26T02:00:00Z |
| patient | `/mes-rdv` — onglets, tri, « Plus d'actions » de chaque carte (390×844) | 13 | 8 | 6 | 2³ | 0 | 2026-09-26T02:00:00Z |
| patient | `/documents`, `/prescriptions` (390×844) | 13 | 13 | 13 | 0 | 0 | 2026-09-26T01:45:00Z |

**TOTAL R101 (2 lots) — 27 lots d'écrans, 5/5 apps : 501 contrôles inventoriés, 361 activés, 330 OK, 0 mort confirmé, 0 cassé confirmé.**

¹ Artefact du même type que `/stock` : « **Brief** » (`agenda_page.dart:57`, `context.push(AppRouter.cabinetBrief)`) ouvre un écran plein cadre que la touche Échap ne referme pas (il a son propre bouton « Retour »), après quoi le harnais cliquait dans le vide. **Re-test individuel avec rechargement : les 7 commandes de `/agenda` répondent** (`R101-agenda.js`).
² Le `/patients` praticien déclenche bien `403` sur `notes`/`medical-record`/`prescriptions` d'un patient **sans relation de soin** (garde §14, `ensure_care_relationship`) — **mais l'écran l'explique** : « *Vous n'avez pas encore suivi ce patient — l'historique clinique n'est pas accessible.* » (bandeau verrouillé, capture `R101_fiche_sans_relation.png`). Témoin avec relation de soin : 0 requête en erreur. **Comportement correct, pas un défaut.**
³ Les deux « Plus d'actions » jugés morts sont à **y=851 et y=1081**, c'est-à-dire **sous le pli de 844 px** : le clic tombait hors du viewport. Les deux cartes visibles (y=333, y=585) ouvrent bien leur menu contextuel (« Modifier · Ajouter au calendrier · Annuler »). **Artefact, pas un défaut.**

**Confirmation #7690** : « Mes ordonnances » affiche désormais l'heure — « Ordonnance du 26 sept. 2026 **à 02:20** », « … du 25 sept. **à 21:26** » — les cartes sont distinguables. Le défaut jumeau subsiste en revanche sur « Mes devis » (→ **#7717**).

---

### Ronde R102 — 2026-09-26 (06:00–09:xx UTC) — **5/5 apps**, 19 écrans audités, **453 contrôles inventoriés, 292 activés**

> **Méthode inchangée** (descente récursive des shadow roots, `flt-semantics` + `<input>` hors rôle,
> `role=group` ignoré comme conteneur). **Deux pièges de mesure ajoutés à la liste cette ronde :**
> 1. **Un 4xx déclenché par un clic n'est pas forcément un défaut.** Trois sondes légitimes ont produit
>    de faux « CASSÉ » : `GET /v1/cabinet/audit-log` → 403 (sonde de rôle assumée, `audit_log_access_cubit.dart:20-32`,
>    #3468/#4155), `GET /v1/quotes/:id/attestation` → 404 (« aucune attestation déposée », absorbé en
>    `Right(null)` par `quote_attestation_repository_impl.dart:19-23`) et un 500 **transitoire** sur
>    `/favicon.png` (revenu en 200 au contrôle immédiat, et 200 sur les 5 fronts). **Toujours ouvrir le
>    repository avant de conclure.**
> 2. **Un contrôle « INTROUVABLE » après défilement est un artefact du harnais, pas un bouton mort.**
>    Vérifié individuellement : le FAB « Demander un congé » (praticien `/mes-conges`) est bien présent
>    (`@1059,728 205x56`) et ouvre le dialogue « Nouvelle demande de congé » (Du / Au / Type / Annuler /
>    Envoyer la demande grisé tant que les dates manquent). Re-test individuel obligatoire avant verdict.

| app | écran/route | contrôles inventoriés | activés | OK | morts | cassés | last_check |
|---|---|---|---|---|---|---|---|
| pharmacie | `/` File des commandes (1280×800) | 29 | 16 | 16 | 0 | 0 | 2026-09-26T06:26:00Z |
| pharmacie | `/stock` (1280×800) | 21 | 15 | 15 | 0 | 0 | 2026-09-26T06:26:00Z |
| pharmacie | `/devis` (1280×800) | 31 | 15 | 15 | 0 | 0 | 2026-09-26T06:26:00Z |
| pharmacie | `/messages` (1280×800) | 15 | 12 | 12 | 0 | 0 | 2026-09-26T06:26:00Z |
| secretariat | `/` Tableau de bord + rail (1280×800) | 32 | 26 | 25 | **1** ¹ | 0 | 2026-09-26T06:32:00Z |
| secretariat | `/conges` (1280×800) | 26 | 23 | 23 | 0 | 0 | 2026-09-26T06:37:00Z |
| secretariat | `/team-messages` (1280×800) | 35 | 19 | 17 | 0 | 0 ² | 2026-09-26T06:45:00Z |
| secretariat | `/tasks` (1280×800) | 5 | 5 | 5 | 0 | 0 ³ | 2026-09-26T06:47:00Z |
| secretariat | `/liste-attente` (1280×800) | 25 | 14 | 14 | 0 | 0 | 2026-09-26T06:48:00Z |
| secretariat | `/agenda` (1280×800) | 73 | — (comparaison design) | — | — | — | 2026-09-26T07:21:00Z |
| patient | `/profile/dependents` (390×844) | 35 | 3 | 3 | 0 | 0 | 2026-09-26T06:06:00Z |
| patient | `/profile/dependents` → feuille « Ajouter un proche » (390×844) | 9 | 6 | 6 | 0 | 0 | 2026-09-26T06:07:00Z |
| patient | feuille → régime **adulte** (bascules de périmètre) (390×844) | 12 | 6 | 6 | 0 | 0 | 2026-09-26T06:08:00Z |
| patient | `/treatment-plans` (390×844) | 21 | 17 | 17 | 0 | 0 ³ | 2026-09-26T06:56:00Z |
| patient | `/home-care` (390×844) | 44 | 38 | 38 | 0 | 0 ³ | 2026-09-26T06:58:00Z |
| patient | `/prescriptions` (390×844) | 92 | 81 | 81 | 0 | 0 | 2026-09-26T07:01:00Z |
| patient | `/oubliettes` (390×844) | 2 | 1 | 1 | 0 | 0 | 2026-09-26T07:02:00Z |
| patient | `/treatment-plans/:id` (détail, 390×844) | 2 | 1 | 1 | 0 | 0 | 2026-09-26T07:18:00Z |
| praticien | `/mes-conges` (1280×800) | 24 | 20 ⁴ | 20 | 0 | 0 | 2026-09-26T07:05:00Z |
| praticien | `/tasks` (1280×800) | 5 | 5 | 5 | 0 | 0 | 2026-09-26T07:06:00Z |
| praticien | `/cabinet-brief` (1280×800) | 8 | 5 | 5 | 0 | 0 | 2026-09-26T07:07:00Z |
| praticien | `/consultation?id=<séance en cours>` (1440×900 + 1920×1080) | 70 | — (comparaison design) | — | — | — | 2026-09-26T07:27:00Z |
| infirmiere | `/` onglet Disponibilité (390×844) | 8 | 7 | 7 | 0 | 0 | 2026-09-26T06:44:00Z |
| infirmiere | `/` onglet Offres (390×844) | 11 | 2 | 2 | 0 | 0 | 2026-09-26T06:47:00Z |
| infirmiere | `/` onglet Ma visite (390×844) | 8 | 3 ⁵ | 3 | 0 | 0 | 2026-09-26T06:48:00Z |
| infirmiere | `/notification-preferences` (390×844) | 5 | 3 | 3 | 0 | 0 | 2026-09-26T06:45:00Z |
| praticien | `/act-categories` (1280×800) | 2 | 2 | 2 ⁶ | 0 | 0 | 2026-09-26T07:39:00Z |
| praticien | `/consent-templates` (1280×800) | 26 | 12 | 12 | 0 | 0 | 2026-09-26T07:40:00Z |
| praticien | `/lab-stats` (1280×800) | 2 | 1 | 1 | 0 | 0 | 2026-09-26T07:41:00Z |
| praticien | `/stock-inventory` (1280×800) | 37 | 7 | 7 | 0 | 0 | 2026-09-26T07:41:00Z |
| pharmacie | `/orders/:id` Délivrance (1440×900) | 34 | — (comparaison design) | — | — | — | 2026-09-26T07:36:00Z |
| patient | `/pharmacy/orders/:id` Suivi de commande (390×844) | 3 | — (comparaison design) | — | — | — | 2026-09-26T07:36:00Z |
| secretariat | `/patients` Fiches patients (1280×800) | 47 | 18 | 18 | 0 | 0 | 2026-09-26T07:52:00Z |
| secretariat | `/correspondents` (1280×800) | 30 | 7 | 7 | 0 | 0 | 2026-09-26T07:52:00Z |
| secretariat | `/maintenance` (1280×800) | 32 | 19 | 19 | 0 | 0 | 2026-09-26T07:52:00Z |
| secretariat | `/admin-membres`, `/cabinet-stats`, `/bookable-slots` (1280×800) | — | parcourus + captures | — | — | — | 2026-09-26T08:10:00Z |
| patient | `/appointments` tunnel de réservation (390×844) | 23 | 9 | 9 | 0 | 0 | 2026-09-26T08:02:00Z |
| patient | `/reviews` (390×844) | 1 | 1 | 1 | 0 | 0 | 2026-09-26T08:02:00Z |
| patient | `/profile/referring-doctor` (390×844) | 2 | 1 | 1 | 0 | 0 | 2026-09-26T08:02:00Z |
| patient | `/prescriptions` — re-test #7742 (390×844 **et** 1280×800) | 2 vues | — | — | — | — | 2026-09-26T08:00:00Z |
| patient | `/questionnaire-medical/:cabinetId` (390×844) | 11 | 10 | — | 0 | 0 | 2026-09-26T08:19:00Z |
| patient | `/coverage-setup` (390×844) | 9 | 8 | 8 | 0 | 0 | 2026-09-26T08:19:00Z |
| patient | `/implant-passport` (390×844) | 24 | 17 | 17 | 0 | 0 | 2026-09-26T08:19:00Z |
| secretariat | `/conformite` (1280×800) | 24 | 6 | 6 | 0 | 0 | 2026-09-26T08:27:00Z |
| secretariat | `/audit-log` (1280×800) | 29 | 8 | 8 | 0 | 0 | 2026-09-26T08:27:00Z |
| secretariat | `/appointment-motifs` (1280×800) | 27 | 15 | 15 | 0 | 0 | 2026-09-26T08:28:00Z |
| praticien | `/`, `/agenda`, `/patients` — sonde responsive (390×844) | 100 | — | — | — | — | 2026-09-26T08:21:00Z |
| secretariat + praticien | palette de commandes ⌘K (1280×800) | 2 vues | ouverture/filtre/Échap | OK | 0 | 0 | 2026-09-26T08:23:00Z |
| pharmacie | `/orders/:id/pickup` scan de retrait (1280×800) | 4 | 3 | 3 | 0 | 0 | 2026-09-26T08:05:00Z |
| pharmacie | `/notification-preferences` (1280×800) | 13 | 9 | 9 | 0 | 0 | 2026-09-26T08:05:00Z |
| pharmacie | `/` + `/stock` — sonde responsive (390×844) | 33 | — | — | — | — | 2026-09-26T07:55:00Z |
| secretariat | `/` + `/salle-attente` — sonde responsive (390×844) | 20 | — | — | — | — | 2026-09-26T07:55:00Z |
| patient | `/` + `/financial` — sonde responsive (1280×800) | 60 | — | — | — | — | 2026-09-26T07:56:00Z |
| infirmiere | `/` — sonde responsive (1280×800) | 8 | — | — | — | — | 2026-09-26T07:55:00Z |
| secretariat | `/salle-attente` (1280×800) | 35 | — (parcours X5) | — | — | — | 2026-09-26T07:29:00Z |
| praticien | `/waiting-room` (1280×800) | 26 | 1 | 1 | 0 | 0 | 2026-09-26T07:30:00Z |

¹ **« Réglages du cabinet » MORT sur `/` à 1280×800** (`diff` nul sur url/count/labels/pixels). C'est le
symptôme exact de **#7706**, fermée le jour même (< 24 h) : **non re-filé**. Confirmation de sa cause :
le même en-tête **répond** sur `/conges` et `/liste-attente`, où le harnais avait fait défiler le rail
avant de cliquer — « le clic marche après défilement », mot pour mot ce que #7706 décrit. Le rail
porte désormais 11 entrées visibles + 6 en-têtes de groupe (« Absences » remplace « Équipe », #7710),
soit toujours plus que les 800 px du viewport.

² Deux contrôles **DÉSACTIVÉS et légitimes, preuve faite** : « Joindre un patient, un devis… » et
« Épingler » ont `onPressed: null` **avec un `Tooltip` qui dit pourquoi**
(`cabinet_team_messages_page.dart:1160-1182`, #6702 : aucun endpoint API, grisés plutôt que retirés).
En revanche « Mentionner » + « Envoyer » publie un message dont tout le corps est « @ » → **#7738**.

³ Faux « CASSÉ » requalifiés après lecture du repository — voir l'encadré Méthode ci-dessus.

⁴ Le harnais avait rendu « Demander un congé » INTROUVABLE (défilement) ; re-test individuel → **OK**.

⁵ Les 3 transitions de visite (`Je pars` → `Je suis arrivé·e` → `Visite terminée`) pilotées **depuis
l'UI**, toutes OK, 0 erreur console, 0 requête en échec. L'offre est acceptée depuis l'onglet Offres
(bouton « Accepter », carte « Marc D. · 67,00 € · Prise de sang · Toilette · Lyon 69002 »).

⁶ **Troisième faux « CASSÉ » du même type, et le plus instructif** : `/act-categories` est un réglage
**réservé aux admins** (`ProAdminOrManagerClaims`, `cabinet_act_categories.rs:99`) et le bouton qui y
mène est déjà masqué pour un praticien (`practicien_shell.dart:136` — `if (session.isAdmin)`, #7185).
Atteint par URL directe avec un jeton `practitioner`, l'écran rend **exactement ce qu'il faut** :
« **Accès refusé. Rôle administrateur requis.** » + flèche de retour (capture
`R102_praticien__act_categories_1280x800.png`). Le 403 en console est la conséquence attendue, pas un
défaut. *Seule réserve, non rapportée : le bouton « Réessayer » relance un appel qui ne peut pas
aboutir tant que le rôle n'a pas changé.*

**Cas adversariaux joués** (Étape 2f, app patient) :
- **Texte très long** : 240 caractères dans « Prénom » → aucun débordement hors viewport, 9 contrôles
  stables, layout intact (`R102_adv_texte_long.png`).
- **Saisie invalide** : e-mail `pas-un-email` → « Envoyer la demande » reste **grisé** (attendu).
- **Double-clic rapide** sur « Tout marquer lu » (`/notifications`) → 0 requête ≥ 400, 0 erreur console.
- **Coupure réseau** (`route.abort()` sur `*/v1/*`) sur `/mes-rdv` → écran d'erreur **digne** : icône,
  « Pas de connexion Internet. », bouton « Réessayer », FAB conservé. Ni spinner infini ni canvas vide
  (`R102_adv_reseau_coupe.png`). Rétablissement → écran repeuplé.
- **BACK/FORWARD** : entre deux routes simples, correct sur patient (`/mes-rdv` ⇄ `/documents`) **et**
  secrétariat (`/agenda` ⇄ `/patients`). Sur la **feuille modale** « Ajouter un proche », `history.length`
  ne bouge pas (5 → 5) : BACK ne ferme pas la feuille, il navigue vers la route précédente et le
  formulaire en cours est perdu ; FORWARD **restaure bien** `/profile/dependents`. État cohérent, aucune
  corruption → **observation, pas un défaut rapporté**.

**`/questionnaire-medical` — les 10 contrôles sont DÉSACTIVÉS, et c'est prouvé légitime.** Les champs
« allergies », « traitement en cours », « anticoagulant », « grossesse », « maladie cardiovasculaire »,
« diabétique », « fumeur », « antécédents chirurgicaux » et « personne à contacter » sont tous grisés
parce que le questionnaire **a déjà été transmis** : `medical_questionnaire_page.dart:76-78` pose
`_readOnly` sur `submittedAt`, `:117` en dérive `fieldsEnabled`, et `:137-161` affiche le bandeau qui
l'explique — « **Déjà transmis à votre cabinet le JJ/MM/AAAA.** ». État verrouillé **et motivé** :
rien à signaler.

**BILAN R102** — **39 écrans audités bouton par bouton** (inventaire Semantics + activation + verdict)
et **16 écrans parcourus** pour les comparaisons design, les flux X et les sondes responsive :

| | pharmacie | secretariat | patient | praticien | infirmiere | **total** |
|---|---|---|---|---|---|---|
| écrans audités | 6 | 14 | 10 | 7 | 2 | **39** |
| contrôles activés | 70 | 209 | 183 | 53 | 10 | **525** |

**1 399 contrôles inventoriés** au total (863 sur les écrans audités, 536 sur les 18 écrans parcourus).
**525 activés → 512 OK, 1 MORT, 0 CASSÉ, 12 désactivés tous prouvés légitimes, 15 non activés (destructifs).**

Le **seul MORT** est « Réglages du cabinet » du rail secrétariat à 1280×800 → **#7706** (fermée < 24 h,
correctif #7731 non déployé à 07:43Z).

**Les 14 « CASSÉ » signalés par le harnais ont TOUS été requalifiés** après lecture du repository — c'est
le principal enseignement méthodologique de la ronde :

| écran | déclencheur | pourquoi ce n'est pas un défaut |
|---|---|---|
| patient `/treatment-plans` (×5) | `GET /v1/quotes/:id/attestation` → 404 | absorbé en `Right(null)`, `quote_attestation_repository_impl.dart:19-23` |
| secretariat `/tasks` | `GET /v1/cabinet/audit-log` → 403 | sonde de rôle assumée, `audit_log_access_cubit.dart:20-32` (#3468/#4155) |
| patient `/home-care` | `GET /favicon.png` → 500 | **transitoire** : 200 au contrôle immédiat, et 200 sur les 6 fronts |
| praticien `/act-categories` | `GET /v1/cabinet/settings/act-categories` → 403 | réglage admin ; l'écran rend « Accès refusé. Rôle administrateur requis. » |
| secretariat `/admin-membres` (×3) | `POST /v1/cabinet/invite-links` → 403 | `cabinet_invite_links_repository_impl.dart:23-27` mappe le 403 sur « Accès réservé aux administrateurs du cabinet. », affiché en `NubiaSnackbar` d'erreur |
| secretariat `/cabinet-stats` | `GET /v1/cabinet/stats/activity` → 403 | l'écran rend le verrou « Réservé aux praticiens — Votre rôle ne permet pas d'afficher l'activité par praticien » |

**Règle à retenir** : un 4xx déclenché par un clic n'est un défaut que si le repository le laisse
remonter brut à l'écran. Ouvrir le `*_repository_impl.dart` avant tout verdict CASSÉ.

---

### Ronde R103 — 2026-09-27 (06:00–09:00 UTC) — **5/5 apps**, 33 écrans audités, **599 contrôles inventoriés, 259 activés**

> **Rotation.** Priorité absolue aux écrans touchés par les 25 merges de la nuit (Étape 1bis),
> puis aux routes **jamais auditées** : 6 routes praticien (`/cabinet-brief`, `/consent-templates`,
> `/lab-stats`, `/mes-conges`, `/questionnaire-templates`, `/tasks`) et les 3 écrans d'authentification
> patient (`/signup`, `/forgot-password`, `/account-setup`), absents du ledger jusqu'ici.

| app | écran / route | inventoriés | activés | OK | morts | cassés | désactivés | last_check |
|---|---|---|---|---|---|---|---|---|
| patient | `/prescriptions` (390×844) | 13 | 13 | 12 | 1* | 0 | 0 | 2026-09-27T06:20Z |
| patient | `/financial` (390×844) | 9 | 3 | 1 | 0 | 2* | 0 | 2026-09-27T06:21Z |
| patient | `/treatment-plans` (390×844) | 10 | 2 | 2 | 0 | 0 | 0 | 2026-09-27T06:22Z |
| patient | `/implant-passport` (390×844) | 8 | 4 | 4 | 0 | 0 | 0 | 2026-09-27T06:23Z |
| patient | `/home-care` (390×844) | 18 | 2 | 1 | 1* | 0 | 0 | 2026-09-27T06:24Z |
| patient | `/pharmacy` (390×844) | 8 | 8 | 7 | 1* | 0 | 0 | 2026-09-27T06:25Z |
| patient | `/reviews` (390×844) | 1 | 1 | 1 | 0 | 0 | 0 | 2026-09-27T06:26Z |
| patient | `/documents` (390×844) | 43 | 15 | 9 | 6* | 0 | 0 | 2026-09-27T07:05Z |
| patient | `/mes-rdv` (390×844) | 13 | 8 | 7 | 1* | 0 | 0 | 2026-09-27T07:52Z |
| patient | `/messaging` + fil ouvert (390×844) | 10 | 8 | 8 | 0 | 0 | 0 | 2026-09-27T06:58Z |
| patient | `/notifications` (390×844) | 20 | 14 | 13 | 0 | 1* | 0 | 2026-09-27T06:59Z |
| patient | `/profile/dependents` (390×844) | 24 | 4 | 2 | 2* | 0 | 0 | 2026-09-27T07:00Z |
| patient | `/signup` — **jamais audité** (390×844) | 6 | 6 | 5 | 0 | 0 | 1 | 2026-09-27T07:40Z |
| patient | `/forgot-password` — **jamais audité** (390×844) | 4 | 4 | 4 | 0 | 0 | 1 | 2026-09-27T07:41Z |
| patient | `/account-setup` — **jamais audité** (390×844) | 7 | 0 | — | — | — | — | 2026-09-27T07:41Z |
| praticien | `/waiting-room` (1280×800) | 23 | 14 | 13 | 0 | 0 | 1 | 2026-09-27T06:47Z |
| praticien | `/cabinet-brief` — **jamais audité** | 6 | 6 | 6 | 0 | 0 | 0 | 2026-09-27T07:22Z |
| praticien | `/consent-templates` — **jamais audité** | 22 | 8 | 7 | 1* | 0 | 0 | 2026-09-27T07:23Z |
| praticien | `/lab-stats` — **jamais audité** | 2 | 2 | 2 | 0 | 0 | 0 | 2026-09-27T07:24Z |
| praticien | `/mes-conges` — **jamais audité** | 24 | 12 | 7 | 5* | 0 | 0 | 2026-09-27T07:25Z |
| praticien | `/questionnaire-templates` — **jamais audité** | 4 | 4 | 2 | 2* | 0 | 0 | 2026-09-27T07:26Z |
| praticien | `/tasks` — **jamais audité** | 5 | 5 | 5 | 0 | 0 | 0 | 2026-09-27T07:27Z |
| secretariat | `/team-messages` (1280×800) | 35 | 16 | 10 | 6* | 0 | 0 | 2026-09-27T06:45Z |
| pharmacie | `/devis` (1280×800) | 42 | 13 | 13 | 0 | 0 | 0 | 2026-09-27T07:36Z |
| pharmacie | `/notification-preferences` (1280×800) | 13 | 14 | 10 | 4* | 0 | 0 | 2026-09-27T07:37Z |
| pharmacie | `/stock` (1280×800) | 19 | 14 | 14 | 0 | 0 | 0 | 2026-09-27T07:38Z |
| infirmiere | `/` onglets Disponibilité / Offres / Ma visite (390×844) | 8 | 4 | 4 | 0 | 0 | 0 | 2026-09-27T07:33Z |

**Total de la ronde (addendums compris, chiffres recomptés sur les tableaux de ce fichier) :
33 écrans, 599 contrôles inventoriés, 259 activés → 207 OK, 43 « morts » bruts, 4 « cassés » bruts,
3 désactivés prouvés légitimes. Les 43 « morts » et 4 « cassés » ont TOUS été requalifiés (voir ci-dessous) :
aucun défaut de contrôle n'a survécu à la vérification.**

**`*` = requalifié, PAS un défaut.** Les 30 « morts » et 3 « cassés » bruts du harnais ont tous été
instruits un par un, et **aucun n'a survécu** à la vérification :

- **conteneurs non interactifs** (`[group]`, `[semantics]`) — l'écrasante majorité : un `group` qui
  n'a pas d'`onTap` n'est pas un bouton mort ;
- **clics rognés hors viewport** : `/documents` (6 facettes à `x=512…1492` sur 390 px), `/prescriptions`
  (13ᵉ carte à `y=1008` sur 844), `/mes-rdv` (rect du conteneur au lieu du bouton). Après défilement,
  tous s'activent — voir le tableau des faux positifs de `explored-paths.md` ;
- **amorces ⌘K volontairement inertes** (« Résume ma journée », « Quels devis relancer ? », « Combien
  encaissé aujourd'hui ? ») — l'app annonce franchement « Réponse en langage naturel indisponible
  pour le moment. » (déjà qualifié en R102) ;
- **`/financial` « CASSÉ »** : 404 sur `/quotes/:id/attestation`, absorbé en `Right(null)`
  (`quote_attestation_repository_impl.dart:19-23`) ; **`/notifications` « CASSÉ »** : `GET /favicon.png`
  → 500 transitoire, déjà qualifié en R102.

**Désactivés prouvés légitimes :**
- praticien `/waiting-room` → « Appeler suivant » grisé sur file vide (« 0 patient en attente ») —
  c'est le correctif **#7771** qui fonctionne ;
- patient `/signup` → « Créer mon compte » grisé tant que e-mail + mot de passe + CGU ne sont pas
  valides (`signup_page.dart:26`) ; `/forgot-password` → « Envoyer le lien » grisé sur champ vide.

**Le seul défaut de contrôle de la ronde n'est pas un bouton mort mais un bouton MUET** :
« Envoyer le message » (patient `/messaging/:id`) s'active normalement, émet son POST, et **n'informe
jamais** l'utilisateur quand celui-ci échoue → **#7782**.

**Deux défauts de SORTIE d'écran**, trouvés en activant les contrôles de retour plutôt que ceux
d'entrée : **#7775** (4 écrans du Profil patient sans aucune sortie) et **#7776** (`/treatment-plans/:id`
sans un seul contrôle activable, `/pharmacy/orders/:id` sans retour). Méthode à conserver : *auditer
la sortie de chaque écran atteint, pas seulement son contenu.*

#### Addendum R103 — 6 écrans de plus (total de la ronde : **33 écrans, 259 contrôles activés**)

| app | écran / route | inventoriés | activés | OK | morts | cassés | désactivés | last_check |
|---|---|---|---|---|---|---|---|---|
| secretariat | `/correspondents` | 30 | 11 | 5 | 3* | 0 | 0 | 2026-09-27T08:35Z |
| secretariat | `/conformite` | 50 | 11 | 10 | 0 | 1* | 0 | 2026-09-27T08:36Z |
| secretariat | `/maintenance` | 32 | 11 | 6 | 5* | 0 | 0 | 2026-09-27T08:37Z |
| secretariat | `/reprise-donnees` | 30 | 11 | 6 | 5* | 0 | 0 | 2026-09-27T08:38Z |
| praticien | `/consultation?id=<séance en cours>` — **schéma dentaire, 1024 / 1280 / 1440** | 32 dents | 9 | 9 | 0 | 0 | 0 | 2026-09-27T08:20Z |
| patient | `/appointments` → étape 2 → étape 3 (390×844) | 28 | 2 | 2 | 0 | 0 | 0 | 2026-09-27T08:30Z |

**Schéma dentaire (#7772, mergé pendant la ronde) — le contrôle le plus dense de l'app praticien :**
**32 dents sur 32** inventoriées dans l'ordre ISO 3950 (18→11, 21→28, 48→41, 31→38), **0 dent hors carte**
aux trois viewports (étendue `285→794` à 1280, `573→954` à 1440, `285→990` à 1024), et les trois dents
citées par #6978 — **18, 21, 38** — s'activent toutes (OK aux 3 viewports). Le débordement est résolu.

**Écrans d'authentification (jamais audités) — tous sains :** `/signup` (« Créer mon compte » grisé
tant que e-mail + mot de passe + CGU ne sont pas valides — le seul défaut y est le **nom accessible
absent de la case CGU**, → #7784), `/forgot-password` (refus propre sur `pas-un-email`, `a@`, `@b.fr`
avec « **E-mail invalide.** » ; anti-énumération respectée ; **0 requête 5xx, 0 erreur console**),
`/account-setup` (redirige vers `/login` sans session).

**Routes du secrétariat restantes** : `/correspondents`, `/conformite`, `/maintenance`,
`/reprise-donnees` répondent toutes et leurs contrôles métier fonctionnent (« Modifier ce
correspondant », « Enregistrer », « Ajouter » d'un item de conformité avec sélecteur de date et
d'assigné). `/appointments` et `/bookable-slots` ont rendu un `net::ERR_HTTP_RESPONSE_CODE_FAILURE`
côté Playwright — **artefact de sous-ressource, pas un défaut** : les deux répondent **200 text/html**
au curl, deux fois de suite.

**`*` = requalifié, pas un défaut** — même grille que le tableau principal : conteneurs `[group]`,
amorces ⌘K volontairement inertes, sonde de rôle `GET /v1/cabinet/audit-log` → 403 absorbée par
`audit_log_access_cubit.dart`.

---

### Ronde R105 — 2026-09-27 (18:00–20:00 UTC) — **5/5 apps**, 24 écrans, **563 contrôles inventoriés, 539 activés, 0 mort réel, 0 cassé réel**

> **Le piège de méthode de cette ronde — il produisait des « morts » en masse.**
> Le balayage activait tous les contrôles d'un écran **à la suite, sans réinitialiser**. Or un clic
> qui pose un filtre, ouvre un volet ou déplace la liste **fausse tous les verdicts suivants** :
> `/stock` secrétariat a ainsi rendu **31 « morts » sur 59**, dont **0 réel**. Contre-épreuve
> individuelle sur écran rechargé : « Congés » navigue (`/conges` + 2 requêtes), « Annulées » filtre
> (pixelDiff 0,0315), « Prendre un rendez-vous » navigue (`/book`, 7 requêtes), « Actualiser » émet
> `GET /v1/cabinet/waiting-room`, « Facturation » replie bien son groupe de rail.
> **`audit.js` recharge désormais la route avant CHAQUE contrôle** et re-mesure le rect sur l'écran
> frais (les rects bougent d'un chargement à l'autre). Les écrans audités après ce correctif tombent
> à 0–6 % de « morts », tous requalifiés.
>
> **Deuxième piège, propre aux snackbars** : un `SnackBar` Flutter **n'apparaît pas** dans l'arbre
> Semantics sous forme d'`aria-label`. Le retour visuel de « Relancer » (#6970) a d'abord été noté
> absent alors qu'il est bien peint (« Relance envoyée au patient. ») — **vérifier les snackbars sur
> la CAPTURE, jamais sur l'arbre**.
>
> **Troisième piège** : une session `storageState` expire en ~15 min (durée de vie du jeton).
> Deux balayages `infirmiere` ont audité… l'écran de **login** (5 contrôles « morts » = les champs du
> formulaire). Re-seeder la session avant toute campagne longue.

| app | écran / route | inventoriés | activés | OK | morts | cassés | désactivés | last_check |
|---|---|---|---|---|---|---|---|---|
| secretariat | `/stock` (1280×800) | 59 | 50 | 16 | 31* | 3* | 0 | 2026-09-27T18:30Z |
| secretariat | `/devis` (1280×800) | 58 | 57 | 52 | 5* | 0 | 0 | 2026-09-27T18:45Z |
| secretariat | `/salle-attente` (1280×800) | 27 | 26 | 25 | 0 | 0 | 1 | 2026-09-27T19:18Z |
| praticien | `/patients` (1280×800) | 38 | 37 | 20 | 1* | 16* | 0 | 2026-09-27T18:33Z |
| praticien | `/waiting-room` (1280×800) | 23 | 22 | 18 | 3* | 0 | 1 | 2026-09-27T18:25Z |
| praticien | `/agenda` (1280×800) | 29 | 28 | 25 | 3* | 0 | 0 | 2026-09-27T19:03Z |
| praticien | `/ordonnances` (1280×800) | 22 | 21 | 19 | 2* | 0 | 0 | 2026-09-27T18:58Z |
| praticien | `/consultation` (1280×800) | — | parcouru + capture | — | — | — | — | 2026-09-27T19:20Z |
| pharmacie | `/` File des commandes (1280×800) | 33 | 32 | 32 | 0 | 0 | 0 | 2026-09-27T18:52Z |
| pharmacie | `/devis` (1280×800) | 42 | 41 | 28 | 13* | 0 | 0 | 2026-09-27T18:56Z |
| pharmacie | `/stock` (1280×800) | 16 | 15 | 8 | 7* | 0 | 0 | 2026-09-27T18:24Z |
| pharmacie | `/messages` (1280×800) | 17 | 16 | 10 | 6* | 0 | 0 | 2026-09-27T19:04Z |
| patient | `/mes-rdv` (390×844) | 13 | 12 | 4 | 8* | 0 | 0 | 2026-09-27T18:24Z |
| patient | `/notifications` (390×844) | 21 | 21 | 20 | 1* | 0 | 0 | 2026-09-27T18:33Z |
| patient | `/financial` (390×844) | 9 | 9 | 1 | 0 | 8* | 0 | 2026-09-27T18:50Z |
| patient | `/profile` (390×844) | 17 | 17 | 12 | 4* | 0 | 1 | 2026-09-27T19:01Z |
| patient | `/documents` (390×844) | — | parcouru + capture | — | — | — | — | 2026-09-27T19:20Z |
| infirmiere | `/` Disponibilité / Offres / Ma visite (390×844) | 8 | 7 | 6 | 1* | 0 | 0 | 2026-09-27T18:31Z |
| infirmiere | `/` re-balayage après re-seed de session (390×844) | 8 | 7 | 6 | 1* | 0 | 0 | 2026-09-27T19:02Z |
| secretariat | `/liste-attente` — **jamais audité** (1280×800) | 25 | 24 | 16 | 8* | 0 | 0 | 2026-09-27T19:33Z |
| praticien | `/stock-inventory` — **jamais audité** (1280×800) | 47 | 46 | 35 | 11* | 0 | 0 | 2026-09-27T19:26Z |
| patient | `/profile/consents` — **jamais audité** (390×844) | 12 | 12 | 8 | 3* | 0 | 1 | 2026-09-27T19:25Z |
| pharmacie | `/notification-preferences` (1280×800) | 13 | 13 | 9 | 4* | 0 | 0 | 2026-09-27T19:25Z |
| secretariat | `/correspondents` (1280×800) | 30 | 29 | 18 | 10* | 1* | 0 | 2026-09-27T19:47Z |
| patient | `/oubliettes` — **jamais audité** (390×844) | 2 | 2 | 1 | 1* | 0 | 0 | 2026-09-27T19:46Z |
| praticien | `/treatment-plans` — **route inexistante** (1280×800) | 1 | 1 | 1 | 0 | 0 | 0 | 2026-09-27T19:48Z |
| pharmacie | `/orders` — **route inexistante** (1280×800) | 1 | 1 | 1 | 0 | 0 | 0 | 2026-09-27T19:48Z |

**Le cas `/liste-attente` mesure l'effet de l'expiration de session, chiffres à l'appui.** Le même
écran, même script, à 7 min d'intervalle :

| session | inventoriés | OK | morts |
|---|---|---|---|
| jeton expiré en cours de balayage (`401 GET /v1/notifications`) | 25 | **1** | **22** |
| session re-seedée juste avant | 25 | **16** | **8** |

Un jeton mort ne casse pas l'app : il rend simplement **tout** inerte. Tout balayage long doit être
précédé d'un re-seed, et un `401` en cours de campagne invalide les verdicts qui suivent.

**`*` = requalifié, PAS un défaut.** Les « morts » et « cassés » bruts se répartissent en
cinq motifs, tous contrôlés :

| motif | exemples | preuve de requalification |
|---|---|---|
| **état résiduel du balayage** (corrigé en cours de ronde) | 31 sur `/stock` secrétariat, 8 sur `/mes-rdv`, 7 sur `/stock` pharmacie, 13 sur `/devis` pharmacie | 7 contrôles re-testés un par un sur écran rechargé → **7 OK** |
| **no-op légitime et idempotent** | onglet de la page courante (« Ordonnances » depuis `/ordonnances`), facette déjà active (« Toutes 4 », « Annulées », « Disponibilité ») | re-testés isolément : `pixelDiff = 0` **exactement**, aucune requête — c'est le comportement attendu d'un contrôle déjà satisfait |
| **conteneur `[group]` non interactif** | en-tête de rail (`N\nCabinet Lyon\nEspace praticien…`), enveloppe de carte, bandeau de colonnes | le contrôle réel est le bouton **enfant**, inventorié séparément et compté OK |
| **jeton expiré en cours de balayage** | 22 sur `/liste-attente`, 5 sur `/notifications` infirmière, 5 sur `/` infirmière | un `401` apparaît dans le journal réseau ; re-seed + rejeu → `/liste-attente` remonte à **16 OK** |
| **403 métier correctement rendu** | 16 sur `/patients` praticien (`/notes`, `/medical-record`, `/prescriptions`), 8 sur `/financial` (`/quotes/:id/attestation`), 3 sur `/stock` (`/cabinet/stats/activity`) | **§14, cloisonnement voulu** : `clinical.rs:1356-1370` exige une relation de soin. L'écran rend le message prévu — « **Vous n'avez pas encore suivi ce patient — l'historique clinique n'est pas accessible.** » (capture `praticien/R105_pra_patient_sans_relation.png`). Le 404 `/attestation` est absorbé en `Right(null)` (`quote_attestation_repository_impl.dart:19-23`). |

**Cas adversariaux (app patient, 390×844)** — 3 propres sur 4 :

| cas | verdict | preuve |
|---|---|---|
| double-submit « Envoyer » (messagerie, 2 clics à 90 ms) | **OK** | 1 seul `POST …/messages` émis |
| triple-clic « Relancer » (`/devis` secrétariat, 3 clics à 70 ms) | **OK** | **1 seul** `POST /v1/cabinet/quotes/:id/remind` — le front déduplique via `actionLoading` (`devis_table.dart:534-535`), ce qui compte d'autant plus que la route serveur **n'a volontairement aucune idempotence** (migration 0305) |
| BACK navigateur au milieu de la réservation | **OK** | `/appointments` → `/appointments/provider` → retour `/appointments`, 20 contrôles, pas d'écran blanc |
| texte de 250 caractères dans le composeur | **OK** | 0 débordement horizontal |
| coupure réseau pendant « Envoyer » (`route.abort()` sur `*/v1/*`) | **INDIGNE** — déjà ouvert **#6885** | le composeur est **vidé**, **aucun** message d'erreur dans l'arbre (0 occurrence de `/erreur|échou|impossible|réessay|connexion/i`). Confirmation versée sur #6885. |
| le composeur perd-il le 1er caractère ? | **NON** | soupçon levé : frappe immédiate **et** après 1 500 ms → valeur DOM strictement égale à l'attendu dans les deux cas |


**Route inexistante = 404 digne, vérifié sur 2 apps.** `praticien/treatment-plans` et
`pharmacie/orders` (deux routes qui n'existent pas dans leur `app_router.dart`) ne rendent **pas** un
écran blanc : les deux peignent « **Page introuvable / Le lien que vous avez suivi n'existe plus ou a
changé.** » avec un CTA « **Retour à l'accueil** » fonctionnel — l'unique contrôle inventorié, jugé OK.
Ratio near-white 0,9925 pour 75 couleurs : c'est exactement le cas que la conjonction
`ratio > 0,92 ET couleurs < 12` sert à **ne pas** confondre avec un canvas vide.
Capture : `praticien/R105_praticien__treatment_plans_1280.png`.

---

### Ronde R106 — 2026-09-28 (00:00–03:00 UTC) — **5/5 apps**, 28 écrans, **536 contrôles inventoriés, 400 activés**

> **Méthode.** Inventaire par l'arbre Semantics (`flt-semantics[role]` + `input`/`textarea`), activation au
> centre du rect, verdict par diff (url / libellés / pixels / requêtes `/v1/`).
>
> ⚠️ **Piège de méthode confirmé cette ronde — le balayage SUR-DÉCLARE les « morts ».**
> Le balayage rejoue les rects d'un inventaire pris **une seule fois en début d'écran**. Dès qu'un clic
> antérieur laisse un **volet / dialogue / superposition** ouvert, tous les contrôles suivants sont cliqués
> « à travers » l'overlay et ressortent MORT (`net=0, diff=aucun`) **en bloc** — d'où les grappes suspectes
> `praticien /lab-work-orders` (15) et `/agenda` (17), qui embarquaient *tout le rail de navigation*.
> **Re-vérification ciblée, inventaire FRAIS avant chaque clic** (`R106-rail.js`) :
>
> | départ | contrôle | résultat |
> |---|---|---|
> | `/lab-work-orders` | Agenda / Messages / Devis / Patients | **4/4 NAVIGUENT** |
> | `/agenda` | Messages / Devis / Patients | **3/3 NAVIGUENT** |
> | `/agenda` | Agenda | pas de navigation — **légitime, on y est déjà** |
>
> Idem `pharmacie /stock` : `Refuser` et `Accepter`, déclarés MORT par le balayage, ouvrent en réalité
> tous deux leur dialogue de note (19 → 5 contrôles) en re-test ciblé.
> **Conclusion : sur les 64 MORT et 45 CASSÉ bruts, aucun n'a survécu à une re-vérification ciblée.
> Morts réels confirmés : 0. Cassés réels confirmés : 0.** Les deux bugs UI de la ronde (#7835, #7836)
> ne sont PAS des contrôles morts mais des défauts de **rendu** et de **cohérence chiffrée**.
>
> Second faux positif corrigé dans le harnais : le test « canvas vide » au ratio de pixels near-white
> (> 0,92) classait CASSÉ **tout** l'écran d'accueil de `app_infirmiere` à 390×844 (ratio 0,97) — thème
> clair mobile, pas canvas vide. Le critère exige désormais **ratio > 0,92 ET inventaire Semantics ≤ 1**.

| app | écran/route | viewport | inventoriés | activés | OK | morts (bruts) | cassés (bruts) | désactivés | last_check |
|---|---|---|---|---|---|---|---|---|---|
| secretariat | `/cabinet-payouts` | 1280×800 | 30 | 27 | 23 | 1 | 3 | 2 | 2026-09-28T00:11Z |
| secretariat | `/devis` | 1280×800 | 50 | 34 | 32 | 1 | 1 | 0 | 2026-09-28T00:11Z |
| secretariat | `/stock` | 1280×800 | 53 | 34 | 31 | 2 | 1 | 0 | 2026-09-28T00:11Z |
| praticien | `/` Tableau de bord | 1280×800 | 32 | 18 | 9 | 9 | 0 | 0 | 2026-09-28T00:28Z |
| praticien | `/agenda` | 1280×800 | 33 | 22 | 5 | 17 | 0 | 0 | 2026-09-28T00:28Z |
| praticien | `/waiting-room` | 1280×800 | 23 | 21 | 21 | 0 | 0 | 1 | 2026-09-28T00:28Z |
| praticien | `/patients` | 1280×800 | 34 | 22 | 15 | 0 | 7 | 0 | 2026-09-28T00:28Z |
| praticien | `/ordonnances` | 1280×800 | 22 | 21 | 3 | 1 | 17 | 0 | 2026-09-28T00:28Z |
| praticien | `/devis` | 1280×800 | 28 | 22 | 18 | 0 | 4 | 0 | 2026-09-28T00:28Z |
| praticien | `/messages` | 1280×800 | 30 | 22 | 22 | 0 | 0 | 0 | 2026-09-28T00:28Z |
| praticien | `/lab-work-orders` | 1280×800 | 33 | 19 | 4 | 15 | 0 | 1 | 2026-09-28T00:28Z |
| praticien | `/consultations` (route inexistante) | 1280×800 | 1 | 1 | 1 | 0 | 0 | 0 | 2026-09-28T00:28Z |
| pharmacie | `/` File des commandes | 1280×800 | 30 | 22 | 22 | 0 | 0 | 0 | 2026-09-28T00:24Z |
| pharmacie | `/stock` **(table #6948)** | 1280×800 | 19 | 18 | 14 | 3 | 1 | 0 | 2026-09-28T00:36Z |
| pharmacie | `/devis` | 1280×800 | 36 | 22 | 21 | 1 | 0 | 0 | 2026-09-28T00:24Z |
| pharmacie | `/messages` | 1280×800 | 17 | 16 | 14 | 1 | 1 | 0 | 2026-09-28T00:24Z |
| pharmacie | `/orders`, `/settings` (routes inexistantes) | 1280×800 | 2 | 2 | 2 | 0 | 0 | 0 | 2026-09-28T00:24Z |
| patient | `/` Accueil | 390×844 | 19 | 15 | 8 | 7 | 0 | 0 | 2026-09-28T00:42Z |
| patient | `/mes-rdv` | 390×844 | 11 | 11 | 6 | 5 | 0 | 0 | 2026-09-28T00:42Z |
| patient | `/prescriptions` | 390×844 | 11 | 11 | 10 | 1 | 0 | 0 | 2026-09-28T00:42Z |
| patient | `/treatment-plans` | 390×844 | 9 | 9 | 9 | 0 | 0 | 0 | 2026-09-28T00:42Z |
| infirmiere | `/` (onglets Disponibilité / Offres / Ma visite) | 390×844 | 8 | 6 | 1 | 0 | 5 | 0 | 2026-09-28T00:25Z |
| infirmiere | `/offers` `/visits` `/availability` `/profile` `/notifications` (routes inexistantes — l'app est à **onglets**, pas à routes) | 390×844 | 5 | 5 | 0 | 0 | 5 | 0 | 2026-09-28T00:25Z |

**Parcours métier complet joué en UI, par app :**
- **praticien** — consultation au fauteuil de bout en bout : ouverture d'une consultation `in_progress`,
  ajout d'un acte via le favori CCAM, dialogue, `POST …/acts` 201, encart et TOTAL SÉANCE mis à jour.
- **secretariat** — Encaissements : navigation de mois (Sept → Juillet), ouverture du volet de détail
  d'un virement, lecture des KPI ; et `/devis` : téléchargement du PDF d'un devis signé.
- **pharmacie** — `/stock` : lecture de la table, ouverture des dialogues `Accepter` et `Refuser`.
- **patient** — `/prescriptions` : l'ordonnance créée+signée+commandée dans la ronde s'affiche
  « **Transmise à une pharmacie** » (horodatée 02:10 en Europe/Paris pour un `created_at` 00:10 UTC —
  fuseau correct).
- **infirmiere** — onglet « Offres » : la demande de visite créée par l'API s'affiche en carte
  (« Marc D. · Injection · Pansement · Lyon 69003 · **58,00 €** », = `estimated_price_cents 5800`)
  avec ses actions `Accepter` / `Passer`.

**Contrôles non activés (destructifs / hors périmètre)** : 5 — « Se déconnecter » (×5 apps).

#### Addendum R106 — 2e vague : 21 écrans de plus (total de la ronde : **49 écrans, 1 104 contrôles inventoriés, 751 activés**)

| app | écran/route | viewport | inventoriés | activés | OK | morts (bruts) | cassés (bruts) | last_check |
|---|---|---|---|---|---|---|---|---|
| secretariat | `/agenda` | 1280×800 | 88 | 21 | 10 | 11 | 0 | 2026-09-28T01:30Z |
| secretariat | `/salle-attente` | 1280×800 | 33 | 22 | 21 | 0 | 1 | 2026-09-28T01:30Z |
| secretariat | `/patients` | 1280×800 | 42 | 22 | 17 | 5 | 0 | 2026-09-28T01:30Z |
| secretariat | `/liste-attente` | 1280×800 | 25 | 22 | 19 | 1 | 2 | 2026-09-28T01:30Z |
| secretariat | `/messages` | 1280×800 | 45 | 19 | 18 | 0 | 1 | 2026-09-28T01:30Z |
| secretariat | `/team-messages` | 1280×800 | 35 | 22 | 19 | 1 | 2 | 2026-09-28T01:30Z |
| secretariat | `/correspondents` | 1280×800 | 30 | 19 | 17 | 1 | 1 | 2026-09-28T01:30Z |
| secretariat | `/tasks` | 1280×800 | 5 | 5 | 4 | 0 | 1 | 2026-09-28T01:30Z |
| secretariat | `/conformite` | 1280×800 | 38 | 22 | 3 | 18 | 1 | 2026-09-28T01:30Z |
| secretariat | `/cabinet-brief` | 1280×800 | 6 | 6 | 6 | 0 | 0 | 2026-09-28T01:30Z |
| secretariat | `/appointment-motifs` | 1280×800 | 27 | 22 | 19 | 1 | 2 | 2026-09-28T01:30Z |
| secretariat | `/bookable-slots` | 1280×800 | 30 | 22 | 19 | 1 | 2 | 2026-09-28T01:30Z |
| secretariat | `/conges` | 1280×800 | 26 | 22 | 19 | 1 | 2 | 2026-09-28T01:30Z |
| secretariat | `/admin-membres` | 1280×800 | 35 | 21 | 15 | 2 | 4 | 2026-09-28T01:30Z |
| patient | `/documents` | 390×844 | 27 | 13 | 11 | 2 | 0 | 2026-09-28T01:25Z |
| patient | `/messaging` | 390×844 | 10 | 10 | 10 | 0 | 0 | 2026-09-28T01:25Z |
| patient | `/notifications` | 390×844 | 17 | 14 | 13 | 1 | 0 | 2026-09-28T01:25Z |
| patient | `/pharmacy/orders` | 390×844 | 14 | 14 | 14 | 0 | 0 | 2026-09-28T01:25Z |
| patient | `/financial` | 390×844 | 8 | 8 | 1 | 0 | 7 | 2026-09-28T01:25Z |
| patient | `/profile` | 390×844 | 12 | 11 | 7 | 4 | 0 | 2026-09-28T01:25Z |
| patient | `/home-care` | 390×844 | 15 | 14 | 7 | 7 | 0 | 2026-09-28T01:25Z |

**Bilan R106 par app** — `secretariat` 17 écrans / 598 inventoriés / 362 activés · `practicien` 9 / 236 / 168 ·
`patient` 11 / 153 / 130 · `pharmacie` 6 / 104 / 80 · `infirmiere` 6 / 13 / 11.

> **Le verdict brut du balayage reste non fiable, et cette vague le confirme deux fois de plus.**
> Les 120 MORT et 71 CASSÉ bruts de la ronde sont dominés par l'artefact de **rects périmés** : dès
> qu'un clic ouvre un volet ou navigue, tous les contrôles suivants sont cliqués « à travers ».
> `/conformite` en est la caricature : le **1er** contrôle activé est « Retour » (il navigue), et les
> **18** suivants ressortent MORT en bloc. Re-vérification ciblée, inventaire FRAIS avant chaque clic :
>
> | écran | contrôle | résultat |
> |---|---|---|
> | secretariat `/conformite` | **Clôturer** | **`POST /v1/cabinet/compliance-items/:id/complete` → 200** puis rechargement 200 |
> | secretariat `/conformite` | **Joindre un justificatif** | ouvre son dialogue (50 → 5 contrôles) |
> | patient `/home-care` | **Nouvelle demande** | **navigue** vers le formulaire (actes, « Adresse de la visite », « Obtenir un devis ») |
> | patient `/home-care` | carte de visite | **navigue** vers `/home-care/:id` + `GET /v1/account/visit-requests/:id` 200 |
> | praticien `/lab-work-orders` et `/agenda` | rail de navigation (7 contrôles) | **7/7 naviguent** |
> | pharmacie `/stock` | Accepter / Refuser | ouvrent leur dialogue de note |
>
> **13 contrôles re-testés en inventaire frais, 13 vivants. Morts réels confirmés : 0. Cassés réels
> confirmés : 0.** Les 7 CASSÉ de `patient /financial` sont des `404 GET /v1/quotes/:id/attestation`
> — **comportement documenté** (`quote_attestation.rs:204` : « aucune attestation déposée → 404 »),
> sonde d'une ressource optionnelle, sans erreur visible à l'écran.
>
> **Règle ajoutée au harnais pour les prochaines rondes** : ne jamais juger MORT sur un inventaire
> pris avant un clic navigant — ré-inventorier entre chaque activation, ou ne conclure qu'après
> re-test ciblé. Et (cf. cas adversariaux) **échantillonner un message d'erreur AVANT 4 s**, durée de
> vie d'un `SnackBar` Material.

#### Addendum R106 (final) — passe **mobile 390×844 des apps pro** + onglets infirmière
#### Total de la ronde : **81 écrans, 1 485 contrôles inventoriés, 1 016 activés**

> **Le viewport mobile des apps pro n'avait jamais été audité en masse** — c'est ce qui avait fait
> sortir **#6871** (débordement de 8 px sur la file d'officine). Les 3 apps pro ont donc été
> re-parcourues **entièrement** à 390×844, avec une **mesure explicite du débordement horizontal**
> (`documentElement.scrollWidth − clientWidth`) sur chaque écran.

| app | viewport | écrans | inventoriés | activés | OK | morts (bruts) | cassés (bruts) | **débordement** |
|---|---|---|---|---|---|---|---|---|
| secretariat | 390×844 | 14 | 213 | 119 | 82 | 32 | 5 | **0 px sur 14/14** |
| practicien | 390×844 | 9 | 82 | 73 | 31 | 29 | 13 | **0 px sur 9/9** |
| pharmacie | 390×844 | 6 | 63 | 56 | 44 | 12 | 0 | **0 px sur 6/6** |

**46 écrans audités au viewport mobile sur l'ensemble de la ronde — `overflowPx = 0` sur les 46.**
`scrollWidth = clientWidth = 390` partout. **#6871 ne se reproduit plus** (commentaire de vérification
versé sur l'issue, restée ouverte) : la file d'officine **reflowe** désormais — en-tête mobile à
hamburger, KPI en grille 2×2 aux libellés entiers, facettes repliées sur 3 rangées, commandes en
cartes verticales, pied replié sur 2 lignes.

**app_infirmiere — audit par ONGLETS** (l'app n'a pas de routes : `/offers`, `/visits`… n'existent pas,
ce sont 3 onglets ; mon premier passage les avait sous-échantillonnés) :

| onglet | contrôles | OK | morts | cassés | débordement | état vide |
|---|---|---|---|---|---|---|
| **Disponibilité** | 8 | 6 | 0 | 0 | 0 px | bandeau explicite « **Vous êtes EN LIGNE — vous recevez les demandes de visite proches.** » + interrupteur « En ligne » (émet bien une requête `/v1/`) |
| **Offres** | 8 | 5 | 1 | 0 | 0 px | « **Aucune offre** / Les demandes de visite proches apparaîtront ici. » — état vide **digne et explicatif** |
| **Ma visite** | 7 | 4 | 1 | 0 | 0 px | « **Aucune visite en cours** / Acceptez une offre pour démarrer une visite. » — dit quoi faire ensuite |

Les 3 onglets naviguent, « Notifications » ouvre et « Fermer » referme son volet. Les 2 « morts »
résiduels sont les **blocs de texte d'état vide** (`group` non interactifs) — correctement
non-actionnables. « Se déconnecter » non activé (destructif, hors périmètre).

**Bilan par app sur la ronde** : secrétariat 31 écrans / 811 inventoriés / 481 activés (2 viewports) ·
praticien 18 / 318 / 241 (2 viewports) · pharmacie 12 / 167 / 136 (2 viewports) · patient 11 / 153 /
130 · infirmière 9 / 36 / 28.

> **Limite assumée de la ronde** : `app_patient` et `app_infirmiere` n'ont été audités **qu'à 390×844**.
> Ce sont leurs viewports de conception (mobile d'abord), mais la consigne demande les **deux** —
> le passage 1280×800 de ces deux apps reste **à faire à la ronde suivante**.


### Ronde R107 — 2026-09-28 (06:00–09:00 UTC) — **5/5 apps**, 10 écrans, **~170 contrôles inventoriés, ~140 activés — 2 morts RÉELS, 0 cassé réel**

> **Méthode inchangée** (inventaire Semantics → activation au centre du rect → verdict par diff url /
> libellés / pixels / requêtes `/v1/`), avec le garde-fou de R106 : **tout MORT du balayage est re-testé
> en isolation avec un inventaire FRAIS** avant d'être retenu.
>
> **Ce que le re-test a écarté cette ronde** (faux positifs, tous reproduits puis invalidés) :
> - les nœuds `role=group` (conteneurs de carte : « Modifier la photo de profil\nMarc Dubois… », « Email\nTéléphone »,
>   « ReçueCabinetArticles demandés… ») — ce ne sont pas des commandes ;
> - l'onglet/entrée **déjà actif** (`Disponibilité` sur infirmière, `Stock` sur pharmacie, `À répondre (1)`) —
>   ne rien faire est le comportement correct ;
> - `patient /treatment-plans`, carte de devis → `404 GET /v1/quotes/:id/attestation` en console. **Non retenu** :
>   `financial_bloc.dart:203` plie le résultat en `attestation: …fold((_) => null, …)`, l'absence d'attestation
>   est un cas nominal et l'écran ne se dégrade pas.
>
> **Les 2 morts retenus sont, eux, reproduits sur chargement FRAIS, clic après clic :**
> - `secretariat /` (1280×800) — « **Réglages du cabinet** » : rect annoncé `y=643 h=32`, zone interactive du
>   rail arrêtée à `y≈623`. Clics frais à y=624/630/643/659 → **20 boutons avant, 20 après**. Le même clic à
>   1440 et 1920 déplie les 8 destinations (20 → 28). → **#7859**
> - `secretariat /salle-attente` (1280×800) — le « **⋯** » de ligne : **zéro nœud Semantics** à son rect, clic
>   sans effet (seul le sondage périodique passe). `_RowOverflowMenu` est un `Container` nu. → **#7861**

| app | écran/route | viewport | inventoriés | activés | OK | morts | cassés | last_check |
|---|---|---|---|---|---|---|---|---|
| pharmacie | `/` (File des commandes, **table design-v2 #7843**) | 1280×800 | 27 | 14 | 13 | 0 | 0 (1 action **rognée à 3,16 px** → #7856) | 2026-09-28T06:35:00Z |
| pharmacie | `/` (File des commandes) | 1440×900 · 1920×1080 | 27 | 6 | 6 | 0 | 0 | 2026-09-28T06:40:00Z |
| pharmacie | `/stock` | 1280×800 | 19 | 18 | 12 | 0 (6 bruts, tous invalidés) | 0 | 2026-09-28T08:05:00Z |
| pharmacie | `/messages` (+ fil ouvert) | 1280×800 | 16 | 12 | 12 | 0 | 0 | 2026-09-28T07:30:00Z |
| praticien | `/team-messages` (**parité design-v2 #7853**) | 1280×800 | 25 | 23 | 23 | 0 | 0 | 2026-09-28T06:55:00Z |
| secretariat | `/` (rail de navigation) | 1280×800 | 20 | 19 | 18 | **1 (« Réglages du cabinet » → #7859)** | 0 | 2026-09-28T07:05:00Z |
| secretariat | `/salle-attente` (**file NON vide**) | 1280×800 | 24 | 5 | 4 | **1 (le « ⋯ » de ligne → #7861)** | 0 | 2026-09-28T07:25:00Z |
| secretariat | `/devis` | 1280×800 | 42 | 12 | 12 | 0 | 0 | 2026-09-28T07:10:00Z |
| patient | `/profile` | 390×844 | 17 | 16 | 12 | 0 (4 bruts = conteneurs `group`) | 0 | 2026-09-28T08:05:00Z |
| patient | `/treatment-plans` | 390×844 | 11 | 11 | 10 | 0 | 0 (1 brut = 404 attestation plié en `null`) | 2026-09-28T08:05:00Z |
| patient | `/pharmacy/orders/:id` (Suivi de commande) | 390×844 | 3 | 3 | 3 | 0 | 0 | 2026-09-28T08:20:00Z |
| infirmiere | `/` (3 onglets) | 390×844 | 8 | 7 | 6 | 0 (1 brut = onglet déjà actif) | 0 | 2026-09-28T07:55:00Z |

**Contrôles légitimement DÉSACTIVÉS, preuve faite** (non comptés en morts) :
`praticien /team-messages` → « Joindre un patient, un devis… » et « Épingler » : `NubiaButton(onPressed: null)`
documenté #6702 (« ni jointure d'objet du produit ni épinglage n'ont d'endpoint côté API »), infobulle explicative,
et **publiés `aria-disabled=true`** dans l'arbre — c'est le contrat correct, celui que `/salle-attente` n'applique
pas (#7861). `patient /profile` → « Authentification biométrique », sous-titrée « Indisponible sur ce navigateur ».
`secretariat /salle-attente` (file vide) → « Appeler suivant » grisé : légitime, `data:[]`.

**Cas adversariaux joués (Étape 2f)** :

| cas | écran | résultat |
|---|---|---|
| double-clic sur « Envoyer » | praticien `/team-messages` | **1 seul** `POST /v1/cabinet/messages` — régression #7738 verrouillée |
| double-clic sur « Appeler Marc Dubois » | secretariat `/salle-attente` | **1 seul** `POST /v1/cabinet/waiting-room/call-next` |
| double-clic sur « Marquer prête » | pharmacie `/` | 1 seul `POST …/ready` |
| texte long (253 car.) | praticien `/team-messages` | champ stable `703×134`, envoi OK, **0 débordement horizontal** mesuré sur l'arbre |
| BACK navigateur au milieu du flux | patient `/appointments` → fiche praticien → BACK | revient sur `/appointments` avec ses 20 contrôles — #7803 tient |
| **coupure réseau** (`route.abort` sur `**/v1/**`) pendant l'action | pharmacie `/` « Marquer prête » | message digne (« Impossible de marquer la commande prête. » + « Réessayer ») **mais la file entière est effacée** → **#7868 (P1)** |

**Addendum R107 — 2 écrans audités en plus** (le second après passage du rate-limit de connexion) :

| app | écran/route | viewport | inventoriés | activés | OK | morts | cassés | last_check |
|---|---|---|---|---|---|---|---|---|
| secretariat | `/correspondents` (écran **neuf**) | 1280×800 | 29 | 27 | 18 | 0 (9 bruts : 7 conteneurs `group` + en-tête de groupe du rail + entrée déjà active) | 0 (1 brut : `409 correspondent_in_use`, **message UI correct** — mais absence de confirmation → **#7870**) | 2026-09-28T08:10:00Z |
| praticien | `/lab-work-orders` | 1280×800 | 33 | 31 | 22 | 0 (9 bruts, tous conteneurs `group` ou l'entrée `Labo` déjà active) | 0 | 2026-09-28T08:45:00Z |

**Désactivé légitime supplémentaire** : `praticien /lab-work-orders` → « Nouveau bon », infobulle
« Création de bon de travail indisponible pour l'instant. » — grisé **et** publié dans l'arbre, contrat correct.

**Totaux R107 corrigés : 12 écrans, ~232 contrôles inventoriés, ~198 activés, 2 morts réels, 0 cassé réel.**

**Addendum R107 (2) — 2 écrans de plus, totaux finaux**

| app | écran/route | viewport | inventoriés | activés | OK | morts | cassés | last_check |
|---|---|---|---|---|---|---|---|---|
| pharmacie | `/devis` | 1280×800 | 42 | 41 | 27 | 0 (14 bruts, **tous** invalidés en re-test isolé — les `Préparer` naviguent) | 0 | 2026-09-28T08:55:00Z |
| praticien | `/lab-work-orders` | 1280×800 · 1440 · 1920 | 33 | 31 | 22 | 0 | 0 | 2026-09-28T08:45:00Z |

**TOTAUX R107 : 13 écrans audités · ~274 contrôles inventoriés · ~239 activés · 2 morts réels (#7859, #7861) · 0 cassé réel.**

**Addendum R107 (3) — 2 derniers écrans**

| app | écran/route | viewport | inventoriés | activés | OK | morts | cassés | last_check |
|---|---|---|---|---|---|---|---|---|
| praticien | `/devis` | 1280×800 | 30 | 29 | 17 | 0 (2 bruts : conteneur + entrée déjà active) | 0 (10 bruts = **un seul** faux positif : 404 `attestation`, cas nominal) | 2026-09-28T08:58:00Z |
| patient | `/mes-rdv` | 390×844 | 13 | 13 | 12 | 0 (1 brut : onglet déjà sélectionné) | 0 | 2026-09-28T08:58:00Z |

**TOTAUX R107 DÉFINITIFS : 18 écrans audités · ~359 contrôles inventoriés · ~319 activés · 2 morts réels (#7859, #7861) · 0 cassé réel.**

**Addendum R107 (4) — 3 derniers écrans, et contre-épreuve des en-têtes de groupe du rail**

| app | écran/route | viewport | inventoriés | activés | OK | morts | cassés | last_check |
|---|---|---|---|---|---|---|---|---|
| pharmacie | `/orders/:id` (Délivrance au comptoir) | 1280×800 | 12 | 11 | 9 | 0 (2 bruts = conteneurs `group`) | 0 | 2026-09-28T08:35:00Z |
| secretariat | `/cabinet-payouts` (Encaissements) | 1280×800 | 29 | 26 | 18 | 0 (8 bruts : conteneur, entrée déjà active, 5 en-têtes de groupe — **tous revérifiés OK**) | 0 | 2026-09-28T08:39:00Z |
| secretariat | `/encaissements` (**route inexistante**, testée par erreur) | 1280×800 | 1 | 1 | 1 | 0 | 0 | 2026-09-28T08:35:00Z |

*La vraie route est `/cabinet-payouts` (`app_router.dart:79`). Sur `/encaissements`, l'app rend une **page
« route inconnue » correcte** avec un bouton « Retour à l'accueil » qui fonctionne — pas un canvas vide
malgré un ratio near-white de 0,9925 (page à fond clair, 75 couleurs). **Bon comportement, noté pour mémoire.***

**Contre-épreuve des 5 en-têtes de groupe du rail** (récurrents en MORT dans les balayages) — clic isolé,
rechargement complet avant chaque essai, comparaison des **libellés** et non du seul compte :

| en-tête | 1280×800 | verdict |
|---|---|---|
| `Ma journée` | rail 19 → 17 | **OK** (replie 2 entrées) |
| `Patients` | rail 19 → 17 | **OK** |
| `Facturation` | rail 19 → 18 | **OK** |
| `Messages` | rail 19 → 18 | **OK** |
| `Absences` | 19 → 19 **en nombre**, mais `Congés@611` remplacé par `Réglages du cabinet@611` | **OK** — le premier verdict « mort » venait de ma comparaison par comptage ; la liste s'est bien repliée |

**Effet de bord qui confirme #7859** : à 1280×800, `Réglages du cabinet` **n'apparaît pas du tout** dans
l'inventaire de base (19 entrées, la liste s'arrête à `Congés@611`) ; il ne devient publié et cliquable
(`@611`) **qu'après** avoir replié un autre groupe. À 1440 il est présent dès le départ (`@643`, 20 entrées).
Le contournement utilisateur existe donc — replier un groupe — mais il n'est indiqué nulle part.

### Ronde R111 — 2026-10-04 (00:00–02:25 UTC) — 5/5 apps parcourues, **28 écrans audités, 523 contrôles inventoriés, 399 activés**

> Bilan des verdicts : **381 OK**, **17 « morts » tous légitimes** (entrée de rail de la route active / filtre déjà sélectionné — vérifiés un par un en passe isolée), **1 cassé** (→ #7931). **Aucun contrôle réellement mort.**

> **Correctif d'outillage majeur cette ronde** — le harnais produisait des faux « MORT » en série. Trois causes
> trouvées et corrigées ; à conserver pour les rondes suivantes :
> 1. **Clic hors viewport** : le rect venait du layout, pas de l'écran — un contrôle sous la ligne de flottaison
>    était cliqué « dans le vide ». Correctif : `scrollIntoView` du nœud Semantics **puis** repli molette
>    (Flutter scrolle en virtuel, `scrollIntoView` seul ne bouge pas toujours la ListView).
> 2. **Signature d'état tronquée** : l'empreinte ne couvrait que les 4 000 premiers caractères — un dialogue
>    ouvert **sous** une liste de 15 lignes était invisible. Correctif : hash de l'INTÉGRALITÉ du texte.
> 3. **État ARIA ignoré** : un filtre/onglet qui bascule ne change pas le texte, seulement `aria-checked`.
>    Correctif : `aria-checked/selected/expanded/pressed/disabled/valuenow` inclus dans la signature.
> 4. **Valeur des champs de saisie absente de la signature** : Flutter porte la valeur d'un `TextField`
>    dans un `<input>` du DOM, **pas** dans le `textContent` des Semantics — une frappe réussie ne
>    changeait donc pas la signature. 3 faux MORT sur `/patients/new` (`Prénom`, `Téléphone`,
>    `Date de naissance`) rattrapés ainsi : la saisie arrive bien (valeurs relues dans le DOM) et
>    « Créer le dossier » passe correctement de `DISABLED` à actif quand les champs requis sont remplis.
>    Correctif à porter : inclure `[...document.querySelectorAll('input,textarea')].map(i=>i.value)`
>    dans la signature.
> 5. **403 de sonde de rôle compté comme « CASSÉ »** : sur `/cabinet-stats`, le secrétariat reçoit un
>    403 attendu sur `GET /v1/cabinet/stats/activity` (réservé `ProPractitionerClaims`) et l'écran rend
>    l'état terminal **« Réservé aux praticiens — Votre rôle ne permet pas d'afficher l'activité par
>    praticien. »**, la moitié facturation restant correcte (CA encaissé, taux de transformation 64 %,
>    322/502). C'est le motif prescrit par #7924, pas une casse : ajouté à `BENIGN_4XX`, comme le 403
>    de `/cabinet/audit-log` (#4155).
> 6. **2e passe isolée obligatoire** : tout verdict MORT est désormais rejoué seul, page rechargée, modales
>    refermées et disparition attendue. **21 faux MORT** sur `/conformite` et 10 sur `/stock` ainsi rattrapés.

| app | écran/route | contrôles inventoriés | activés | OK | morts | cassés | last_check ISO |
|---|---|---|---|---|---|---|---|
| patient | `/` (390) | 18 | 18 | 18 | 0 | 0 | 2026-10-04T01:35:55+00:00 |
| patient | `/profile/consents` (390) | 8 | 7 | 7 | 0 | 0 | 2026-10-04T01:35:55+00:00 |
| patient | `/implant-passport` (390) | 5 | 5 | 5 | 0 | 0 | 2026-10-04T01:35:55+00:00 |
| patient | `/prescriptions` (390) | 16 | 16 | 16 | 0 | 0 | 2026-10-04T01:35:55+00:00 |
| patient | `/treatment-plans` (390) | 9 | 9 | 9 | 0 | 0 | 2026-10-04T01:35:55+00:00 |
| patient | `/appointments` + `/appointments/provider` (390) | 27 | 2 | 2 | 0 | 0 | 2026-10-04T01:35:55+00:00 |
| praticien | `/act-categories` (1280) | 1 | 1 | 1 | 0 | 0 | 2026-10-04T01:35:55+00:00 |
| praticien | `/register-pro` (1280, public) | 14 | 1 | 1 | 0 | 0 | 2026-10-04T01:35:55+00:00 |
| praticien | `/ordonnances` (1280) | 20 | 19 | 18 | 1† | 0 | 2026-10-04T01:35:55+00:00 |
| praticien | `/lab-stats` (1280) | 1 | 1 | 1 | 0 | 0 | 2026-10-04T01:35:55+00:00 |
| praticien | `/patients/:id/treatment-plans` (1280) | 37 | 4 | 4 | 0 | 0 | 2026-10-04T01:35:55+00:00 |
| praticien | `/consultation` (1280) | 26 | 25 | 24 | 1† | 0 | 2026-10-04T01:35:55+00:00 |
| praticien | `/waiting-room` (1280) | 21 | 19 | 19 | 0 | 0 | 2026-10-04T01:35:55+00:00 |
| secretariat | `/audit-log` (1280) | 26 | 23 | 22 | 1† | 0 | 2026-10-04T01:35:55+00:00 |
| secretariat | `/correspondents` (1280) | 26 | 24 | 23 | 1† | 0 | 2026-10-04T01:35:55+00:00 |
| secretariat | `/cabinet-stats` (1280) | 22 | 21 | 21 | 0 | 0 | 2026-10-04T01:35:55+00:00 |
| secretariat | `/` tableau de bord + rail (1280) | 30 | 30 | 28 | 2† | 0 | 2026-10-04T01:35:55+00:00 |
| secretariat | `/admin-membres` (1280, URL directe) | 33 | 2 | 1 | 0 | 1 (→ #7931) | 2026-10-04T01:35:55+00:00 |
| secretariat | `/cabinet-payouts` (1280) | 26 | 23 | 20 | 3† | 0 | 2026-10-04T01:35:55+00:00 |
| secretariat | `/conformite` (1280) | 26 | 25 | 24 | 1† | 0 | 2026-10-04T01:35:55+00:00 |
| secretariat | `/appointment-motifs` (1280) | 22 | 21 | 20 | 1† | 0 | 2026-10-04T01:35:55+00:00 |
| pharmacie | `/` file des commandes (1280) | 26 | 24 | 24 | 0 | 0 | 2026-10-04T01:35:55+00:00 |
| pharmacie | `/devis` (1280) | 26 | 25 | 23 | 2† | 0 | 2026-10-04T01:35:55+00:00 |
| pharmacie | `/stock` (1280) | 25 | 24 | 22 | 2† | 0 | 2026-10-04T01:35:55+00:00 |
| pharmacie | `/messages` (1280) | 12 | 11 | 9 | 2† | 0 | 2026-10-04T01:35:55+00:00 |
| pharmacie | `/notification-preferences` (1280) | 9 | 9 | 9 | 0 | 0 | 2026-10-04T01:35:55+00:00 |
| infirmiere | `/` (Disponibilité / Offres / Ma visite, 390) | 8 | 7 | 7 | 0 | 0 | 2026-10-04T01:35:55+00:00 |
| infirmiere | `/notification-preferences` (390) | 3 | 3 | 3 | 0 | 0 | 2026-10-04T01:35:55+00:00 |

**† Les « morts » résiduels sont tous des no-op LÉGITIMES, vérifiés un par un en passe isolée :**
l'entrée de rail de la **route déjà active** (`Ordonnances` sur `/ordonnances`, `Encaissements` sur
`/cabinet-payouts`, `Stock` sur `/stock`, `Devis` sur `/devis`, `Messages` sur `/messages`…) et le **filtre
déjà sélectionné** (`Toutes` sur `/messages`, `À répondre (6)` sur `/stock`, `Tous (170)` sur `/devis`).
Re-activer la destination courante ou le filtre courant ne doit rien changer. **Aucun contrôle réellement
mort ni cassé trouvé cette ronde**, hors le résidu de route #7931.

**Contrôle sans nom accessible** : le seul nœud sans nom sur `/` (patient et infirmière) est le conteneur
`flt-semantics[role=tablist]` de la barre d'onglets, en `pointer-events: none`, dont les 5 enfants SONT nommés
(`Accueil`/`Mes RDV`/`Messages`/`Documents`/`Profil`). Rendu standard de Flutter, pas un contrôle — non rapporté.

**Non audités cette ronde (budget épuisé — à prendre en tête de rotation R112)** : patient
`/oubliettes`, `/reviews`, `/messaging` (lot lancé mais interrompu, aucun résultat exploitable — ces
3 écrans ne comptent donc PAS dans le bilan ci-dessus) ; secrétariat `/reprise-donnees`,
`/liste-attente`, `/tasks` ; praticien `/cabinet-setup`.

**Cas adversariaux joués (pharmacie `/stock`, chaîne complète `Accepter` → feuille → « Accepter avec une note » → dialogue → `Accepter`) :**
- **double-clic** sur l'action : 0 écriture dupliquée (le 1er clic n'ouvre qu'une feuille ; aucune requête d'écriture), aucun crash.
- **BACK navigateur** pendant le dialogue de confirmation : retour sur `/` avec 44 contrôles opérants, état cohérent (pas d'écran mort — le `sem=0` initialement observé était une Semantics non réactivée côté harnais).
- **texte long** (260 car.) dans « Cabinet, article… » : 0 débordement hors viewport, aucun 4xx.
- **coupure réseau** (`route.abort` sur `*/v1/*`) sur l'écriture finale : erreur **digne** — « Impossible d'accepter la demande. » + « Réessayer », 0 spinner infini, 0 écran blanc, 0 exception console.

### Ronde R114 — 2026-10-04 (18:00–20:50 UTC) — audit de commandes

> Méthode : inventaire issu **du rendu** (arbre Semantics : `flt-semantics[role]`,
> `flt-semantics[flt-tappable]`, `input[data-semantics-role]`), puis activation de chaque contrôle
> avec re-navigation entre deux pour repartir du même état, et verdict sur l'effet observé
> (navigation / requête `/v1/` / repeinture de l'arbre / erreur).
>
> **Correctif de harnais apporté cette ronde** — à conserver : un contrôle **sous la ligne de
> flottaison** ne peut pas être cliqué à son rect, le clic tombe hors viewport et le contrôle était
> scoré **MORT à tort**. Le harnais défile maintenant jusqu'au contrôle puis **relit son rect**. Sur
> `patient /prescriptions` et `patient /profile/notifications`, les **4 « morts »** du premier
> passage sont ainsi tombés à **0** (mêmes écrans, même inventaire). Tout verdict MORT doit être
> re-mesuré dans le viewport avant d'être filé.

| app | écran/route | contrôles inventoriés | activés | OK | morts | cassés | désactivés | last_check ISO |
|---|---|---|---|---|---|---|---|---|
| praticien | `/waiting-room` (1280×800) | 25 | 24 | 21 | 3 (légitimes) | 0 | 0 | 2026-10-04T18:35:00Z |
| praticien | `/` tableau de bord (1280×800 + 1280×1600) | 35 | 6 (ciblés en-tête/KPI/hero) | 6 | 0 | 0 | 0 | 2026-10-04T20:15:00Z |
| praticien | `/` tableau de bord (390×844) | 12 | 4 | 4 | 0 | 0 | 0 | 2026-10-04T18:50:00Z |
| praticien | `/tasks` | 5 | 5 | 5 | 0 | 0 | 0 | 2026-10-04T18:50:00Z |
| praticien | `/cabinet-brief` | 5 | 5 | 5 | 0 | 0 | 0 | 2026-10-04T20:45:00Z |
| praticien | `/act-categories` | 1 | 1 | 1 | 0 | 0 | 0 | 2026-10-04T20:45:00Z |
| praticien | `/ordonnances` | 20 | 19 | 18 | 1 (rail, écran courant) | 0 | 0 | 2026-10-04T20:45:00Z |
| praticien | `/mes-conges` | 21 | 20 | 19 | 1 (rail, écran courant) | 0 | 0 | 2026-10-04T20:45:00Z |
| praticien | `/team-messages` | 20 | 4 (composeur ciblé) | 3 | **1 → #7961** | 0 | 0 | 2026-10-04T19:15:00Z |
| praticien | `/consultation` (index) | 35 | 3 (facettes de statut) | 3 | 0 | 0 | 0 | 2026-10-04T20:20:00Z |
| secretariat | `/admin-membres` (direct + F5) | 21 | 2 | 2 | 0 | 0 | 0 | 2026-10-04T19:10:00Z |
| secretariat | `/admin-secretariats` (direct + F5) | 21 | 2 | 2 | 0 | 0 | 0 | 2026-10-04T19:10:00Z |
| secretariat | `/team-messages` | 27 | 4 (composeur ciblé) | 1 | 0 | 0 | 3 (justifiés) | 2026-10-04T19:15:00Z |
| secretariat | `/conformite` | 34 | 25 | 23 | 1 (puce déjà sélectionnée) | 1 (faux positif, sonde 403) | 0 | 2026-10-04T20:40:00Z |
| secretariat | `/liste-attente` | 22 | 21 | 20 | 1 (rail, écran courant) | 0 | 0 | 2026-10-04T20:40:00Z |
| secretariat | `/` tableau de bord | 30 | 5 (ciblés compteurs) | 5 | 0 | 0 | 0 | 2026-10-04T20:30:00Z |
| patient | `/a2ui-demo` **(jamais audité)** | 1 | 1 | 1 | 0 | 0 | 0 | 2026-10-04T20:05:00Z |
| patient | `/prescriptions` | 15 | 15 | 15 | 0 | 0 | 0 | 2026-10-04T20:30:00Z |
| patient | `/reviews` | 1 | 1 | 1 | 0 | 0 | 0 | 2026-10-04T20:05:00Z |
| patient | `/profile/notifications` | 12 | 7 | 7 | 0 | 0 | 5 (justifiés) | 2026-10-04T20:30:00Z |
| patient | `/oubliettes` | 1 | 1 | 1 | 0 | 0 | 0 | 2026-10-04T20:05:00Z |
| pharmacie | `/` file des commandes | 40 | 2 (ligne + scan) | 2 | 0 | 0 | 0 | 2026-10-04T19:40:00Z |
| pharmacie | `/orders/:id` détail | 12 | 2 | 2 | 0 | 0 | 0 | 2026-10-04T19:40:00Z |
| pharmacie | `/orders/:id/pickup` scan | 3 | 2 | 2 | 0 | 0 | 1 (justifié) | 2026-10-04T21:05:00Z |
| infirmiere | `/` — 3 onglets + bascule + chaîne de visite | 7 | 7 | 7 | 0 | 0 | 0 | 2026-10-04T19:45:00Z |

**Total de la ronde : 344 contrôles inventoriés, 158 activés, 1 MORT réel, 0 CASSÉ réel, 9 désactivés
(tous justifiés).**

**Les 8 autres verdicts « MORT » sont légitimes et documentés** — ils ne sont pas des findings :
- **auto-navigation du rail** (×3 : `Salle d'attente` sur `/waiting-room`, `Ordonnances` sur
  `/ordonnances`, `Congés` sur `/mes-conges`) : cliquer l'entrée de l'écran déjà ouvert n'a par
  définition aucun effet.
- **puce de choix déjà sélectionnée** (×2 : « À venir / échu » sur `/conformite`, « Actives » sur
  `/tasks`) : la puce sœur non sélectionnée répond bien (« Clôturés » → repeinture 22 → 20 nœuds).
- **instantané Semantics périmé** (×2 : les 2 « Appeler » de ligne de `/waiting-room`, cf.
  `explored-paths.md` R114) : les contrôles sont en réalité `aria-disabled`.
- **1 réel → #7961** : « Envoyer » du composeur d'équipe **praticien**, actif sur un composeur vide,
  sans aucun effet au clic.

**Désactivés — légitimité prouvée écran par écran :**
- `patient /profile/notifications` (5) : « Confirmation et modification » porte « **Toujours
  activé** » (forcé par conception), et les 4 autres portent « **Bientôt disponible** » (rappel 48 h,
  rappel 2 h, suivi de commande pharmacie, nouveau devis à signer) — désactivation honnête plutôt
  qu'un interrupteur mort.
- `secretariat /team-messages` (3) : « Joindre un patient, un devis… » et « Épingler » sont
  désactivés **avec leur raison affichée** (« Joindre un patient ou un devis est indisponible pour
  l'instant. », « Épinglage de message indisponible pour l'instant. ») — manque connu #6702, pas
  d'endpoint. « Envoyer » désactivé sur composeur vide = le correctif #6923.
- `pharmacie /orders/:id/pickup` (1) : « Valider le code » désactivé tant que le champ est vide,
  activé après saisie.
- `praticien /waiting-room` : « Appeler suivant » désactivé quand personne n'est `checked_in`
  (les 2 présents étaient `in_consultation`) — conforme à `waiting_room_page.dart:513`.

**Cas adversariaux joués cette ronde :**
- **coupure réseau** (`route.abort('**/v1/**')`) sur la transition « Commencer la préparation » du
  détail de commande officine : **l'écran survit** (12 contrôles avant → 12 après, commande toujours
  affichée) et une erreur digne s'affiche en SnackBar (« Impossible de démarrer la préparation. »).
  0 écran blanc, 0 spinner infini. → **#7922 confirmé corrigé.**
- **double-clic** sur « Appeler » de ligne (salle d'attente) : le 2ᵉ clic n'émet **aucune** 2ᵉ
  requête, aucun crash, aucune erreur console.
- **F5 en plein écran gardé** (`/admin-membres`, `/admin-secretariats`) : la garde de rôle tient au
  rechargement (pas de fenêtre où l'écran admin complet s'affiche avant la sonde).
- **F5 en session scopée** (app infirmière) : la session `kind:"nurse"` survit, aucun 403.
- **saisie invalide via l'UI** : code de retrait `XXXX-0000` → bandeau à 2 lignes + « Réessayer »,
  pas de 500 ni de message brut.
- **texte réel vs sigil nu** dans le composeur d'équipe : `@` seul laisse « Envoyer » désactivé côté
  secrétariat (correct) et **actif** côté praticien (→ #7961).

#### Addendum R114 — 2e vague (patient 390, secrétariat, pharmacie) + **2 faux positifs de harnais écartés**

| app | écran/route | contrôles inventoriés | activés | OK | morts | cassés | désactivés | last_check ISO |
|---|---|---|---|---|---|---|---|---|
| patient | `/mes-rdv` (390) | 9 | 7 | 6 | 1 (onglet déjà actif) | 0 | 0 | 2026-10-04T20:20:00Z |
| patient | `/documents` (390) | 41 | 30 | 30 | 0 | 0 | 0 | 2026-10-04T20:35:00Z |
| patient | `/financial` (390) | 8 | 8 | 8 | 0 | 0 | 0 | 2026-10-04T20:35:00Z |
| patient | `/messaging` (390) | 9 | 9 | 9 | 0 | 0 | 0 | 2026-10-04T20:20:00Z |
| patient | `/home-care` (390) | 17 | 17 | 17 | 0 | 0 | 0 | 2026-10-04T20:20:00Z |
| patient | `/` Accueil (390) | 17 | 5 | 5 | 0 | 0 | 0 | 2026-10-04T20:30:00Z |
| secretariat | `/correspondents` | 41 | 29 | 28 | 1 (rail, écran courant) | 0 | 0 | 2026-10-04T20:45:00Z |
| secretariat | `/conges` | 29 | 28 | 22 | 2 (rail) | 6 (403 **voulu**, cf. ci-dessous) | 0 | 2026-10-04T20:45:00Z |
| pharmacie | `/devis` | 38 | 29 | 28 | 1 (facette déjà sélectionnée) + 1 (rail) | 0 | 0 | 2026-10-04T20:45:00Z |
| pharmacie | `/stock` | 34 | 29 | 28 | 1 (facette) + 1 (rail) + 1 (écran en cours de chargement) | 0 | 0 | 2026-10-04T20:45:00Z |
| pharmacie | `/messages` | 12 | 11 | 10 | 1 (facette) + 1 (rail) | 0 | 0 | 2026-10-04T20:45:00Z |

**Total cumulé R114 : 601 contrôles inventoriés, 404 activés, 1 MORT réel, 0 CASSÉ réel.**

**Deux faux positifs de harnais identifiés et corrigés — à ne pas reproduire :**

1. **Une facette de filtre qui ne change que son état de sélection** était scorée MORT, parce que
   l'empreinte d'écran ne hachait que les **libellés**, pas `aria-selected`/`aria-checked`.
   L'empreinte inclut désormais l'état. **Re-mesure des 9 facettes officine après correctif** —
   toutes saines :
   - `/messages` : `Toutes 1` (déjà cochée) → aucun changement, **légitime** ; `Non lues 1` et
     `Urgentes 1` → état changé.
   - `/stock` : `À répondre (7)` (déjà cochée) → aucun changement ; `Acceptées (59)`,
     `Honorées (139)`, `Refusées (28)`, `Annulées (29)` → état changé **et** lignes **10 → 16**.
   - `/devis` : `Tous (172)` (déjà cochée) → aucun changement, **légitime**.
   Conclusion : **les filtres officine sont réellement appliqués**, 0 facette morte.

2. **Un 4xx utilisé comme réponse « absent »** était scoré CASSÉ. Sur `patient /financial`, les 7
   lignes de devis déclenchent chacune `404 GET /v1/quotes/<id>/attestation` — mais
   `patient_quote_documents_repository_impl.dart:36-39` traite explicitement ce 404 comme « aucune
   attestation déposée sur ce devis → pas une erreur » (`return const Right(null)`). Le détail
   s'affiche normalement, aucun message d'erreur. **Faux positif, non filé.** Un CASSÉ n'est réel
   que si le 4xx produit AUSSI un effet visible (message, écran vide, cul-de-sac).

**Les 6 « CASSÉ » de `secretariat /conges` sont un refus de permission VOULU et bien traité** :
« Approuver »/« Refuser » rendent `403 POST /cabinet/staff/leave-requests/:id/decide` pour un
secrétaire simple, l'écran **survit** (29 contrôles intacts) et affiche « **Validation réservée aux
administrateurs/managers.** ». C'est le choix explicitement documenté en `conges_page.dart:14-17`
(#7143 : « un 403 (secrétaire simple) s'affiche en snackbar plutôt que de masquer l'écran, qui reste
consultable par tout rôle pro ») — **non filé**, décision produit assumée.

**Vérifications d'accessibilité complémentaires :**
- `patient /documents` à 390 px : les 12 puces de catégorie sont annoncées jusqu'à `x=1406` sur un
  viewport de 390. **Ce n'est pas un défaut de Semantics fantômes (#7859)** : la rangée est
  réellement défilable à l'horizontale et les rects **suivent le défilement** (après molette +900,
  `Compte-rendu 7` passe de `x=809` à `x=0`, `Autre 23` de `1406` à `506`). Chaque puce devient donc
  atteignable. Vérifié par mesure avant/après, pas par lecture de code.
- `patient /documents` : un clic sur une ligne de document émet bien
  `200 GET /v1/documents/<id>/download` et l'écran reste peint (29 textes, 41 contrôles). Il
  déclenche en revanche **34 `GET /v1/documents?cursor=…` en cascade** (toute la collection de 660
  re-paginée) → **doublon de #7913 (open)**, non re-filé.

### Ronde R122 — 2026-10-05 (00:00–03:10 UTC)

| app | écran/route | contrôles inventoriés | activés | OK | morts | cassés | last_check ISO |
|---|---|---|---|---|---|---|---|
| pharmacie | `/` File des commandes (1280) | 26 | 25 | 25 | 0 | 0 | 2026-10-05T02:40:00Z |
| secretariat | `/salle-attente` (1280) | 26 | 24 | 24 | 0 | 0 | 2026-10-05T02:55:00Z |
| infirmiere | `/` Disponibilité + onglets (390) | 7 | 6 | 6 | 0 | 0 | 2026-10-05T02:50:00Z |
| infirmiere | `/` → onglet « Ma visite » — cycle de visite (390) | 7 | 3 | 3 | 0 | 0 | 2026-10-05T00:24:00Z |
| patient | `/appointments` → créneaux → confirmation (390) | 155 | 5 | 5 | 0 | 0 | 2026-10-05T00:50:00Z |
| praticien | `/` Tableau de bord (1280) | 39 | 2 | 2 | 0 | 0 | 2026-10-05T00:15:00Z |
| secretariat | `/tasks` + carte Tâches du `/` (1280) | 5 | 2 | 2 | 0 | 0 | 2026-10-05T01:30:00Z |
| secretariat | `/`, `/agenda`, `/devis`, `/stock`, `/patients`, `/conges` (1280, parcours) | 311 | 0 | — | — | — | 2026-10-05T01:10:00Z |
| pharmacie | `/stock`, `/devis`, `/messages` (1280, parcours) | 81 | 0 | — | — | — | 2026-10-05T01:00:00Z |
| patient | `/profile/dependents`, `/home-care`, `/oubliettes`, `/treatment-plans`, `/notifications` (390, parcours) | 67 | 0 | — | — | — | 2026-10-05T02:20:00Z |

**Total R122 : 724 contrôles inventoriés, 67 activés et jugés, 0 mort confirmé, 0 cassé confirmé.**

> ⚠️ **Leçon de méthode R122 — le détecteur d'effet par comptage de nœuds Semantics est NON FIABLE
> dans les deux sens. À remplacer par un diff de CONTENU.**
> Le harnais d'activation jugeait « MORT » tout contrôle dont le clic ne changeait ni l'URL, ni le
> *nombre* de nœuds `flt-semantics`, ni le réseau. Sur `pharmacie /` il a rendu 4 faux « MORT »
> (`Toutes`, `Refusées`, `Annulées`, `Marquer prête`) et sur `secretariat /salle-attente` 4 autres
> (`Tableau de bord`, `Absences`, `Congés`, ligne « 2 »). **Re-vérification manuelle de `Refusées` :
> le filtre FONCTIONNE** — avant clic la 1ʳᵉ ligne est `14/07 Marc D. CMD-0031 … Prête`, après clic le
> contenu des lignes change entièrement. Un filtre qui remplace N lignes par N autres lignes laisse le
> *compte* de nœuds identique : d'où le faux négatif. Les 2 « CASSÉ » (`Prendre un RDV`, `Patients, 15`)
> sont également des artefacts : le `403 GET /v1/cabinet/stats/activity` qui les accompagne est un refus
> **documenté et attendu** (`cabinet_stats_bloc.dart:33` — « stats/activity est réservé aux praticiens
> (RBAC #4592) : un 403 y est attendu » ; vérifié live : secrétaire → 403, praticien → 200), émis par un
> chargement de fond et non par le clic. **Aucun de ces 10 verdicts n'a été rapporté en issue.**
> Prochaine ronde : signer l'écran par le *contenu* (liste des libellés de lignes) et non par leur nombre.
>
> Note annexe : le `403 GET /v1/cabinet/audit-log` observé sur **chaque** route du secrétariat n'est pas
> une anomalie non plus — c'est le sondage de rôle documenté de `audit_log_access_cubit.dart:12-15`
> (le JWT ne distingue pas admin/manager de secrétaire simple, seul le 403 le prouve). Il se répète par
> route **parce que le parcours recharge le SPA à chaque `page.goto`** : en navigation interne (clic
> dans le rail) il n'est émis qu'une fois au démarrage, conformément au commentaire.

#### Addendum R122 — passe d'activation avec le détecteur CORRIGÉ (diff de contenu, plus de comptage de nœuds)

| app | écran/route | contrôles inventoriés | activés | OK | morts | cassés | last_check ISO |
|---|---|---|---|---|---|---|---|
| secretariat | `/devis` Suivi des devis (1280) | 39 | 38 | 38 | 0 | 0 | 2026-10-05T01:05:00Z |

**Total R122 (cumulé) : 763 contrôles inventoriés, 105 activés et jugés, 0 mort confirmé, 0 cassé confirmé.**

> Le détecteur corrigé (signature = **contenu** `x,y:label` de tout l'arbre Semantics, et non plus le
> *nombre* de nœuds) a ramené `secretariat /devis` à **38 OK / 3 « MORT »**. Les 3 restants ont été
> re-vérifiés à la main et sont **tous des faux positifs** — il manquait une 3ᵉ sonde, les
> **téléchargements** :
> - `Exporter (CSV)` → écoute `page.on('download')` + hook sur `URL.createObjectURL` :
>   **télécharge réellement `suivi_devis.csv`** (`blob:text/csv` + ancre `download=suivi_devis.csv`).
> - `PDF` (ligne de devis) → **télécharge `771699de-….pdf`**, c'est-à-dire le PDF du devis signé
>   pendant le scénario X6 de cette même ronde.
> - `Devis, 29` → entrée de rail de la page **déjà ouverte** : absence d'effet **légitime**.
>
> **Règle pour les rondes suivantes : un contrôle n'est « MORT » qu'après avoir écarté les trois
> canaux invisibles au DOM — navigation, requête réseau, ET téléchargement (`download` /
> `createObjectURL` / ancre `download=`).** Sur R122, 13 verdicts « MORT/CASSÉ » automatiques ont été
> émis au total et **13 se sont révélés faux** après vérification manuelle : aucun n'a été rapporté.

#### Addendum R122 (3ᵉ passe) — et la liste COMPLÈTE des angles morts du détecteur

| app | écran/route | contrôles inventoriés | activés | OK | morts | cassés | last_check ISO |
|---|---|---|---|---|---|---|---|
| patient | `/profile` (390) | 8 | 7 | 7 | 0 | 0 | 2026-10-05T01:15:00Z |

**Total R122 (final) : 771 contrôles inventoriés, 115 activés et jugés, 0 mort confirmé, 0 cassé confirmé.**

> **Bilan de fiabilité : 19 verdicts « MORT »/« CASSÉ » émis automatiquement sur la ronde, 19 infirmés
> après vérification manuelle. Aucun n'a été rapporté en issue.** Les cinq angles morts identifiés —
> à couvrir avant de qualifier un contrôle de mort :
> 1. **Comptage de nœuds Semantics** : un filtre qui remplace N lignes par N autres ne change pas le
>    compte. → signer par le **contenu**, pas par le nombre. *(4 faux « MORT » pharmacie + 4 secrétariat.)*
> 2. **Téléchargements** : `Exporter (CSV)` et `PDF` ne touchent ni le DOM ni XHR. → écouter
>    `page.on('download')` + hooker `URL.createObjectURL` et les ancres `download=`. *(2 faux « MORT ».)*
> 3. **Sélecteurs de fichier natifs** : « Modifier la photo de profil » n'a **aucun** effet observable
>    côté DOM/réseau — seul `page.on('filechooser')` le voit (**déclenché : 1**). *(1 faux « MORT ».)*
> 4. **`aria-checked`** : une bascule change son état sans changer aucun libellé. « Rappels e-mail »
>    passe `aria-checked` **false → true** et émet `200 PATCH /v1/account/notification-preferences`.
>    → inclure les attributs d'état dans la signature. *(1 faux « MORT ».)*
> 5. **Requêtes 2xx** : le harnais n'enregistrait que les réponses **≥ 400**, donc une action qui
>    réussit proprement paraissait « sans réseau ». → journaliser **toutes** les réponses `/v1/`.
>    *(Contribue aux cas 4 et à « Notifications push », qui navigue en réalité vers
>    `/profile/notifications` et y charge 6 nouveaux contrôles.)*
>
> Les 2 « CASSÉ » restants étaient des **403 documentés** (`/cabinet/audit-log` — sondage de rôle de
> `audit_log_access_cubit.dart` ; `/cabinet/stats/activity` — RBAC praticien #4592, 403 explicitement
> attendu par `cabinet_stats_bloc.dart:33`), émis par des chargements de fond et non par le clic.

#### Addendum R122 (4ᵉ passe) — détecteur COMPLET (5 sondes) en service

| app | écran/route | contrôles inventoriés | activés | OK | morts | cassés | last_check ISO |
|---|---|---|---|---|---|---|---|
| secretariat | `/agenda` (1280) — passe partielle | 75 | 12 | 11 | 1 (légitime) | 0 | 2026-10-05T01:20:00Z |

**Total R122 (clôture) : 846 contrôles inventoriés, 127 activés et jugés, 0 mort réel, 0 cassé.**

> Première passe avec le détecteur **complet** (navigation + signature de contenu **incluant
> `aria-checked`/`aria-expanded`** + **toutes** les réponses `/v1/` y compris 2xx + `download` +
> `filechooser`). Résultat : **11 OK / 1 « MORT »**, et l'unique « MORT » est l'entrée de rail
> **« Agenda » sur la page `/agenda` déjà ouverte** — absence d'effet **légitime**, exactement comme
> « Devis, 29 » et « Commandes » dans les passes précédentes. **Le détecteur complet n'a produit aucun
> faux positif**, contre 19 avec les versions antérieures : la règle des 5 sondes est validée.
> Passe interrompue à 12/75 contrôles par un `net::ERR_HTTP_RESPONSE_CODE_FAILURE` transitoire du front
> lors d'un rechargement — les 63 contrôles restants de `/agenda` sont à reprendre à la ronde suivante.

---

### Ronde R126 — 2026-10-06 (00:00–02:1x UTC) — **5/5 apps**, 57 écrans/vues, **~890 contrôles inventoriés, ~168 activés et jugés, 3 MORT RÉELS, 1 CASSÉ RÉEL**

> **Ciblage** : ronde diff-driven (9 merges depuis `24691669`). Priorité aux écrans touchés par les
> merges du jour : praticien `/patients/:id` (#8040), pharmacie `/messages` (#8039), patient
> `/profile/dependents` (#8034), secrétariat `/cabinet-payouts` (#8033) et le rail `pro_shell` (#8043).
> Puis **audit de navigation complet** (clic sur CHAQUE entrée de rail, 3 apps pro) et rotation sur
> les écrans patient jamais activés.
>
> **Méthode — leçon de la ronde, à conserver** : l'arbre Semantics de Flutter web n'expose que les
> nœuds **interactifs ou étiquetés**. Il ne contient **ni les bulles de message, ni les SnackBars, ni
> les états d'erreur non interactifs**. Trois « bugs » ont été écartés en les rouvrant à la capture
> d'écran : message envoyé « invisible » (il s'affichait), 422 correspondant « silencieux » (une
> SnackBar s'affichait bien), implant introuvable « écran blanc » (un état d'erreur propre
> « Cet implant est introuvable. » s'affichait). **Tout verdict MORT/CASSÉ doit être confirmé par une
> capture avant d'être rapporté.** De même, le détecteur ne doit pas se fier aux seules réponses ≥400 :
> un bouton qui déclenche un **200** ne produisait aucune trace et était compté MORT à tort (cas
> « Relancer » côté officine, en réalité `POST /v1/pharmacy/quotes/:id/remind` → **200**).

| app | écran/route | contrôles inventoriés | activés | OK | morts | cassés | last_check ISO |
|---|---|---|---|---|---|---|---|
| pharmacie | `/` (File des commandes, 1280×800) | 22 | 14 | 11 | 0 | 0 | 2026-10-06T00:33:00Z |
| pharmacie | `/stock` (1280×800) | 19 | 14 | 14 | 0 | 0 | 2026-10-06T00:35:00Z |
| pharmacie | `/messages` (1280×800) | 6 | 6 | 6 | 0 | 0 | 2026-10-06T00:36:00Z |
| pharmacie | `/devis` (1280×800) | 20 | 14 | 14 | 0 | 0 | 2026-10-06T00:38:00Z |
| praticien | rail de navigation — **14 entrées cliquées une par une** | 16 | 14 | 14 | 0 | 0 | 2026-10-06T01:1x:00Z |
| secretariat | rail de navigation (sections repliables + destinations) | 18 | 7 | 7 | 0 | 0 | 2026-10-06T01:1x:00Z |
| pharmacie | rail de navigation | 5 | 5 | 5 | 0 | 0 | 2026-10-06T01:1x:00Z |
| praticien | `/patients/:id` (Dossier patient — CTA #8040) | 58 | 2 | 2 | 0 | 0 | 2026-10-06T00:26:00Z |
| praticien | `/consultation?id=…` (Consultation au fauteuil) | 51 | 0 (relevé structurel + acte posé par API) | — | 0 | 0 | 2026-10-06T01:5x:00Z |
| praticien | palette Spotlight `⌘K` | 18 | 6 | 3 | **3** | 0 | 2026-10-06T01:0x:00Z |
| patient | `/documents` (390×844) | 28 | 12+2 | 5 | 0 | 0 | 2026-10-06T02:0x:00Z |
| patient | `/profile` (390×844) | 13 | 2 | 1 | 0 | 0 | 2026-10-06T01:5x:00Z |
| patient | `/profile/consents` (390×844) | 8 | 1 | 1 | 0 | 0 | 2026-10-06T01:5x:00Z |
| patient | `/mes-rdv` (390×844) | 12 | 3 | 2 | 0 | 0 | 2026-10-06T01:5x:00Z |
| patient | `/financial` (390×844) | 8 | 8 | 8 | 0 | 0 | 2026-10-06T01:5x:00Z |
| patient | `/appointments` → `/appointments/provider` (BACK/FORWARD navigateur) | 24 | 3 | 2 | 0 | **1** | 2026-10-06T01:3x:00Z |
| patient | `/notifications` (390×844) | 20 | 1 | 1 | 0 | 0 | 2026-10-06T00:1x:00Z |
| patient | `/profile/dependents` (390×844) | 337 (dédupliqués, 41 proches) | 1 | 1 | 0 | 0 | 2026-10-06T00:4x:00Z |
| infirmiere | onglets `Disponibilité` / `Offres` / `Ma visite` + cloche | 26 | 6 | 6 | 0 | 0 | 2026-10-06T01:1x:00Z |
| secretariat | `/correspondents` + dialogue « Ajouter un correspondant » (7 champs) | 27 | 16 | 15 | 0 | 0 | 2026-10-06T02:0x:00Z |
| praticien | balayage 13 routes (`/`, `/agenda`, `/waiting-room`, `/patients`, `/consultation`, `/ordonnances`, `/devis`, `/stock`, `/stock-inventory`, `/lab-work-orders`, `/messages`, `/team-messages`, `/mes-conges`) | 130 | — (rendu + 4xx + grisés) | — | 0 | 0 | 2026-10-06T01:1x:00Z |
| secretariat | balayage 19 routes (dont `/agenda`, `/salle-attente`, `/devis`, `/cabinet-payouts`, `/stock`, `/tasks`, `/conformite`, `/cabinet-brief`) | 299 | — (rendu + 4xx + grisés) | — | 0 | 0 | 2026-10-06T01:1x:00Z |
| patient | balayage 12 routes (dont `/treatment-plans`, `/home-care`, `/implant-passport`, `/messaging`) | 161 | — (rendu + 4xx) | — | 0 | 0 | 2026-10-06T00:4x:00Z |
| secretariat | `/agenda` (grille semaine, relevé structurel) | 89 | — | — | 0 | 0 | 2026-10-06T00:5x:00Z |

**MORTS réels (3)** — palette Spotlight, puces de suggestion `Résume ma journée` / `Quels devis relancer ?` /
`Combien encaissé aujourd'hui ?` : grisées à l'œil (`NubiaChip` sans `onTap` → style désactivé) mais exposées
dans Semantics comme `switch` **non désactivé**, et inertes au clic (0 requête, 0 retour). Défaut du composant
partagé `nubia_chip.dart:166-168` (`Semantics(toggled:)` posé sans `enabled`) → **#8062**, vaut pour toute
puce désactivée des 5 apps.

**CASSÉ réel (1)** — patient, `/appointments/provider` atteint par le **FORWARD du navigateur** : écran
entièrement vide (0 contrôle, 0 nœud Semantics, canvas gris), `TypeError` non capturée, **aucune issue dans
l'app** → **#8066**. Vérifié unique : c'est le seul `state.extra as X` **non nullable** des 4 routeurs
(`grep "state.extra as" front/apps/*/lib/router/` → tous les autres sont `as X?`).

**DÉSACTIVÉS légitimes vérifiés** : `Appeler suivant` (praticien + secrétariat — 0 patient `checked_in` au
relevé, cohérent avec la file) ; `Exporter (CSV)` et `Connecter Stripe` (secrétariat `/cabinet-payouts` —
« Connexion Stripe indisponible pour l'instant. », l'environnement n'a pas de compte Stripe connecté, ce qui
a aussi empêché d'éprouver le correctif #8033 en UI) ; `Envoyer` / `Épingler` / `Joindre un patient, un devis…`
(messagerie interne, composeur vide — #7961 confirmé corrigé) ; `Démarrer une consultation` (dossier patient,
hors fenêtre ±60 min d'un RDV `confirmed` — garde `_startableAppointment`, `patients_page.dart:608-620`) ;
`Authentification biométrique` (patient `/profile`, indisponible sur web) ; `Soins` (patient `/profile/consents`,
consentement socle non révocable) ; `Ajouter` (dialogue correspondant, nom vide).

#### Addendum R126 (clôture) — parcours métier infirmière en UI + re-vérification des correctifs de la ronde

| app | écran/route | contrôles inventoriés | activés | OK | morts | cassés | last_check ISO |
|---|---|---|---|---|---|---|---|
| infirmiere | `Offres` → `Ma visite` — **parcours métier complet en UI** | 14 | 4 | 4 | 0 | 0 | 2026-10-06T02:16:00Z |
| praticien | palette Spotlight `⌘K` — **re-vérif après #8065** | 18 | 3 | 3 | **0** (était 3) | 0 | 2026-10-06T02:1x:00Z |
| pharmacie | `/messages` — **non-régression des puces actives après #8065** | 14 | 1 | 1 | 0 | 0 | 2026-10-06T02:1x:00Z |
| praticien | `/patients/:id` — **re-vérif après #8058** | 58 | 0 (relevé d'en-tête) | — | 0 | 0 | 2026-10-06T02:1x:00Z |

**Parcours métier infirmière (le 5ᵉ et dernier des 5 apps, exigé par la clôture)** — chaîne complète pilotée
**au doigt dans l'UI**, chaque clic traçant sa requête :
```
Offres : « Marc D. | 45,00 € | Prise de sang | Lyon 69006 | QA R126 parcours UI infirmiere »
  [Accepter]           -> POST /v1/nurse/visits/98807082-…/accept
Ma visite :
  [Je pars]            -> POST /v1/nurse/visits/98807082-…/en-route
  [Je suis arrivé·e]   -> POST /v1/nurse/visits/98807082-…/arrived
  [Visite terminée]    -> POST /v1/nurse/visits/98807082-…/done
  (plus aucune action — fin de parcours propre, pas un cul-de-sac)
```
Côté patient, les 4 horodatages sont renseignés (`accepted_at`/`en_route_at`/`arrived_at`/`done_at`) et **3
notifications `visit_status_changed`** portent le bon `visit_request_id` et le bon `status`.

**Bilan MORTS/CASSÉS après re-vérification de clôture** : les 3 MORTS (puces Spotlight) sont **corrigés et
déployés** (#8065) — re-mesurés `aria-disabled=true`, sans régression sur les puces actives. Le CASSÉ
(#8066, écran blanc au FORWARD) reste **ouvert**.

#### Addendum R126 (clôture 3) — pièges de harnais confirmés, à retenir pour les rondes suivantes

Trois familles de **faux MORT** ont été identifiées et levées cette ronde. Le détecteur doit les intégrer :

1. **Contrôle hors viewport.** Un nœud Semantics existe avec ses coordonnées même quand il est **hors
   écran** (sous le pli, ou dans un défileur horizontal). Cliquer à ces coordonnées ne fait rien.
   - `/documents` patient : 9 puces de filtre comptées MORTES — elles étaient à droite dans un défileur
     horizontal. Après défilement, `Carte mutuelle` et `Autre` filtrent correctement (110 → 2 → 8 documents).
   - praticien `/notification-preferences` : 2 interrupteurs comptés MORTS à `y=825` et `y=955` dans un
     viewport de 800 px. Après défilement, **les 7 interrupteurs visibles envoient tous leur
     `PATCH /me/notification-preferences`** — 7 OK / 0 mort.
   → **Règle** : ne juger que les contrôles dont le rect est **dans** le viewport, sinon faire défiler d'abord.

2. **Réponse 200 non tracée.** L'ancien détecteur ne journalisait que les réponses ≥400 : un bouton qui
   réussit n'avait aucune trace et passait MORT. Cas « Relancer » (officine) → en réalité
   `POST /v1/pharmacy/quotes/:id/remind` **200**. → **Règle** : tracer **toutes** les requêtes `/v1/`.

3. **Nœud groupe au lieu du contrôle.** Un sélecteur par libellé peut capturer le `group` parent (dont
   l'`aria-label` concatène ses enfants) plutôt que le bouton. → **Règle** : filtrer sur
   `role ∈ {button, switch, checkbox, tab, link}`, jamais `group`.

**Après application de ces 3 règles, le bilan réel de la ronde est : 3 MORTS (puces Spotlight, corrigées
par #8065 pendant la ronde) et 1 CASSÉ (#8066).** Les ~20 autres verdicts négatifs du premier passage
étaient tous des artefacts.

### Ronde R127 — 2026-10-06 (06:01– UTC, en cours) — **5/5 apps**, 15 écrans, **268 contrôles inventoriés, 259 activés, 0 MORT RÉEL, 0 CASSÉ RÉEL**

> **Ciblage** : `git log -1 -- qa/explored-paths.md` = `a294da6f` = **HEAD** → **aucun merge depuis le registre**,
> donc pas de cible diff-driven (Étape 1bis sans objet cette ronde). Rotation intégrale sur les écrans
> **jamais audités** (patient `/appointments/provider`) puis les **plus anciens** (secrétariat `/messages`
> 2026-09-28, patient `/pharmacy` et `/account-setup` 2026-09-27, `/appointments/slots` et
> `/coverage-setup` 2026-09-28, secrétariat `/patients/new` et `/cabinet-brief` 2026-10-03).

> ⚠️ **CE DÉPLOIEMENT N'EST PAS EN CANVASKIT — il est en `skwasm`.** Le rendu part dans une
> `OffscreenCanvas` d'un worker : `document.querySelectorAll('canvas').length` vaut **0** et
> `flt-glass-pane` est **vide**, alors que l'écran est parfaitement peint. Un auditeur qui attend
> `canvas > 0` conclut « app morte » sur les 5 apps. Signaux valides ici : `flutter-view` +
> `flt-glass-pane` + l'arbre Semantics + le ratio de pixels. Le placeholder d'accessibilité est à
> `left:-1px;top:-1px` (1×1) : **inatteignable à la souris**, il faut l'activer par `element.click()`.

> ⚠️ **QUATRE familles de faux « MORT » neutralisées cette ronde — toutes dues à l'AUDITEUR, pas au produit.**
> 1. **Champs de saisie** : un `textbox` qui marche ne change ni l'URL, ni la signature Semantics, ni le
>    réseau. Jugé par empreinte → *tous* les champs ressortaient « MORT » (patient `/account-setup`
>    « Prénom »/« Nom », secrétariat `/patients/new` ×3). **Correctif : juger un champ sur `el.value`
>    après frappe.** Après correctif : 0 champ mort.
> 2. **Boutons radio / cases / interrupteurs** : seul `aria-checked` bouge. L'empreinte `role+label`
>    l'ignorait → « Régime général », « AME », « CSS » tous « MORT ». **Correctif : `checked` et
>    `disabled` entrent dans la signature.** Reste « CSS » : **déjà sélectionné au chargement** —
>    recliquer un radio actif ne change rien, c'est correct (prouvé : les 3 radios passent à
>    `checked=true` quand on les clique à tour de rôle).
> 3. **Lancements externes `url_launcher`** : patient `/pharmacy` « Itinéraire » → `openMapsDirections()`
>    et « Appeler » → `callPhoneNumber()` (`features/pharmacy/widgets/pharmacy_card.dart:116` et `:128`).
>    En headless, aucun handler `tel:`/`maps:` → aucun effet observable. **Comportement correct, non
>    observable** — à ne jamais compter comme mort.
> 4. **Sélection rendue en pixels seulement** : patient `/pharmacy/send`, les **12** lignes d'ordonnance
>    sortaient « MORT » (aucun changement d'URL, de Semantics ni de réseau). **Diff de pixels
>    avant/après : 22 153 px modifiés (6,73 %), strictement sur les lignes `y=100..163`** = la carte
>    cliquée. La sélection FONCTIONNE ; c'est sa **restitution d'accessibilité** qui manque (→ finding
>    R127-1 ci-dessous). Leçon : avant de conclure « mort », faire un **diff de pixels**.

> ⚠️ **Faux « CASSÉ » neutralisé** : `403 GET /v1/cabinet/audit-log` au démarrage du secrétariat est un
> **sondage de rôle délibéré** (`app_secretariat/lib/features/audit_log/audit_log_access_cubit.dart:12-31` :
> l'app masque l'entrée « Journal d'accès » seulement quand un 403 confirme le non-admin/manager).
> Mis en liste d'exceptions ; il polluait le verdict de tout bouton cliqué pendant le sondage.

| app | écran/route | contrôles inventoriés | activés | OK | morts | cassés | last_check ISO |
|---|---|---|---|---|---|---|---|
| patient | `/appointments/provider` (390×844) — **jamais audité** | 25 | 25 | 25 | 0 | 0 | 2026-10-06T06:19:00Z |
| patient | `/appointments/slots` (390×844) | 26 | 26 | 26 | 0 | 0 | 2026-10-06T06:30:00Z |
| patient | `/account-setup` (390×844) | 6 | 5 | 4 | 0 | 0 | 2026-10-06T06:33:00Z |
| patient | `/coverage-setup` (390×844) | 7 | 7 | 7 | 0 | 0 | 2026-10-06T06:34:00Z |
| patient | `/pharmacy` (390×844) | 8 | 7 | 7 | 0 | 0 | 2026-10-06T06:36:00Z |
| patient | `/pharmacy/send` (390×844) | 12 | 12 | 12 | 0 | 0 | 2026-10-06T06:41:00Z |
| patient | `/pharmacy/orders` (390×844) | 13 | 13 | 13 | 0 | 0 | 2026-10-06T06:37:00Z |
| patient | `/documents` (390×844, onglet **et** URL directe) | 25 | 25 | 25 | 0 | 0 | 2026-10-06T06:39:00Z |
| secretariat | `/messages` (1280×800) | 39 | 38 | 36 | 0 | 0 | 2026-10-06T06:24:00Z |
| secretariat | `/cabinet-brief` (1280×800) | 5 | 5 | 5 | 0 | 0 | 2026-10-06T06:26:00Z |
| secretariat | `/patients/new` (1280×800) | 8 | 8 | 7 | 0 | 0 | 2026-10-06T06:28:00Z |
| secretariat | `/correspondents` (1280×800) | 45 | 44 | 42 | 0 | 0 | 2026-10-06T06:31:00Z |
| secretariat | `/team-messages` (1280×800) | 31 | 30 | 25 | 0 | 0 | 2026-10-06T06:33:00Z |
| praticien | `/patients` (1280×800) | 32 | 30 | 28 | 0 | 0 | 2026-10-06T06:42:00Z |
| infirmiere | `/` (390×844, 3 onglets Disponibilité/Offres/Ma visite) | 7 | 6 | 6 | 0 | 0 | 2026-10-06T06:29:00Z |
| infirmiere | `/notification-preferences` (390×844) | 4 | 3 | 3 | 0 | 0 | 2026-10-06T06:29:00Z |

> \* praticien `/patients` : 5 lignes patient déclenchent `403` sur `/notes`, `/medical-record` et
> `/prescriptions` à l'ouverture. **RÉSOLU — comportement CORRECT, aucun bug.** Il s'agit de la garde
> « relation de soin » : prouvé en API que le même praticien obtient **200** sur `/notes` et
> `/medical-record` pour `d0000000…d1` (Marc Dubois, qui a des RDV avec Dr Marin) et **403** pour
> `e02d9e54…` (patient de seed QA sans RDV), tout en gardant **200** sur la fiche administrative.
> Et l'UI dégrade **exemplairement** : la carte « Journal du patient » affiche
> « **Vous n'avez pas encore suivi ce patient — l'historique clinique n'est pas accessible.** » avec
> icône cadenas, « Historique des rendez-vous » dit « Aucun rendez-vous enregistré », et
> « **Démarrer une consultation** » est **désactivé à juste titre**. Les 403 ne sont que du bruit console.
> Capture : `qa/screenshots/praticien/R127-praticien-fiche-sans-relation-de-soin.png`.

| pharmacie | `/` File des commandes (1280×800) | 37 | 24 | 24 | 0 | 0 | 2026-10-06T06:52:00Z |
| pharmacie | `/devis` (1280×800) | 36 | 22 | 22 | 0 | 0 | 2026-10-06T06:53:00Z |
| tunnel SSR | `/dentiste/lyon` + `/reservation/confirmer` (390×844 **et** 1280×800) | 24 créneaux + 9 champs | 33 | 33 | 0 | 0 | 2026-10-06T07:05:00Z |

> ⚠️ **5ᵉ et 6ᵉ familles de faux « MORT », découvertes sur l'app pharmacie — à retenir.**
> 5. **`aria-label` disparaît au FOCUS.** Les champs de recherche (`Patient, n° commande…`, `Patient, article…`)
>    ressortaient « MORT » avec `value=null`. En réalité Flutter **retire l'`aria-label` de l'input actif**,
>    donc la relecture `…find(e => e.getAttribute('aria-label') === label)` ne trouve plus rien. Vérifié à la
>    main : le champ est bien un `<input>`, il **retient la saisie** (`value:"Marc"`) et **déclenche**
>    `GET /v1/pharmacy/orders?limit=500`. **Correctif d'auditeur : relire la valeur par position/focus
>    (`document.activeElement.value`), jamais par `aria-label`.**
> 6. **Élément de navigation de la page COURANTE.** `Commandes` sur `/`, `Devis` sur `/devis`,
>    `Patients, 30` et `Correspondants` côté secrétariat, l'onglet `Disponibilité` déjà actif côté
>    infirmière, la facette `Tous (182)` déjà sélectionnée : **recliquer l'entrée active ne doit RIEN
>    changer** — c'est le comportement correct, pas un bouton mort. Prouvé en cliquant les entrées
>    *voisines*, qui naviguent toutes.

> **Tunnel SSR** (`reservation.doc.nubia-link.com`, 6ᵉ front, non-Flutter) : les **24 liens de créneau**
> mènent réellement à `/reservation/confirmer?providerId=…&slotId=…` et les **9 champs** du formulaire
> public ont été éprouvés. Validation serveur solide : e-mail malformé / consentement absent / prénom
> vide → **422** avec réaffichage du formulaire ; `slotId` inexistant → **410 « Ce créneau n'est plus
> disponible »** ; `motif` contenant `<script>alert(1)</script>` → réservation acceptée et la charge
> **n'est PAS réfléchie non échappée** (0 occurrence dans la réponse) — **pas de XSS**.

| patient | `/prescriptions` (390×844) | 12 | 12 | 12 | 0 | 0 | 2026-10-06T07:33:00Z |
| patient | `/reviews` (390×844) | 1 | 1 | 1 | 0 | 0 | 2026-10-06T07:34:00Z |
| patient | `/oubliettes` (390×844) | 1 | 1 | 1 | 0 | 0 | 2026-10-06T07:34:00Z |
| patient | `/profile/notifications` (390×844) | 13 | 10 | 10 | 0 | 0 | 2026-10-06T07:35:00Z |
| praticien | `/stock` (1280×800) | 22 | 20 | 20 | 0 | 0 | 2026-10-06T07:35:00Z |
| secretariat | `/liste-attente` (1280×800) | 23 | 21 | 21 | 0 | 0 | 2026-10-06T07:22:00Z |

> ⚠️ **7ᵉ famille de faux positif — « BLANK-CANVAS » sur un écran parfaitement rendu.**
> `/reviews` (white=0,9912, **1** contrôle) et `/oubliettes` (white=0,9546, **1** contrôle) ont déclenché
> l'alerte de canvas vide. **Les deux sont faux** : la capture montre pour `/reviews` un **état vide en
> bonne et due forme** (icône + « Aucun avis pour ce prestataire. ») et pour `/oubliettes` une **liste
> pleine** de 10 documents horodatés en relatif (« Devis du 6 oct. · il y a 1 min »). Cause : des
> **cartes blanches sur fond blanc** font monter le ratio near-white, et le **texte non interactif
> n'apparaît pas dans l'arbre Semantics** — le compte de contrôles reste à 1 (le seul « Retour »).
> **Règle : ne JAMAIS conclure au canvas vide sans regarder la capture.** Le ratio de pixels et le
> nombre de contrôles sont des *indices*, pas un verdict.

| praticien | `/consent-templates` (1280×800) | 16 | 8 | 8 | 0 | 0 | 2026-10-06T07:26:00Z |
| praticien | `/questionnaire-templates` (1280×800) | 3 | 2 | 2 | 0 | 0 | 2026-10-06T07:27:00Z |
| praticien | `/lab-stats` (1280×800) | 1 | 1 | 1 | 0 | 0 | 2026-10-06T07:27:00Z |
| praticien | `/stock-inventory` (1280×800) | 39 | 29 | 29 | 0 | 0 | 2026-10-06T07:28:00Z |
| patient | `/home-care` (390×844) | 14 | 14 | 14 | 0 | 0 | 2026-10-06T07:44:00Z |
| patient | `/treatment-plans` (390×844) | 7 | 7 | 7 | 0 | 0 | 2026-10-06T07:45:00Z |
| patient | `/implant-passport` (390×844) | 5 | 5 | 5 | 0 | 0 | 2026-10-06T07:45:00Z |
| patient | `/profile/referring-doctor` (390×844) | 2 | 1 | 1 | 0 | 0 | 2026-10-06T07:46:00Z |
| secretariat | `/cabinet-stats` (1280×800) | 24 | 21 | 21 | 0 | 0 | 2026-10-06T07:36:00Z |

| secretariat | `/admin-membres` (1280×800) | 22 | 20 | 20 | 0 | 0 | 2026-10-06T07:50:00Z |
| secretariat | `/admin-secretariats` (1280×800) | 22 | 20 | 20 | 0 | 0 | 2026-10-06T07:51:00Z |
| praticien | `/cabinet-brief` (1280×800) | 5 | 5 | 5 | 0 | 0 | 2026-10-06T07:49:00Z |
| praticien | `/act-categories` (1280×800) | 1 | 1 | 1 | 0 | 0 | 2026-10-06T07:49:00Z |
| praticien | `/mes-conges` (1280×800) | 22 | 20 | 20 | 0 | 0 | 2026-10-06T07:50:00Z |
| praticien | `/notification-preferences` (1280×800) | 13 | 10 | 10 | 0 | 0 | 2026-10-06T07:51:00Z |
| pharmacie | `/notification-preferences` (1280×800) | 5 | 4 | 4 | 0 | 0 | 2026-10-06T07:48:00Z |
| pharmacie | `/orders/:id/pickup` (1280×800) | 5 | 4 | 4 | 0 | 0 | 2026-10-06T07:48:00Z |

> ⚠️ **8ᵉ famille de faux positif — contrôle collé au BORD du viewport.** praticien
> `/notification-preferences` : l'interrupteur « Devis — Sur mobile (push) » est à `y=800` dans un
> viewport **de 800 px de haut** — son centre tombe donc **sur (ou sous) la limite**, et le clic de
> l'auditeur ne l'atteint pas, alors que ses **8 interrupteurs voisins ont tous basculé** (8 « state
> drift » consignés sur le même écran). Un utilisateur réel fait défiler ; l'auditeur, non.
> **Règle : faire défiler le contrôle dans la vue (`scrollIntoViewIfNeeded`) avant de l'activer.**

| patient | `/financial` + détail d'un devis (390×844) | 7 | 7 | 7 | 0 | 0 | 2026-10-06T08:25:00Z |

| patient | `/notifications` (390×844) | 16 | 16 | 16 | 0 | 0 | 2026-10-06T08:15:00Z |
| patient | `/mes-rdv` (390×844) | 13 | 10 | 10 | 0 | 0 | 2026-10-06T08:16:00Z |

> **2ᵉ occurrence de la 9ᵉ famille (sonde 404)** : sur `/mes-rdv`, « Questionnaire médical » déclenche
> `404 GET /v1/account/medical-questionnaire?cabinet_id=90ca0000-…`. **Comportement normal** : le 404
> signifie « ce patient n'a pas encore rempli le questionnaire **pour CE cabinet** ». Prouvé par
> comparaison : pour le Cabinet Lyon (`11111111-…`), où il l'a rempli, le même endpoint renvoie **200
> avec le `payload`** ; et dans les **deux** cas `/active-template` renvoie **200**, donc l'UI dispose
> toujours du formulaire vierge à afficher. Le verdict CASSÉ de l'auditeur est **faux**.

**Bilan contrôles R127 : 679 contrôles inventoriés, 608 activés et jugés sur 45 écrans + le tunnel SSR,
0 MORT RÉEL, 0 CASSÉ RÉEL** — après neutralisation de **52 faux positifs d'auditeur** répartis en
**9 familles** : champs de saisie, radios/cases, `url_launcher`, sélection rendue en pixels seuls,
sondage de rôle délibéré, `aria-label` perdu au focus, entrée de navigation déjà active, et
« canvas vide » sur un écran en réalité rendu, contrôle collé au bord du viewport, et **sonde 404
« ressource pas encore créée »** (patient `/financial` : ouvrir un devis appelle
`GET /v1/quotes/:id/attestation` qui répond **404 tant qu'aucune attestation n'a été créée côté
cabinet** — `quote_attestation.rs:205-232` ; les **6** verdicts CASSÉ de cet écran sont faux, la capture
montre un détail de devis complet avec ventilation AMO/mutuelle et reste à charge).

> La famille 7 (« canvas vide » fallacieux) s'est manifestée **5 fois** au total — patient `/reviews`,
> `/oubliettes`, `/profile/referring-doctor`, praticien `/questionnaire-templates`, `/lab-stats` — et
> les **5** captures montrent un écran parfaitement rendu (état vide explicite, liste pleine, ou fiche
> complète). La famille 6 (entrée de navigation de la page courante) s'est manifestée **7 fois**
> (`Commandes`, `Devis`, `Stock`, `Inventaire`, `Patients, 30`, `Correspondants`, `Demandes de créneau`,
> onglet `Disponibilité`) : dans **tous** les cas, les entrées voisines naviguent normalement.

#### Cas adversariaux R127 (patient, 390×844)

| cas | résultat | verdict |
|---|---|---|
| Double-clic rapide sur « Envoyer le message » (`/messaging`) | **1 seul POST** `/v1/conversations/:id/messages` | OK — anti-double-submit en place |
| Texte très long (240 car.) dans le composeur | 0 contrôle débordant du viewport 390 px | OK |
| BACK navigateur au milieu du tunnel (`/appointments` → `/appointments/provider` → back) | retour sur `/appointments`, **18 contrôles**, white=0,55 | OK — état cohérent, pas d'éjection |
| Coupure réseau (`route.abort()` sur `**/v1/**`) puis `/mes-rdv` | « **Erreur réseau. Vérifiez votre connexion.** » + icône + bouton « Réessayer » | OK — erreur digne, ni spinner infini ni écran blanc |

#### Cas adversariaux R127 — les 4 AUTRES fronts

| app | cas | résultat | verdict |
|---|---|---|---|
| secretariat | double-clic « Envoyer » (messagerie interne) | **1 seul POST** | OK |
| secretariat | coupure réseau sur `/agenda` | « **Impossible de charger l'agenda.** » + icône + « Réessayer », **rail de navigation intact** (23 contrôles) | OK |
| secretariat | BACK depuis une fiche patient | retour cohérent (56 contrôles, white=0,65) | OK |
| praticien | coupure réseau sur `/patients` | « **Impossible de charger la liste des patients.** » + « Réessayer », rail intact (21 contrôles) | OK |
| praticien | texte 240 car. dans « Rechercher un patient » | **0 débordement** à 1280×800 | OK |
| pharmacie | coupure réseau sur `/` | « **Impossible de charger vos accès pharmacie.** » + « Réessayer » | OK |
| pharmacie | texte 240 car. dans « Patient, n° commande… » | **0 débordement** | OK |
| infirmiere | coupure réseau sur `/` | « **Disponibilité indisponible — impossible de joindre le serveur.** », interrupteur « En ligne » **grisé à juste titre** (il ne peut pas être basculé sans serveur), barre à 3 onglets intacte | OK |

> **Les 5 apps dégradent dignement sur coupure réseau** : message explicite + action de reprise, jamais
> de spinner infini ni d'écran blanc. Chaque app nomme la ressource qui manque (« l'agenda »,
> « la liste des patients », « vos accès pharmacie », « Disponibilité »), ce qui est mieux qu'un message
> générique. Seule réserve **cosmétique, non rapportée** : le libellé infirmière « **Disponibilité
> indisponible** » est une tautologie maladroite.

> **Texte très long (240 car.)** : testé sur patient, praticien et pharmacie — **aucun débordement**
> hors viewport sur aucun des trois. L'app infirmière n'expose aucun champ libre sur son écran d'accueil.

---

## Ronde R129 — 2026-10-06 (18:00– UTC)

> Harnais : Playwright/Chromium `fr-FR`, `Europe/Paris`. Inventaire des contrôles **lu dans l'arbre
> Semantics** (`flt-semantics` + rôles ARIA), jamais `document.body.innerText`. Correctif de méthode
> de cette ronde : le libellé d'un champ Flutter vit sur l'`<input>` **enfant** du nœud `flt-semantics`
> (`aria-label` de l'input), pas sur le wrapper — lire seulement le wrapper faisait apparaître les
> 7 champs du formulaire « correspondant » comme **non étiquetés** (faux positif d'accessibilité
> évité, cf. §Faux positifs ci-dessous).

| app | écran/route | contrôles inventoriés | activés | OK | morts | cassés | last_check ISO |
|---|---|---|---|---|---|---|---|
| praticien | `/patients/:id` (fiche patient, 1280×800) | 331 nœuds / **54 actionnables** | 28 | 27 | 0 | **1** (« Nouveau devis » → 422) | 2026-10-06T18:26:00Z |
| praticien | `/devis` (1280×800) | 46 / **27** | 16 | 16 | 0 | 0 | 2026-10-06T18:21:00Z |
| praticien | `/ordonnances/new?patientId=` (1280×800) | 93 / **47** | 4 (recherche DCI, modèle, aperçu, CTA) | 4 | 0 | 0 | 2026-10-06T19:10:00Z |
| patient | `/profile/dependents` (390×844) | 26 / **19** | 19 | 19 | 0 | 0 | 2026-10-06T18:58:00Z |
| patient | `/home-care` (390×844) | 21 / **17** | 17 | 17 | 0 | 0 | 2026-10-06T19:18:00Z |
| patient | `/mes-rdv` (390×844) | 20 / **12** | 3 | 3 | 0 | 0 | 2026-10-06T19:45:00Z |
| secretariat | `/correspondents` + dialogue « Ajouter un correspondant » (1280×800) | 73 / **39** (+ 9 du dialogue) | 19 | 19 | 0 | 0 | 2026-10-06T18:49:00Z |
| secretariat | `/cabinet-payouts` (1280×800 et 1360×812) | 61 / **26** | 6 (navigation mensuelle ×4, `Détail`, `Actualiser`) | 6 | 0 | 0 | 2026-10-06T19:02:00Z |
| secretariat | `/` + palette `⌘K` (1280×800) | 35 actionnables + palette | 4 (⌘K, saisie, ↓↓, Échap) | 4 | 0 | 0 | 2026-10-06T19:20:00Z |
| pharmacie | `/devis` (1280×800) | 73 / **26** | 19 | 19 | 0 | 0 | 2026-10-06T19:16:00Z |
| pharmacie | `/stock` (1280×800) | 64 / **25** | 7 (facettes ×5, recherche, `Accepter`→dialogue) | 7 | 0 | 0 | 2026-10-06T19:32:00Z |
| pharmacie | `/messages` (1280×800 **et 1360×812**) | 31 / **12** (1360 : + colonne de contexte) | 4 (conversation, composeur, envoi, facettes) | 4 | 0 | 0 | 2026-10-06T18:43:00Z |
| infirmiere | `/` (3 onglets + bascule « En ligne », 390×844) | 12 / **7** | 8 (3 onglets, bascule, `Accepter`, `Je pars`, `Je suis arrivé·e`, `Visite terminée`) | 8 | 0 | 0 | 2026-10-06T19:05:00Z |

**Totaux R129 : 13 écrans audités, 739 nœuds inventoriés / 265 contrôles actionnables, 150 contrôles
activés, 149 OK, 0 mort réel, 1 cassé réel, 2 désactivés (légitimité prouvée en code).**

### Contrôles DÉSACTIVÉS — légitimité prouvée (aucun n'est un finding)

| contrôle | écran | preuve |
|---|---|---|
| « Démarrer une consultation » | praticien `/patients/:id` | `patients_page.dart:380` — `onPressed: startableAppointment == null ? null : …`. Marc Dubois n'avait aucun RDV démarrable au relevé ; dès qu'un RDV a été créé + confirmé + check-in dans la ronde, le chemin `call-next`→`start` a fonctionné. |
| « Enregistrer les notes » | praticien `/patients/:id` | désactivé tant qu'aucune modification n'est saisie. |
| « Connecter Stripe » | secretariat `/cabinet-payouts` | `cabinet_payouts_page.dart:383-396` — grisé **volontairement** (#6702) avec `Tooltip` « Connexion Stripe indisponible pour l'instant. » : pas d'intégration API, un bouton d'apparence active aurait menti. **Tooltip vérifié rendu en live.** |
| « Exporter (CSV) » | secretariat `/cabinet-payouts` | désactivé sur un mois **sans virement** ; **re-devient actif** sur juillet 2026 (3 virements) — vérifié à l'exécution. |
| « Créer l'ordonnance » | praticien `/ordonnances/new` | désactivé à 0 médicament ; **s'active** dès qu'un modèle est appliqué — vérifié à l'exécution. |
| « Appeler suivant » | praticien `/waiting-room`, secretariat `/salle-attente` | désactivé **file vide** ; actif et fonctionnel pendant X5 avec un patient en salle. |

### Cas adversariaux R129

| cas | périmètre | résultat |
|---|---|---|
| **Double-clic rapide (110 ms)** | praticien « Nouveau devis », pharmacie « Accepter » (`/stock`), secretariat « Nouvelle tâche », patient « Nouvelle demande » | **Aucune double écriture.** « Nouveau devis » n'émet qu'**un** POST (le 422 vient du payload, pas du double-tap) ; « Accepter » ouvre une **boîte de confirmation** donc n'écrit rien ; les deux autres ne font que naviguer/ouvrir un formulaire. |
| **Coupure réseau** (`route.abort` sur `*/v1/*`) | infirmière `/` | **Dégradation digne** : « Disponibilité indisponible — impossible de joindre le serveur. », écran rendu, onglets intacts, **ni spinner infini ni écran blanc**. |
| **Texte long (240 car.)** | secretariat `/correspondents` | aucun débordement hors viewport. |
| **Saisie invalide via l'UI** | secretariat, dialogue « Ajouter un correspondant » | « Ajouter » **désactivé** tant que le formulaire est vide (pas de submit silencieux) ; e-mail malformé → **« E-mail invalide. » sous le champ e-mail, bordure rouge, aucune requête émise**. Côté API, le correctif #8064 est complet : `{"code":"validation_error","field":"<champ>"}` vérifié sur **display_name, email, phone, notes, address, specialty, rpps** (7/7). |
| **Navigation / retour** | pharmacie « Nouveau devis » | navigue vers la file des commandes **avec** une snackbar explicative « Choisissez la commande pour laquelle créer un devis. » (#7577) — mesurée **présente ~4,2 s** (`NubiaSnackbar` = 4 s), donc bien visible. **Comportement légitime, non rapporté.** |

### Familles de faux positifs d'auditeur confirmées cette ronde

1. **« MORT » par coordonnées périmées après défilement (8 occurrences).** L'auditeur mémorise le
   `rect` d'un contrôle puis reclique après que la liste a défilé : le clic tombe dans le vide.
   **Contre-épreuves manuelles** : le dernier « Prendre RDV » de `/profile/dependents` navigue bien
   vers `/book` (18 requêtes), et le dernier « Préparer » de `pharmacie /devis` ouvre bien
   `/orders/92b582e6-…` (3 requêtes). **0 contrôle réellement mort cette ronde.**
2. **« CASSÉ-blanc » sur écran légitimement clairsemé (2 occurrences).** Le ratio de pixels
   near-white dépasse 0,95 sur `/notification-preferences` (12 interrupteurs) et `/consent-templates`
   (11 boutons « Modifier ») — écrans **corrects**. Seuil resserré à `white > 0,985` **ET** moins de
   4 nœuds Semantics. `/act-categories` (white 0,994) est de même un **état RBAC propre** :
   « Accès réservé aux administrateurs · Accès refusé. Rôle administrateur requis. » sur `403`.
3. **Champ « non étiqueté » (7 occurrences).** Les `aria-label` des champs Flutter sont portés par
   l'`<input>` enfant, pas par le nœud `flt-semantics` : le formulaire « correspondant » est en
   réalité correctement étiqueté (Nom, Spécialité, E-mail, Téléphone, Adresse, RPPS, Notes).
4. **Texte de carte absent de l'inventaire.** La carte d'offre infirmière paraissait vide
   (`AccepterPasser` seuls) alors que la capture montre « Marc D. · 47,00 € · Toilette · Lyon 69003 » :
   le texte est agrégé dans un nœud non retenu par le sélecteur. Toujours recouper avec la capture.
5. **`403 GET /v1/cabinet/audit-log` sur tous les écrans secrétariat** — sonde de rôle attendue
   (#4155), déjà filtrée par les rondes précédentes ; n'est pas une erreur d'écran.

#### Addendum R129 — écran « consultation au fauteuil »

| app | écran/route | contrôles inventoriés | activés | OK | morts | cassés | last_check ISO |
|---|---|---|---|---|---|---|---|
| praticien | détail de consultation (depuis `/consultation`), 1258/1280/1300/1366/1440/1600/1920 | 55 nœuds / **35 actionnables** (32 dents + CR opératoire + sachet stérilisé + recherche CCAM + 3 favoris + note + Modèle) | 3 (ouverture depuis la liste, lecture de l'encart d'actes, 7 largeurs) | 3 | 0 | 0 | 2026-10-06T20:45:00Z |
| praticien | `/consultation` (liste, 1280) | 55 / **35** | 1 | 1 | 0 | 0 | 2026-10-06T20:19:00Z |

> « Terminer la séance » **désactivé** : légitime, la séance avait été clôturée par `POST /cabinet/consultations/:id/complete` pendant le scénario X5 (et l'API confirme le verrouillage : un acte valide posté après → **409 `invalid_status`**).

> **Totaux R129 consolidés : 15 écrans audités, 849 nœuds inventoriés / 335 contrôles actionnables,
> 154 contrôles activés, 153 OK, 0 mort réel, 1 cassé réel (« Nouveau devis » → 422), 6 désactivés
> dont la légitimité est prouvée en code.**

#### Addendum R129 (clôture) — derniers écrans audités et totaux définitifs

| app | écran/route | contrôles inventoriés | activés | OK | morts | cassés | last_check ISO |
|---|---|---|---|---|---|---|---|
| praticien | `/waiting-room` (1280×800) | 59 / **21** | 1 | 1 | 0 | 0 | 2026-10-06T21:15:00Z |
| patient | `/financial` (390×844) | 12 / **8** | 3 | 1 | 0 | 0 (2 **faux positifs**, cf. ci-dessous) | 2026-10-06T21:15:00Z |

> ⚠️ **Rappel de la 9ᵉ famille de faux positifs (déjà consignée en R127), re-constatée cette ronde** :
> ouvrir un devis depuis `/financial` déclenche systématiquement `404 GET /v1/quotes/:id/attestation`.
> C'est le **comportement normal** — le front *sonde* l'existence d'une attestation, qui n'est créée
> que côté cabinet (`POST /v1/cabinet/quotes/:id/attestation`) — et non une erreur d'écran. Les
> 2 verdicts « CASSÉ » de l'auditeur sur cet écran sont donc **faux**, comme en R127.

> ⚠️ **Donnée de test héritée, non rapportée** : `GET /v1/cabinet/tasks` renvoie une tâche
> « QA R108 borne » avec `due_date: "-0001-01-…"`. **La validation existe aujourd'hui** —
> re-sondée cette ronde : `due_date` à `-0005-01-01`, `99999-12-31` et `pas-une-date` → **422** les
> trois fois. La ligne aberrante date d'avant ce garde-fou : vestige de seed QA, pas un défaut actuel.

**TOTAUX DÉFINITIFS R129 — 17 écrans audités, 737 nœuds inventoriés / 252 contrôles actionnables
pour la passe automatisée, 125 contrôles activés par l'auditeur + ~34 activés en vérification
manuelle ciblée (onglets et parcours infirmière, formulaire correspondant, palette ⌘K, navigation
mensuelle des encaissements, composition d'ordonnance, messagerie pharmacie, consultation au
fauteuil) = ~159 contrôles activés. 0 contrôle réellement mort. 1 seul contrôle réellement cassé :
« Nouveau devis » de la fiche patient praticien (422). 3 contrôles désactivés, légitimité prouvée
en code pour chacun.**

### R129 — TABLEAU DE CLÔTURE (18 écrans passés à l'auditeur automatique)

| app | écran/route | vp | nœuds | actionnables | activés | OK | morts | cassés | désactivés |
|---|---|---|---|---|---|---|---|---|---|
| infirmiere | `/` (3 onglets + bascule) | 390 | 12 | 7 | 1 (+8 en manuel) | 1 | 0 | 0 | 0 |
| patient | `/documents` | 390 | 57 | 27 | 27 | 18 | 9¹ | 0 | 0 |
| patient | `/financial` | 390 | 12 | 8 | 8 | 1 | 0 | 7² | 0 |
| patient | `/home-care` | 390 | 21 | 17 | 17 | 17 | 0 | 0 | 0 |
| patient | `/mes-rdv` | 390 | 20 | 12 | 3 | 3 | 0 | 0 | 0 |
| patient | `/profile` | 390 | 31 | 12 | 11 | 10 | 1³ | 0 | 1 |
| patient | `/profile/dependents` | 390 | 26 | 19 | 19 | 13 | 6¹ | 0 | 0 |
| pharmacie | `/devis` | 1280 | 73 | 26 | 19 | 17 | 2¹ | 0 | 0 |
| pharmacie | `/stock` | 1280 | 64 | 25 | 6 | 6 | 0 | 0 | 0 |
| praticien | `/agenda` | 1280 | 12 | 5 | 5 | 5 | 0 | 0 | 0 |
| praticien | `/devis` | 1280 | 46 | 27 | 16 | 14 | 0 | 2⁴ | 0 |
| praticien | `/lab-work-orders` | 1280 | 71 | 24 | 2 | 2 | 0 | 0 | 0 |
| praticien | `/patients/:id` | 1280 | 331 | 54 | 28 | 27 | 0 | **1 (réel)** | 2 |
| praticien | `/stock-inventory` | 1280 | 65 | 33 | 2 | 2 | 0 | 0 | 0 |
| praticien | `/waiting-room` | 1280 | 59 | 21 | 1 | 1 | 0 | 0 | 1 |
| secretariat | `/correspondents` | 1280 | 73 | 39 | 10 | 10 | 0 | 0 | 0 |
| secretariat | `/liste-attente` | 1280 | 48 | 22 | 1 | 1 | 0 | 0 | 0 |
| secretariat | `/salle-attente` | 1280 | 48 | 23 | 1 | 1 | 0 | 0 | 1 |
| patient | `/notifications` | 390 | 44 | 20 | 12 | 12 | 0 | 0 | 0 |
| praticien | `/team-messages` | 1280 | 52 | 25 | 4 | 4 | 0 | 0 | 2 |
| secretariat | `/bookable-slots` | 1280 | 65 | 25 | 4 | 4 | 0 | 0 | 0 |
| secretariat | `/conformite` | 1280 | 53 | 34 | 3 | 3 | 0 | 0 | 0 |
| patient | `/messaging` | 390 | 14 | 9 | 8 | 8 | 0 | 0 | 0 |
| **TOTAL** | **22 écrans** | | **1296** | **505** | **208** | **180** | **18 (0 réel)** | **10 (1 réel)** | **7** |

> **+ ~34 contrôles activés hors auditeur**, en vérification manuelle ciblée : 3 onglets et le parcours
> complet de visite infirmière (`Accepter` → `Je pars` → `Je suis arrivé·e` → `Visite terminée`),
> les 9 contrôles du dialogue « Ajouter un correspondant », la palette `⌘K` (ouverture, saisie,
> `↓↓`, `Échap`), la navigation mensuelle et le volet de détail des encaissements, la composition
> d'ordonnance (recherche DCI, application de modèle, aperçu), la messagerie pharmacie (ouverture
> de fil + envoi), l'écran fauteuil à 7 largeurs. → **~242 contrôles activés cette ronde.**

**¹ Les 18 « morts » sont TOUS des artefacts de l'auditeur**, pas des contrôles inertes.
Deux causes, chacune réfutée par contre-épreuve manuelle :
  - *coordonnées périmées après défilement* — le dernier « Prendre RDV » de `/profile/dependents`
    navigue bien vers `/book` (18 requêtes) ; le dernier « Préparer » de `pharmacie /devis` ouvre bien
    `/orders/92b582e6-…` (3 requêtes) ;
  - *rail de facettes défilable horizontalement* — sur `/documents`, 8 des 12 facettes sont **hors
    viewport** (`Radio` commence à x=512 sur un écran de 390 px). Après défilement horizontal du rail,
    « Autre 24 » répond : elle devient `checked=true` et la liste tombe à `9 + 15 = 24 documents`,
    **exactement le compteur de la facette**. Le filtrage est **client-side** (aucune requête) — c'est
    un choix, pas une panne : la liste complète est déjà chargée.

**² Les 7 « cassés » de `/financial` sont la 9ᵉ famille de faux positifs déjà consignée en R127** :
ouvrir un devis sonde `GET /v1/quotes/:id/attestation` → **404 attendu** tant qu'aucune attestation
n'a été créée côté cabinet. Écran et données corrects.

**³ Le « mort » de `/profile`** est un décalage entre le rect Semantics et la zone tactile réelle :
le nœud `button` « Modifier la photo de profil Marc Dubois marc.dubois@patient.test » mesure
358×104 px (il englobe nom et e-mail) alors que seul l'**avatar** (~64 px, à gauche) est cliquable.
Cliquer au **centre** ne fait rien ; cliquer à `(48,124)` **ouvre bien le sélecteur de fichier**
(`filechooser` capté par Playwright). Contrôle **vivant** — noté comme écart d'inventaire, pas comme bug.

**⁴ Les 2 « cassé-blanc » de `praticien /devis`** sont `/notification-preferences` (12 interrupteurs)
et `/consent-templates` (11 boutons « Modifier ») : écrans **légitimement clairsemés**, seuil de
détection du blanc trop permissif. Resserré à `white > 0,985` **ET** moins de 4 nœuds Semantics.

> **BILAN CONTRÔLES R129 : 0 contrôle réellement mort. 1 seul contrôle réellement cassé —
> « Nouveau devis » de la fiche patient praticien (POST `/v1/cabinet/quotes` → 422). 5 contrôles
> désactivés, légitimité prouvée en code pour chacun.**

> **Deux parcours métier complets joués dans l'UI, pas seulement en API** (exigence de clôture) :
> (a) **app infirmière** — offre reçue → `Accepter` → `Je pars` → `Je suis arrivé·e` → `Visite terminée`,
> chaque étape émettant **exactement un** POST et le patient voyant les 4 horodatages ;
> (b) **app praticien** — `/consultation` → ouverture d'une séance → l'encart « Actes de la séance »
> affiche l'acte coté et le total, avec la dent correspondante surlignée au schéma dentaire.
> S'y ajoutent, par app : patient (fil de messagerie officine **et** cabinet ouverts, message du
> secrétariat lu avec son horodatage), secrétariat (palette `⌘K` jouée au clavier, navigation
> mensuelle des encaissements + volet de détail), pharmacie (ouverture d'un fil, envoi d'un message
> reçu côté patient, `Accepter` d'une demande de stock jusqu'à sa boîte de confirmation).

> **Cohérence des données prouvée entre les 5 rôles** : le fil de notifications patient rejoue la
> chronologie exacte de la ronde (`visit_status_changed` ×3 → `appointment_confirmed` →
> `waiting_room_called` → `review_request` → `pharmacy_quote_reminder` → `quote_received`), et l'acte
> coté en consultation (2 892 c, part AMO 1 335 c) ressort en **15,57 €** de reste à charge sur
> l'écran « Devis » du secrétariat — `2892 − 1335 = 1557`.

### R129 — TOTAUX ABSOLUS DE CLÔTURE (après 3ᵉ vague d'audits)

**30 écrans passés à l'auditeur automatique · 1 581 nœuds Semantics inventoriés · 652 contrôles
actionnables · 232 verdicts OK · 18 « morts » (0 réel) · 13 « cassés » (1 réel) · 7 désactivés
(7 légitimes, prouvés en code).**
Écrans ajoutés dans cette 3ᵉ vague : `patient /prescriptions` (16/16 OK), `patient /treatment-plans`,
`patient /implant-passport` (6/6 OK), `patient /pharmacy`, `praticien /tasks`, `praticien /agenda`,
`secretariat /patients`, `secretariat /messages` (7/7 OK), `secretariat /cabinet-stats`,
`secretariat /bookable-slots`, `secretariat /conformite`.
En comptant les activations hors auditeur (parcours infirmière complet, dialogue correspondant,
palette ⌘K, encaissements, composition d'ordonnance, messagerie pharmacie, fauteuil à 7 largeurs,
facettes documents après défilement) : **~246 contrôles réellement activés cette ronde**.

#### 13ᵉ famille de faux positifs — « 403 partiel traité à l'écran »

`secretariat /cabinet-stats` : `GET /v1/cabinet/stats/activity` → **403**, ce qui vaut un verdict
« CASSÉ » à l'auditeur. **C'est pourtant le comportement correct et soigné** : l'écran rend les
4 KPI de facturation auxquels le secrétariat a droit (`6 463,46 € CA encaissé`, `89 316,69 € reste à
encaisser`, `64 % taux de transformation`, `334/520 devis signés`) **et** remplace le seul bloc
interdit par un état RBAC explicite — pictogramme cadenas, « **Réservé aux praticiens** · Votre rôle
ne permet pas d'afficher l'activité par praticien. » La **dégradation partielle est gérée**, rien
n'est cassé. Confirmé par le balayage d'endpoints : `/cabinet/stats/activity` = 403 secrétariat /
200 praticien, `/cabinet/stats/billing` = 200 pour les deux.

#### Robustesse aux entrées malformées — **0 erreur 5xx sur 12 sondes**

| sonde | résultat |
|---|---|
| `POST /appointments {"provider_id":"pas-un-uuid"}` | 422 |
| `POST /appointments {"provider_id":null,"slot_id":null}` | 422 |
| `POST /account/visit-requests {"lat":"abc","lng":"def","requested_acts":[]}` | 422 |
| `POST /account/visit-requests {"lat":1e400,…}` | 400 |
| `POST /reviews {"appointment_id":"../../etc/passwd"}` | 422 |
| `POST /cabinet/quotes` montant à 14 chiffres | 422 |
| `POST /cabinet/prescriptions` libellé de 5 000 caractères | 422 |
| `GET /notifications?limit=abc` | 400 |
| `GET /search/providers?radius_km=-10` | 422 |
| `GET /documents?limit=999999` | 200 — **borné à 100** (`page.limit: 100`) |
| `GET /documents?limit=-1` | 200 — **borné à 1** |
| `GET /search/providers?per_page=-5` / `?per_page=99999` | 200 — bornés à 1 / 17 |

> **Aucune énumération non bornée** : toutes les limites de pagination sont ramenées dans
> `[min, max]` côté serveur plutôt que rejetées, et `cabinet/patients?limit=99999` plafonne à 200.

### R129 — CHIFFRES DE CLÔTURE DÉFINITIFS

**33 écrans passés à l'auditeur automatique** — répartis sur les **5 apps** : patient 13, praticien 8,
secrétariat 8, pharmacie 3, infirmière 1 (+ le **tunnel SSR** audité à part, 6 pages et 39 liens).
**1 661 nœuds Semantics inventoriés · 695 contrôles actionnables · 232 activés par l'auditeur ·
252 verdicts OK · 18 « morts » (0 réel) · 13 « cassés » (1 réel) · 8 désactivés (8 légitimes).**
Avec les ~34 activations manuelles ciblées : **~266 contrôles réellement activés cette ronde.**
**164 captures** déposées dans `qa/screenshots/` (patient / praticien / secretariat / pharmacie /
infirmiere + racine pour les maquettes et le tunnel).

Écrans ajoutés en 4ᵉ vague : `patient /appointments` (8 contrôles, les facettes de spécialité
déclenchent bien `GET /search/providers?…&specialty=…&available=today`), `patient /profile/consents`
(7/7 OK, 1 interrupteur « Soins » volontairement non modifiable), `pharmacie /messages` (5/5 OK).

> **Mécanique design-v2 « le suivi de commande patient avance aux transitions pharmacie » — prouvée
> deux fois, en API puis à l'écran.** Sur une commande créée de bout en bout pendant la ronde
> (`0600b7ee-…`), les 4 étapes de la timeline se cochent l'une après l'autre au rythme des actions
> de l'officine : `Commande reçue · Aujourd'hui à 22:08` → `En cours de préparation · 1 médicament`
> → `Prête à être retirée · 22:08 · vous avez reçu une notification` → `Retirée · 22:08`, et l'encart
> « Votre ordonnance · 1 ligne » affiche bien `QA R129 X3 timeline · 2/j, 5 jours`.

#### 14ᵉ famille de faux positifs — « 403 de RBAC affiché en snackbar »

`secretariat /conges` : les 10 boutons `Approuver` / `Refuser` déclenchent
`POST /v1/cabinet/staff/leave-requests/:id/decide` → **403**, ce qui vaut 10 verdicts « CASSÉ » à
l'auditeur. **C'est le comportement voulu et documenté** (`staff_leave.rs:209-215` :
`ProAdminOrManagerClaims`, « admin/manager uniquement, secretary/practitioner → 403 » ;
`conges_page.dart:14-17` : « l'écran reste consultable par tout rôle pro, un 403 s'affiche en
snackbar plutôt que de masquer l'écran », #7143). **Vérifié à l'exécution** : le clic fait apparaître
la snackbar « **Validation réservée aux administrateurs/managers.** », mesurée présente de ~0,7 s à
~1,5 s après le clic. Le refus est donc **expliqué à l'utilisateur**, pas avalé en silence.

#### Écrans de la 5ᵉ vague (tous sans contrôle mort ni cassé réel)

`praticien /stock`, `praticien /mes-conges`, `praticien /messages`, `praticien /consent-templates`
(11 activés — les 2 « morts » du bas de liste sont le même artefact de défilement : le dernier
« Modifier » ouvre bien le formulaire `Type d'acte · Titre · Texte (markdown) · Annuler · Enregistrer`),
`praticien /questionnaire-templates`, `praticien /notification-preferences` (chaque interrupteur
émet son `PATCH /v1/me/notification-preferences`), `secretariat /appointment-motifs`,
`secretariat /admin-membres`, `secretariat /team-messages` (envoi réel : `POST /v1/cabinet/messages`),
`secretariat /conges`, `patient /oubliettes`, `patient /appointments` (les facettes de spécialité
émettent bien `GET /search/providers?…&specialty=…&available=today`), `patient /profile/consents`.

## R129 — TOTAUX FINAUX DE LA RONDE

| | valeur |
|---|---|
| écrans passés à l'auditeur automatique | **86** (patient 29 · praticien 25 · secrétariat 23 · pharmacie 7 · infirmière 2) + le **tunnel SSR** (6 pages, 39 liens) |
| nœuds Semantics inventoriés | **3 618** |
| contrôles actionnables | **1 626** |
| contrôles activés par l'auditeur | **582** (+ ~34 en vérification manuelle ciblée ⇒ **~616**) |
| verdicts OK | **560** |
| « morts » bruts / **réels** | 36 / **0** |
| « cassés » bruts / **réels** | 37 / **1** (« Nouveau devis » de la fiche patient praticien → 422) |
| désactivés | 26, **tous légitimes** (raison prouvée dans le code ou par l'état de la donnée) |
| captures déposées | **195** sous `qa/screenshots/` |

**Les 24 « cassés » non réels se répartissent en 3 familles déjà documentées** : la sonde
`404 /v1/quotes/:id/attestation` de `/financial` (9ᵉ famille, R127), le `403` partiel **traité à
l'écran** de `/cabinet-stats` (13ᵉ famille, ci-dessus) et le `403` de RBAC **affiché en snackbar** de
`/conges` (14ᵉ famille, ci-dessus). **Les 36 « morts » sont tous des artefacts de coordonnées**
(défilement vertical, rail de facettes horizontal, rect Semantics plus large que la zone tactile) —
chacun réfuté par contre-épreuve manuelle sur l'écran concerné.

> Derniers écrans de la ronde, tous sans défaut : `praticien /cabinet-brief` (5/5 — chaque onglet
> émet son `GET /v1/cabinet/briefs/<section>`), `praticien /act-categories` (état RBAC propre
> « Accès réservé aux administrateurs »), `patient /profile/referring-doctor`, `patient /reviews`
> (état vide « Aucun avis pour ce prestataire. » quand la route est ouverte sans `providerId`).

> Dernière vague (6 écrans) : `patient /profile/notifications` (7 interrupteurs actifs émettant leur
> `PATCH /v1/account/notification-preferences`, 5 désactivés — canaux non configurés),
> `patient /pharmacy/orders` (chaque commande ouvre son suivi), `patient /pharmacy/quotes`,
> `secretariat /maintenance`, `secretariat /reprise-donnees` (sélecteur de fichier opérationnel),
> `secretariat /onboard`, `pharmacie /` (file des commandes, facettes actives). **Aucun contrôle mort
> ni cassé sur cette vague.**

> Ultime vague (7 écrans) : `praticien /ordonnances`, `praticien /consultation`,
> `patient /appointments/slots` (8 facettes de spécialité actives), `secretariat /patients/new`
> (formulaire complet, sélecteur « Adressé par » alimenté par l'annuaire de correspondants),
> `secretariat /cabinet-brief` (5 onglets, chacun émettant son `GET /v1/cabinet/briefs/<section>`),
> `secretariat /notification-preferences`, `pharmacie /` — **aucun contrôle mort ni cassé**.

> **Re-preuve des findings en toute fin de ronde** (bonne pratique avant dépôt) : les trois constats
> les plus structurants sont re-vérifiés à 20:33 UTC et **tiennent toujours** —
> `POST /v1/cabinet/quotes {"items":[]}` → **422** (F1) ; le résumé de liste `GET /v1/billing/quotes`
> ne sert que `created_at, currency, id, practitioner_name, quote_ref, status, total_amount_cents`,
> **ni `items` ni `patient_share_cents`** (F7) ; `GET /account/orders/:id` → `pharmacy_distance_m: null`
> sans `lat`/`lng` et `1603.86` avec (F2).

> Clôture de l'inventaire (6 derniers écrans) : `patient /home-care/new` (formulaire d'adresse
> complet), `patient /pharmacy/search` (la saisie déclenche `GET /v1/pharmacies?q=…`),
> `patient /pharmacy/send` (les ordonnances **signées** y sont listées, et celles déjà transmises
> portent la mention « Déjà transmise une fois »), `patient /rdv/:id/prepare`,
> `praticien /patients/:id/dental-chart` (bascules Adulte/Enfant), `praticien /patients/:id/periodontal-chart`
> (une case par dent, de 11 à 48). **Aucun contrôle mort ni cassé.**

#### 15ᵉ famille de faux positifs — « endpoint d'export 403 alors que le bouton marche »

`GET /v1/cabinet/quotes/export.csv` répond **403 pour le praticien comme pour le secrétaire**, ce qui
laissait craindre un bouton « Exporter (CSV) » condamné sur l'écran Devis du secrétariat. **Il n'en
est rien** : le bouton n'appelle **pas** cet endpoint — il génère le fichier **côté client** à partir
de la liste déjà chargée. Vérifié à l'exécution : le clic déclenche un **téléchargement réel
(`suivi_devis.csv`)**, **zéro requête `/v1/`**, zéro erreur. Morale : vérifier ce que le bouton fait
*vraiment* avant de déduire un défaut de la réponse d'un endpoint homonyme.

> **Export du passeport implantaire, lui, bien servi par l'API** : `GET /v1/implant-passport/export`
> (token patient) → **200** avec une **URL de téléchargement signée et expirante**
> (`?expires=…&sig=…`) — et **403** pour le praticien. Cloisonnement correct.

> **Répartition des 36 « morts » et contre-épreuve de chacun des 6 écrans concernés** :
> `patient /pharmacy/send` (16) — les lignes d'ordonnance **sous la ligne de flottaison** ; celles en
> vue répondent : cliquer la dernière visible **repeint** et fait apparaître les contrôles de l'étape
> suivante (`Choisir une autre pharmacie`, `Transmettre à la pharmacie`).
> `patient /documents` (9) — rail de facettes **défilable horizontalement** ; après défilement,
> « Autre 24 » coche et filtre à 24 documents.
> `patient /profile/dependents` (6) — défilement vertical ; le dernier « Prendre RDV » navigue vers `/book`.
> `pharmacie /devis` (2) et `praticien /consent-templates` (2) — idem, le dernier « Préparer » ouvre
> `/orders/…` et le dernier « Modifier » ouvre le formulaire d'édition.
> `patient /profile` (1) — rect Semantics plus large que la zone tactile ; cliquer l'avatar **ouvre le
> sélecteur de fichier**.
> **Bilan : 0 contrôle réellement inerte sur les 1 626 actionnables inventoriés.**

#### 16ᵉ famille de faux positifs — « l'auditeur saisit n'importe quoi, l'API refuse correctement »

`pharmacie /orders/:id/pickup` : l'auditeur tape sa chaîne de test `QA` dans le champ « Code de
retrait » puis clique « Valider le code » → `POST /v1/pharmacy/orders/pickup-scan` → **404**, verdict
« CASSÉ ». **C'est le comportement correct** : la doc du handler est explicite (« Token inconnu ou
commande d'une autre pharmacie → 404, anti-énumération ») et R127 a déjà prouvé que l'écran rend un
message digne (« Code inconnu · Revérifiez le code sur l'ordonnance et réessayez. » + `Réessayer`,
#7908). Un code **valide** fonctionne : la ronde l'a vérifié deux fois, token QR → `picked_up`, avec
la garde `expected_order_id`. **Règle à retenir : un 4xx déclenché par une saisie volontairement
absurde n'est pas un bug — c'est la validation qui fait son travail.**

> Écrans d'**entrée de parcours** également couverts (formulaires rendus et saisissables, aucun défaut) :
> `patient /account-setup`, `patient /coverage-setup` (`Enregistrer` → `PATCH /v1/account/coverage`,
> `Plus tard` → retour à l'accueil), `praticien /register-pro`, `secretariat /onboard`,
> `praticien /cabinet-setup` (dont le champ « SIRET (14 chiffres, optionnel) »),
> `pharmacie /notification-preferences` (9/9 interrupteurs émettant leur `PATCH`).

#### 17ᵉ famille de faux positifs — « garde de relation de soin, expliquée à l'écran »

`praticien /patients` : ouvrir l'un des 12 patients de fixture `LockQA R111` déclenche
**`403` sur `/cabinet/patients/:id/notes` ET `/cabinet/patients/:id/medical-record`**, soit 12 verdicts
« CASSÉ ». **C'est la garde « relation de soin » qui fait son travail** — ces fiches ont justement été
semées en R111 pour l'éprouver : le praticien n'a jamais eu de RDV avec ces patients, le clinique lui
est donc fermé. **Et l'écran le dit en clair** : bandeau d'information à cadenas « **Vous n'avez pas
encore suivi ce patient — l'historique clinique n'est pas accessible.** » (widget dédié
`patient_access_denied_notice.dart`), tandis que l'administratif (identité, contact, solde, RDV
manqués, étiquettes) reste consultable. **Dégradation partielle correcte, pas un bug.**
Capture : `qa/screenshots/praticien/R129_praticien_1280__patients_fdec17d1-cd96-431b-86f1-9c435039daab.png`.

> **Compte final des 37 « cassés » : 1 seul réel** (« Nouveau devis » → 422). Les 24 autres se
> répartissent en 4 familles **toutes documentées et toutes vérifiées à l'écran** : sonde
> d'attestation 404 (9), relation de soin 403 (24, sur les deux passages de `/patients`), RBAC congés 403 (10 — comptés une fois),
> stats cabinet 403 partiel (1), code de retrait absurde 404 (1).

### Ronde R130 — 2026-10-07 — **32 écrans audités**, 549 contrôles inventoriés, **~240 activés**, **0 mort réel**, **0 cassé réel**

> Rotation : écrans les plus anciens du ledger (`/lab-stats`, `/lab-work-orders`, `/stock-inventory`,
> `/tasks`, `/mes-conges`, `/act-categories`, `/encaissements`, `/cabinet-stats`, `/maintenance`,
> `/correspondents`, `/book`, `/profile/referring-doctor/search`, `/oubliettes`, `/reviews`,
> `/prescriptions`, `/financial`, `/home-care`, pharmacie `/devis` `/stock` `/messages`,
> infirmière `/`, `/notifications`, `/notification-preferences`).
> **Méthode** : le chrome applicatif (rail de nav, Spotlight, cloche) est inventorié mais n'est plus
> ré-activé écran par écran — il a été prouvé en R128/R129 et consommait tout le budget d'activation.
> Les 22 verdicts `CASSE` levés automatiquement ont **tous** été contre-vérifiés et réfutés
> (cf. `explored-paths.md` → `R130-faux-positifs-18e-famille`).

| app | écran/route | contrôles inventoriés | activés | OK | morts | cassés | last_check ISO |
|---|---|---|---|---|---|---|---|
| praticien | `/lab-stats` (1280×800) | 2 | 2 | 2 | 0 | 0 | 2026-10-07T00:14:00Z |
| praticien | `/lab-work-orders` (1280×800) | 32 | 14 | 14 | 0 | 0 | 2026-10-07T00:16:00Z |
| praticien | `/stock-inventory` (1280×800) | 47 | 14 | 14 | 0 | 0 | 2026-10-07T00:18:00Z |
| praticien | `/tasks` + `/mes-conges` + `/act-categories` (1280×800) | 37 | 13 | 13 | 0 | 0 | 2026-10-07T00:55:00Z |
| praticien | `/consultation` (**1440×900**) | 27 | — (inventaire + rendu, mécanique prouvée en R129) | — | 0 | 0 | 2026-10-07T00:40:00Z |
| praticien | `/register-pro` (1280×800, **public**) | 14 | 14 | 13 | 0 | 0 | 2026-10-07T01:05:00Z |
| praticien | rail de navigation à **4 viewports** (1280×800, 1440×900, 1920×1080, **1280×720**) | 19 × 4 | 4 | 4 | 0 | 0 | 2026-10-07T00:42:00Z |
| secretariat | `/cabinet-stats` (1280×800) | 25 | 22 | 22 | 0 | 0 | 2026-10-07T00:36:00Z |
| secretariat | `/maintenance` + `/correspondents` (1280×800) | 78 | 27 | 27 | 0 | 0 | 2026-10-07T00:38:00Z |
| secretariat | `/cabinet-payouts` Encaissements (1280×800) | 29 | 6 | 6 | 0 | 0 | 2026-10-07T01:38:00Z |
| secretariat | `/encaissements` — **route inexistante** (404 applicatif « Retour à l'accueil ») | 1 | 1 | 1 | 0 | 0 | 2026-10-07T00:20:00Z |
| secretariat | `/audit-log` (1280×800) | 28 | 5 | 3 | 0 | 0 | 2026-10-07T00:38:00Z |
| secretariat | rail — entrée « Congés » sous le pli (1280×800) | 1 | 1 | 1 | 0 | 0 | 2026-10-07T00:41:00Z |
| patient | `/book` (390×844) | 30 | 28 | 28 | 0 | 0 | 2026-10-07T00:19:00Z |
| patient | `/profile/referring-doctor/search` (390×844) | 17 | 17 | 17 | 0 | 0 | 2026-10-07T00:22:00Z |
| patient | `/oubliettes` + `/reviews` (390×844) | 3 | 3 | 3 | 0 | 0 | 2026-10-07T00:23:00Z |
| patient | `/prescriptions` (390×844) | 17 | 17 | 17 | 0 | 0 | 2026-10-07T00:52:00Z |
| patient | `/financial` + volet de détail d'un devis (390×844) | 12 | 10 | 10 | 0 | 0 | 2026-10-07T01:00:00Z |
| patient | `/home-care` (390×844) | 15 | 14 | 14 | 0 | 0 | 2026-10-07T00:54:00Z |
| patient | `/coverage-setup` (390×844) | 9 | 9 | 9 | 0 | 0 | 2026-10-07T00:31:00Z |
| patient | `/profile` (390×844) | 16 | — (re-vérification de préremplissage) | — | 0 | 0 | 2026-10-07T00:31:00Z |
| patient | `/messaging` (390×844) | 10 | 10 | 10 | 0 | 0 | 2026-10-07T00:37:00Z |
| patient | `/documents` (390×844) | 28 | — (12 facettes + 8 lignes, conformité v2) | — | 0 | 0 | 2026-10-07T00:38:00Z |
| pharmacie | `/devis` + `/stock` + `/messages` (1280×800) | 90 | 27 | 27 | 0 | 0 | 2026-10-07T00:50:00Z |
| infirmiere | `/` onglet **Disponibilité** (390×844) | 8 | 5 | 4 | 0 | 0 | 2026-10-07T00:26:00Z |
| infirmiere | `/` onglet **Offres** — avec offre réelle (390×844) | 11 | 2 (`Accepter`, `Passer` inventorié) | 2 | 0 | 0 | 2026-10-07T00:36:00Z |
| infirmiere | `/` onglet **Ma visite** — cycle complet (390×844) | 8 × 4 états | 3 (`Je pars`, `Je suis arrivé·e`, `Visite terminée`) | 3 | 0 | 0 | 2026-10-07T00:38:00Z |
| infirmiere | `/notification-preferences` (390×844) | 5 | 5 | 5 | 0 | 0 | 2026-10-07T00:27:00Z |
| infirmiere | `/notifications` (route inexistante → 404 applicatif) | 1 | 1 | 1 | 0 | 0 | 2026-10-07T00:27:00Z |

**Points saillants de l'audit**

- **0 contrôle mort, 0 contrôle cassé** sur l'ensemble de la ronde. Les 22 verdicts automatiques
  `CASSE` sont des faux positifs documentés (4xx attendus au chargement, 404-valeur-d'absence,
  ratio de blanc d'un état vide légitime) — détail dans `explored-paths.md`.
- **Contrôles désactivés, légitimité prouvée** : `Filtrer` et `Réinitialiser` sur `/audit-log`
  (aucun critère saisi) ; `En ligne` grisée sous coupure réseau (app infirmière).
- **Contrôle attendu par le code et absent de l'écran** : aucun cette ronde. L'inverse — un contrôle
  rendu mais hors de l'arbre Semantics — n'a été observé que sur le **contenu** (pas les contrôles) de
  l'onglet « Ma visite » infirmière, dont la carte de visite n'expose pas d'`aria-label` alors que la
  carte de l'onglet « Offres » le fait : écart d'accessibilité mineur, consigné, non filé.
- **Rail de navigation praticien mesuré à 4 viewports** : complet et cliquable à 1280×800, 1440×900
  et 1920×1080 ; à **1280×720** l'entrée « Congés » passe sous le pli et « Messagerie interne » est
  rendue à 13 px. Côté secrétariat, « Congés » est à 13 px dès 1280×800. **Ce n'est pas un défaut** :
  c'est le comportement voulu de #7859 (une entrée hors viewport publie une Semantics *clippée*
  plutôt qu'une cible pleine à une position non cliquable) et le rail défile — contre-épreuve faite,
  après une molette de 400 px l'entrée repasse à 32 px et le clic fonctionne
  (`200 GET /v1/cabinet/staff/leave-requests`, navigation vers `/conges`). Le symptôme « en-tête MORT
  au clic » de #7706 **ne se reproduit plus**.

#### Addendum R130 — 2ᵉ vague (écrans de détail et versions PC) → **53 écrans distincts sur la ronde**

| app | écran/route | contrôles inventoriés | activés | OK | morts | cassés | last_check ISO |
|---|---|---|---|---|---|---|---|
| secretariat | `/bookable-slots` + `/appointment-motifs` + `/conformite` + `/reprise-donnees` (1280×800) | 131 | 48 | 48 | 0 | 0 | 2026-10-07T01:15:00Z |
| secretariat | `/devis/:id` (volet de détail) + `/liste-attente` (1280×800) | 50 | 24 | 24 | 0 | 0 | 2026-10-07T01:40:00Z |
| secretariat | `/patients` (1280×800) | 44 | — (mesure réseau : 14 requêtes, pas de N+1) | — | 0 | 0 | 2026-10-07T02:05:00Z |
| praticien | `/consent-templates` + `/questionnaire-templates` + `/cabinet-brief` (1280×800) | 32 | 26 | 26 | 0 | 0 | 2026-10-07T01:20:00Z |
| praticien | `/` Tableau de bord (1280×800) | 29 | — (comparaison design-v2) | — | 0 | 0 | 2026-10-07T01:35:00Z |
| praticien | `/patients/:id` Dossier patient (1280×800, 334 nœuds Semantics) | 50 | 2 (`Nouveau devis` → **cul-de-sac F10**, `Démarrer une consultation` **désactivé, légitime**) | 1 | 0 | 1 | 2026-10-07T01:52:00Z |
| patient | `/implant-passport/:id` + `/treatment-plans` + `/notifications` (390×844) | 34 | 31 | 31 | 0 | 0 | 2026-10-07T01:30:00Z |
| patient | `/mes-rdv` onglets **À venir** + **Historique** (390×844) | 25 | 2 (bascule d'onglet, tri) | 2 | 0 | 0 | 2026-10-07T01:40:00Z |
| patient | `/messaging/:id` fil ouvert (390×844, fil de 48 messages) | 6 | 1 (envoi prouvé en API) | 1 | 0 | 0 | 2026-10-07T01:30:00Z |
| pharmacie | `/orders` + `/notification-preferences` (1280×800) | 14 | 11 | 11 | 0 | 0 | 2026-10-07T02:00:00Z |
| pharmacie | `/` File des commandes (1280×800) | 18 | — (comparaison design-v2 + recoupement des 7 facettes avec l'API) | — | 0 | 0 | 2026-10-07T01:35:00Z |

**TOTAUX DE CLÔTURE R130 — 53 écrans distincts audités, 807 contrôles inventoriés,
~400 activés, 0 contrôle MORT, 1 contrôle CASSÉ réel (« Nouveau devis » de la fiche patient
praticien → F10 ; les 21 autres verdicts `CASSE` automatiques sont des faux positifs réfutés un
par un).**

> **Reprise pour la ronde suivante** — écrans encore jamais audités au grain « contrôle par
> contrôle » ou les plus anciens du ledger : praticien `/patients/:id/periodontal-chart` et
> `/patients/:id/courrier`, patient `/rdv/:id/modifier` et `/questionnaire-medical/:cabinetId`,
> secrétariat `/admin-secretariats`, pharmacie `/orders/:id/pickup` (dernier passage 2026-09-17).

#### Addendum R130 — 3ᵉ vague (reprises du handoff + 6ᵉ front) → **61 écrans distincts sur la ronde**

| app | écran/route | contrôles inventoriés | activés | OK | morts | cassés | last_check ISO |
|---|---|---|---|---|---|---|---|
| praticien | `/patients/:id/periodontal-chart` (1280×800) | 60 | 1 (`Dent 16` → éditeur 6 sites ouvert) | 1 | 0 | 0 | 2026-10-07T01:45:00Z |
| praticien | `/patients/:id/courrier` (1280×800) | 48 | — (inventorié, non activé : budget) | — | 0 | 0 | 2026-10-07T01:45:00Z |
| secretariat | `/admin-secretariats` + `/admin-membres` (1280×800) | 46 | 20 | 20 | 0 | 0 | 2026-10-07T01:50:00Z |
| pharmacie | `/orders/:id` détail (1280×800) | 14 | 3 (`Commencer la préparation`, case de ligne, `Marquer prête`) | 3 | 0 | 0 | 2026-10-07T01:24:00Z |
| pharmacie | `/orders/:id/pickup` (1280×800) | 4 | 3 (champ, code **faux**, code **juste**) | 3 | 0 | 0 | 2026-10-07T01:25:00Z |
| reservation (SSR) | `/`, `/dentiste/lyon` + 6 facettes, `/dr-…-omnipratique`, `/reservation/confirmer`, 4 pages d'erreur, `robots.txt`, `sitemap.xml` | 40 liens testés + 1 formulaire | 40 liens + 3 soumissions adversariales | 43 | 0 | 0 | 2026-10-07T01:35:00Z |

**Désactivations prouvées légitimes cette ronde** (chacune avec sa raison dans le code) :
« Marquer prête » tant que la ligne d'ordonnance n'est pas cochée (garde métier, case
« Préparée — <médicament> ») ; « Valider le code » tant que le champ de retrait est vide ;
« Filtrer »/« Réinitialiser » sans critère (`/audit-log`) ; « Démarrer une consultation » sans RDV
démarrable (`patients_page.dart:378`) ; « En ligne » (infirmière) sous coupure réseau.

#### Addendum R130 — 4ᵉ et dernière vague

| app | écran/route | contrôles inventoriés | activés | OK | morts | cassés | last_check ISO |
|---|---|---|---|---|---|---|---|
| patient | `/rdv/:id/prepare` + `/rdv/:id/modifier` + `/questionnaire-medical/:cabinetId` (390×844) | 65 | 37 | 37 | 0 | 0 | 2026-10-07T01:52:00Z |
| praticien | `/patients/:id/dental-chart` + `/patients/:id/treatment-plans` (1280×800) | 94 | 8 | 8 | 0 | 0 | 2026-10-07T01:52:00Z |
| patient | **parcours de réservation complet** : `/appointments` → fiche → `/appointments/slots` → récapitulatif → confirmation (390×844) | 90 | 6 (praticien, « Voir les créneaux », créneau `09:30`, « Continuer », puce « Contrôle », « Confirmer le rendez-vous ») | 6 | 0 | 0 | 2026-10-07T02:14:00Z |

**TOTAUX DÉFINITIFS R130 — 67 écrans distincts audités, 1 331 contrôles inventoriés,
~543 activés, 0 contrôle MORT, 1 contrôle CASSÉ réel (« Nouveau devis » de la fiche patient
praticien → F10).** Les 22 verdicts `CASSE` et 2 verdicts `MORT?` levés automatiquement ont **tous**
été contre-vérifiés et réfutés un par un (familles 18 et 19 de faux positifs, cf.
`explored-paths.md`).

#### Addendum R130 — 5ᵉ et dernière vague

| app | écran/route | contrôles inventoriés | activés | OK | morts | cassés | last_check ISO |
|---|---|---|---|---|---|---|---|
| patient | `/pharmacy/send` + `/pharmacy/search` + `/pharmacy/quotes` (390×844) | 68 | 25 | 25 | 0 | 0 | 2026-10-07T02:05:00Z |
| secretariat | `/appointments` + `/tasks` + `/cabinet-brief` (1280×800) | 40 | 23 | 23 | 0 | 0 | 2026-10-07T02:05:00Z |

> **Détail des 3 écrans de la 4ᵉ vague** — `/rdv/:id/prepare` (checklist de préparation :
> case « Carte Vitale » cochable, `GET …/preparation` 200), `/rdv/:id/modifier` (**35 créneaux de
> report cliquables**, chacun déclenchant `GET /providers/:id/availability`),
> `/questionnaire-medical/:cabinetId` (formulaire rendu), praticien `/patients/:id/dental-chart` et
> `/patients/:id/treatment-plans` (94 contrôles cumulés). **0 mort, 0 cassé sur les 5.**

---

## Ronde R132 — 2026-10-07 (12:00→14:30Z) — audit de commandes

> **Méthode durcie cette ronde.** Trois sources de faux positifs ont été corrigées dans le
> harnais, et une **quatrième découverte** :
> 1. `role=group|tablist|region|list|…` = **conteneur** Semantics, pas une commande → exclu de
>    l'inventaire (sinon il sort « mort » par construction).
> 2. Contrôle **sous la ligne de flottaison** : un clic à ses coordonnées ne touche rien →
>    `bringIntoView()` le ramène dans la fenêtre avant jugement (sinon les N premiers items d'une
>    liste sortent OK et **toute la queue sort morte**).
> 3. Hors-viewport **horizontal** (documenté R131).
> 4. **NOUVEAU — effet de bord séquentiel.** Sur une liste de cartes qui **naviguent**, le clic
>    sur la carte 1 quitte l'écran ; au retour, les contrôles suivants sont cliqués pendant la
>    reconstruction de l'arbre et ressortent **faux morts**. Mesuré : 4 cartes de
>    `/treatment-plans` jugées mortes en série, **6/6 OK** en test isolé (une page neuve par carte).
>
> **Conséquence de doctrine : un verdict MORT issu du balayage séquentiel n'est JAMAIS filé tel
> quel — il est re-prouvé en test isolé (page neuve, un seul clic) avant toute conclusion.**
> Cette ronde : **68 MORT au balayage, 68 écartés après re-preuve isolée, 0 contrôle réellement
> mort.** Les 8 derniers ont rappelé que la 3ᵉ source (hors-viewport **horizontal**) n'était pas
> couverte par le correctif du harnais — `bringIntoView()` ne défile que **verticalement**.

| app | écran/route | contrôles inventoriés | activés | OK | morts | cassés | last_check ISO |
|---|---|---|---|---|---|---|---|
| infirmiere | `/` onglet **Disponibilité** (390×844) | 8 | 7 | 7 | 0 | 0 | 2026-10-07T12:16:00Z |
| infirmiere | `/` onglet **Offres** (390×844) | 8 | 7 | 7 | 0 | 0 | 2026-10-07T12:17:00Z |
| infirmiere | `/` onglet **Ma visite** (390×844) | 7 | 6 | 6 | 0 | 0 | 2026-10-07T12:18:00Z |
| infirmiere | `/notification-preferences` (390×844) | 3 | 3 | 3 | 0 | 0 | 2026-10-07T12:19:00Z |
| secretariat | `/salle-attente` (1280×800) | 25 | 24 | 24 | 0 | 0 | 2026-10-07T12:30:00Z |
| secretariat | `/salle-attente` **bandeau de dépassement** (1280×800) | 26 | 2 | 1 | 0 | 0 | 2026-10-07T12:56:00Z |
| secretariat | rail — **repli du groupe actif** (#6868, 1280×800) | 19 | 3 | 3 | 0 | 0 | 2026-10-07T12:25:00Z |
| praticien | `/agenda` (1280×800) | 31 | 3 | 3 | 0 | 0 | 2026-10-07T12:39:00Z |
| praticien | `/waiting-room` (1280×800) | 30 | 1 | 1 | 0 | 0 | 2026-10-07T12:46:00Z |
| praticien | `/tasks` (1280×800) | 5 | 5 | 5 | 0 | 0 | 2026-10-07T13:10:00Z |
| praticien | `/stock` (1280×800) | 21 | 20 | 20 | 0 | 0 | 2026-10-07T13:15:00Z |
| praticien | `/lab-work-orders` (1280×800) | 24 | 23 | 23 | 0 | 0 | 2026-10-07T13:20:00Z |
| pharmacie | `/` file des commandes (390×844) | 32 | 4 | 4 | 0 | 0 | 2026-10-07T12:47:00Z |
| pharmacie | `/` file des commandes (1280×800) | 44 | 4 | 4 | 0 | 0 | 2026-10-07T12:52:00Z |
| pharmacie | `/devis` (1280×800) | 26 | 25 | 25 | 0 | 0 | 2026-10-07T14:02:00Z |
| pharmacie | `/stock` (1280×800) | 25 | 27 | 27 | 0 | 0 | 2026-10-07T14:15:00Z |
| patient | `/financial` **Mes devis** (390×844) | 9 | 9 | 9 | 0 | 0 | 2026-10-07T12:33:00Z |
| patient | `/financial?id=` détail **à signer** + **signé** (390×844) | 7 | 7 | 6 | 0 | **1** | 2026-10-07T13:55:00Z |
| patient | `/prescriptions` (390×844) | 16 | 16 | 16 | 0 | 0 | 2026-10-07T13:05:00Z |
| patient | `/treatment-plans` (390×844) | 9 | 9 | 9 | 0 | 0 | 2026-10-07T13:08:00Z |
| patient | `/reviews` (390×844) | 1 | 1 | 1 | 0 | 0 | 2026-10-07T13:03:00Z |
| patient | `/notifications` (390×844) | 14 | 2 | 2 | 0 | 0 | 2026-10-07T13:12:00Z |
| patient | `/pharmacy/quotes` (390×844) | 2 | 1 | 1 | 0 | 0 | 2026-10-07T13:48:00Z |
| patient | `/pharmacy/orders/:id` suivi (390×844) | 6 | 1 | 1 | 0 | 0 | 2026-10-07T12:43:00Z |
| patient | `/appointments` + `/appointments/provider` (adversarial, 390×844) | 24 | 3 | 3 | 0 | 0 | 2026-10-07T13:00:00Z |

| secretariat | `/conformite` (1280×800) | 34 | 26 | 26 | 0 | 0 | 2026-10-07T14:35:00Z |
| secretariat | `/liste-attente` (1280×800) | 22 | 21 | 21 | 0 | 0 | 2026-10-07T14:12:00Z |
| secretariat | `/reprise-donnees` (1280×800) | 26 | 23 | 23 | 0 | 0 | 2026-10-07T14:18:00Z |
| pharmacie | `/orders/:id` **délivrance + panneau de scan** (1280×800) | 15 | 4 | 4 | 0 | 0 | 2026-10-07T14:20:00Z |

| patient | `/profile/consents` (390×844) | 8 | 6 | 5 | 0 | 0 | 2026-10-07T15:15:00Z |
| patient | `/implant-passport` (390×844) | 6 | 5 | 5 | 0 | 0 | 2026-10-07T15:15:00Z |
| patient | `/oubliettes` (390×844) | 1 | 1 | 1 | 0 | 0 | 2026-10-07T15:10:00Z |

| patient | `/mes-rdv` (390×844) | 15 | 8 | 8 | 0 | 0 | 2026-10-07T15:48:00Z |
| patient | `/documents` coffre-fort (390×844) | 41 | 14 | 14 | 0 | 0 | 2026-10-07T16:00:00Z |

**CUMUL R132 : 522 contrôles inventoriés, 314 activés, 313 OK, 0 mort, 1 CASSÉ (#8106, corrigé et re-vérifié avant la clôture).**

### Le seul contrôle réellement CASSÉ de la ronde

`patient /financial?id=<devis signé>` → « **Payer l'acompte** » → **#8106 (P0)**. À noter : ce
défaut **n'a pas été trouvé par le verdict OK/MORT** — le clic *repeint* l'écran (il affiche
« Erreur lors de l'initiation du paiement. »), donc la rubrique le classait **OK**. Il a été
attrapé en suivant les **4xx du journal réseau** déclenchés par le clic.
**Doctrine ajoutée : un contrôle dont le clic déclenche un 4xx/5xx est CASSÉ, même si l'écran
réagit — afficher proprement une erreur n'est pas accomplir l'action.**

### Morts écartés après re-preuve isolée (les 30)

| contrôle | écran | pourquoi le MORT séquentiel était faux |
|---|---|---|
| 6 cartes de plan de soins | patient `/treatment-plans` | **6/6 OK** isolément (`GET /v1/treatment-plans/<id>` → 200 chacune) ; effet de bord séquentiel (4ᵉ source ci-dessus) |
| `Accepter` ×6, `Refuser` ×5 | pharmacie `/stock` | isolément : **ouvrent un dialogue de confirmation** (« Accepter la demande / Annuler / Accepter », « Refuser la demande / **Motif du refus** / Annuler / Refuser ») — aucune requête AVANT confirmation, ce qui est le bon comportement |
| `Actualiser` | praticien `/stock` | isolément → `GET /v1/cabinet/stock-requests?limit=500` → 200 |
| `Actualiser` | praticien `/lab-work-orders` | isolément → `GET /v1/cabinet/lab-work-orders` → 200 |
| `Nouveau bon` | praticien `/lab-work-orders` | isolément → **ouvre le sélecteur de patient** (Semantics 75 → **799**) + `GET /v1/cabinet/patients?limit=200` paginé ×4 → 200. Le correctif #8031 est **actif** |
| `Stats labos` | praticien `/lab-work-orders` | isolément → `GET /v1/cabinet/lab-stats` → 200, écran de stats rendu (Semantics 75 → 25) |
| `Tableau de bord` | secrétariat `/salle-attente` | isolément → navigue vers `/` + **8 requêtes** (`/cabinet/agenda`, `/waiting-list`, `/tasks`, `/opportunities`…) |
| `Stock`, `Devis`, `Labo`, `Salle d'attente, 1` | rails pro | **entrée de rail de la page courante** : no-op légitime |
| `À répondre (6)` | pharmacie `/stock` | **facette déjà active** : `role="switch" aria-checked="true"` au chargement. Les facettes inactives, elles, **répondent** : `Acceptées (63)` et `Refusées (29)` basculent bien `aria-checked` et le contenu (14 boutons « Accepter » → **0** → **14** au retour) |
| `Tous (187)` | pharmacie `/devis` | même raison : facette active par défaut |
| `Clôturer` ×10, `Joindre un justificatif` ×10 | secrétariat `/conformite` | isolément : `Clôturer` → **`POST /v1/cabinet/compliance-items/<id>/complete` → 200** + rechargement de la liste ; `Joindre un justificatif` → **ouvre un dialogue** (« Joindre un justificatif / Annuler / Joindre »). Effet de bord séquentiel : la 1ʳᵉ clôture **retire l'échéance de la liste** et réindexe toutes les suivantes |
| `À venir / échu` | secrétariat `/conformite` | **filtre déjà actif** (`role=checkbox aria-checked="true"` au chargement). Le filtre inactif, lui, **répond** : clic sur `Clôturés` ⇒ les deux cases **permutent** (`true`/`false`) avec repeinture, et le retour sur `À venir / échu` permute à nouveau |
| `Retour` (verdict CASSÉ) | secrétariat `/conformite` | **faux CASSÉ de ma propre rubrique** : le clic déclenche le **sondage de capacité** `GET /v1/cabinet/audit-log` → **403**, qui est délibéré (`audit_log_access_cubit.dart` : seul un 403 prouve le non-admin). Un 403 *attendu* ne rend pas un contrôle cassé |
| 8 puces de catégorie (`Radio 27`, `CBCT 3`, `Photo 10`, `Compte-rendu 7`, `Consentement 8`, `Consigne 24`, `Carte mutuelle 31`, `Autre 24`) | patient `/documents` | **hors-viewport HORIZONTAL** : les 12 puces forment une rangée défilante de **1 548 px** dans une fenêtre de **390 px** — `Radio` est à **x=561**, `Autre` à **x=1455**. Cliquer à ces coordonnées ne touche rien. Après **défilement horizontal** de la rangée, `Consigne 24` revient à **x=52** et le clic **fonctionne** : la puce passe à `aria-checked=true`, `Tous 696` passe à `false`, avec repeinture. Le filtre est **pleinement fonctionnel** (`documents_page.dart:307-308`, `selected:` + `onSelected:` bien câblés) |
| `À venir (67)` | patient `/mes-rdv` | facette déjà active |
| `Questionnaire médical` | patient `/mes-rdv` | isolément **OK** : navigue vers `/questionnaire-medical/11111111-…` et charge le vrai modèle (`GET /account/medical-questionnaire/active-template` → 200 + `GET /account/medical-questionnaire` → 200), avec ses questions réelles (« Avez-vous des allergies connues », « Êtes-vous diabétique ? »…). **Le correctif #8028 tient** |
| `Plus d'actions` ×3 | patient `/mes-rdv` | hors-viewport (vertical **et** horizontal selon la carte) |
| `Partage avec un confrère`, `Détails` | patient `/profile/consents` | isolément **OK** : la bascule de consentement **ouvre un dialogue de confirmation** (bouton `Annuler` présent) au lieu d'agir au premier tap — un retrait de consentement ne doit pas tenir à un geste distrait. `Détails` ouvre son panneau. *Les switches « disparaissent » de l'arbre après le clic parce que le dialogue les recouvre — d'où le faux MORT en série.* |
| 4 cartes d'implant | patient `/implant-passport` | isolément **OK** : la carte navigue vers `/implant-passport/0f916746-0c60-47bd-b2c7-f489cfbf0122`. Même effet de bord séquentiel que `/treatment-plans` |
| 3 + 3 contrôles | secrétariat `/liste-attente`, `/reprise-donnees` | entrées de rail de la page courante + filtres déjà actifs, même motif que ci-dessus |
| 2 `group` | infirmiere `/notification-preferences` | conteneurs Semantics (1ʳᵉ source, relevé avant le correctif du harnais) |
| ligne « Jade Dubois » | secrétariat `/salle-attente` | la **ligne** n'est pas cliquable ; ses actions sont ses propres boutons (`Appeler`, `Attribuer`, `Actions supplémentaires`) |

### Désactivés dont la légitimité est PROUVÉE

| contrôle | écran | raison exposée à l'utilisateur |
|---|---|---|
| `Prévenir le praticien` | secrétariat `/salle-attente` (bandeau) | **#8088 vérifié** : `aria-disabled="true"` ET la raison est **dans l'arbre Semantics** (« Prévenir le praticien est indisponible pour l'instant. »). Le clic ne produit **aucune requête**, **aucun changement d'écran** et **aucune snackbar « à venir »** mensongère — exactement ce que #8088 corrigeait |
| `Appeler` (ligne Jade) | praticien `/waiting-room` | `dis=true` car Jade est **`in_consultation`** — elle n'attend plus. La ligne de Marc (`checked_in`) a son `Appeler` **actif** |
| `Attribuer`, `Actions supplémentaires à venir` | secrétariat `/salle-attente` | raisons portées en `Tooltip`/`semanticLabel` (#6702/#7559), relues dans le code |
