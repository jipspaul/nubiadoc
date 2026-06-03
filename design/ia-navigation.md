# Architecture d'information — l'univers patient unique

> **Clarification fondatrice.** Nubia côté patient = **UN seul univers** : la marketplace (découverte de n'importe quel praticien) **et** l'espace personnel (RDV, documents, devis, messagerie, salle d'attente, téléconsult) sont **la même app**. La découverte est la porte d'entrée ; l'espace perso en est la profondeur. Pas deux applications.
> Ce doc fixe la **navigation unique** et **mappe toutes les user stories** (cf. `user-stories.md`, `../docs/11`).

## 1. Principe
- **Compte unique, global** (`PatientAccount`) : un patient, tous les praticiens.
- **Front door = recherche** (façon Doctolib) : on ouvre l'app pour trouver/réserver.
- **Profondeur = espace perso** : tout ce qui me concerne, agrégé tous praticiens confondus.
- **Continuité** : trouver → réserver → vivre le RDV (salle d'attente / téléconsult) → garder (docs, devis, suivi) — sans rupture, dans la même app.

## 2. Navigation unique (bottom nav — 5 entrées)

| Onglet | Rôle | Écrans | User stories |
|---|---|---|---|
| **Accueil / Rechercher** | Découverte (marketplace) + accès rapide au prochain RDV | Recherche multi-axes, résultats, filtres, **carte**, profil praticien, réservation | US-M01→M13 + raccourci US-P13 |
| **Mes RDV** | Tous mes RDV (tous praticiens), à venir + historique, prise/gestion, **salle d'attente virtuelle**, **téléconsult** | Mes RDV, détail RDV, salle d'attente, check-in, téléconsult, liste d'attente | US-P07→P12, US-M12, US-M14→M17 |
| **Messages** | Messagerie avec les cabinets | Fil, conversation, pièces jointes | US-P15, US-P16 |
| **Documents** | Coffre-fort + finances + parcours de soins | Coffre-fort, devis/**signature**, **paiement/acompte**, espace financier, plan de traitement, passeport | US-P17→P26 |
| **Profil** | Compte global & santé | Infos admin, **couverture santé** (régime oblig./AME/CSS, mutuelle, carte, tiers payant), **mes proches/ayants droit**, consentements, questionnaire, suivi/prévention, infos cabinets, **avis**, réglages, notifications | US-P01→P06, US-P27→P30, US-P28, US-M13, US-P14 |

> Le **tableau de bord** (US-P13 « actions à réaliser ») vit en tête de l'**Accueil** (au-dessus/à côté de la recherche) : à signer, à régler, prochain RDV, messages non lus — pour ne rien rater dès l'ouverture.

## 3. Parcours transverses (traversent les onglets)
- **Découverte → réservation** : Accueil → résultats/carte → profil → réservation → (confirmation) → apparaît dans **Mes RDV**.
- **Jour J** : Mes RDV → check-in → **salle d'attente virtuelle** → (présentiel : « c'est à vous » / distanciel : **téléconsult**).
- **Wedge financier** : un devis poussé par le cabinet → notif → **Documents** → signature → acompte → reçu.
- **Suivi** : rappel prévention (Profil/notif) → re-réservation (Accueil) — la boucle d'engagement.

## 4. Les autres faces (même produit, autres publics)
- **Annuaire public (web non connecté)** : les profils praticiens + recherche sont **aussi accessibles sans compte** (SEO/partage) → incitation à créer un compte pour réserver. Même contenu que l'onglet Accueil, en public.
- **Back-office cabinet** (praticien/secrétariat) : app séparée (desktop/tablette) côté pro — agenda, fiche patient, devis, messagerie, **profil public** & ouverture de créneaux, **pilotage de la file** (US-S*, US-D*, US-M18→M20). C'est l'autre face de la marketplace.
  - **Onboarding pro en self-service** : le pro **crée son compte et inscrit son cabinet** avec **vérification RPPS/ADELI** (le modèle « patient invité par son cabinet » est complété par une inscription B2B autonome). Le tableau de bord permet la création de comptes (rôles Praticien/Secrétariat). Cf. US-D07, `08-back-office-v2-spotlight.md`.
  - **Cœur praticien** : tableau de bord clinique, mes patients, **consultation au fauteuil** (CCAM), **plan & devis**, **ordonnance**, **journal clinique**.
  - **Deux paradigmes de navigation à l'étude** : **V1 sidebar** (validée) et **V2 « Spotlight »** (command-palette + assistant « Demander à Nubia »). Détail et arbitrage : `08-back-office-v2-spotlight.md`.

## 5. Couverture des user stories (check complet)
- **Patient perso** US-P01→P28 : répartis Accueil/RDV/Messages/Documents/Profil (voir §2). ✅ tous logés.
- **Marketplace** US-M01→M17 : Accueil (recherche/carte/profil/réservation) + Mes RDV (salle d'attente/téléconsult). ✅
- **Praticien/annuaire** US-M18→M20 + US-S*/US-D* : back-office. ✅
- **Transverse** US-X01→X04 : a11y, cloisonnement, états, démo — appliqués partout. ✅

## 6. Conséquence design
- **Une seule maquette de référence** : `mockups/nubia-univers.html` (remplace la séparation patient/marketplace). Les deux fichiers précédents (`nubia-maquettes.html`, `nubia-marketplace.html`) restent comme vues détaillées, mais **l'univers unifié fait foi**.
- Nav commune visible sur **chaque** écran patient → sentiment d'une seule app.
- Cohérence design system (émeraude, arrondi doux) sur toute la traversée.

> Maquette unifiée : `mockups/nubia-univers.html`. Flux : `04-ux-flows/`. Stories : `user-stories.md`. Scope : `../docs/11`.
