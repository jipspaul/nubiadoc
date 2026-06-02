# User stories — produit Nubia (base du design)

> **Toutes** les user stories du produit, telles qu'on sait aujourd'hui ce qu'il sera (cf. `../docs/06` specs, `02-inventaire-ecrans.md`, PDF patient). Formulées côté utilisateur : *En tant que… je veux… afin de…*.
> ⭐ **L'app patient est UN seul univers** (marketplace + espace perso) — voir `ia-navigation.md`. Maquette unifiée de référence : [`mockups/nubia-univers.html`](./mockups/nubia-univers.html). Flux : `04-ux-flows/`.

## Conventions
- **ID** : `US-P` (patient), `US-S` (secrétariat), `US-D` (praticien), `US-X` (transverse).
- **Prio** : 🟧 prod · 🎭 démo (mocké) · ❌ exclu MVP.
- **Statut design** : ⬜ à concevoir · 🎨 flux fait (maquette partielle/à affiner) · ✅ maquette hi-fi faite.

---

## A. Patient — Onboarding, compte & consentements

| ID | User story | Prio | Écran | Design |
|---|---|---|---|---|
| US-P01 | Créer mon compte (e-mail + mot de passe), afin d'accéder à mon espace. | 🟧 | Onboarding | ✅ |
| US-P02 | Me connecter (biométrie), afin de retrouver mes données vite. | 🟧 | Connexion | ✅ |
| US-P03 | Accepter CGU et donner mes consentements, afin d'utiliser le service en confiance. | 🟧 | Consentements | 🎨 |
| US-P04 | Mettre à jour mes infos administratives (coordonnées, sécu, mutuelle). | 🟧 | Profil | 🎨 |
| US-P05 | Remplir le questionnaire médical, afin que le praticien ait mes antécédents. | 🟧 | Questionnaire | 🎨 |
| US-P06 | Gérer mes préférences de notifications. | 🟧 | Réglages | 🎨 |

## B. Patient — Rendez-vous

| ID | User story | Prio | Écran | Design |
|---|---|---|---|---|
| US-P07 | Voir les créneaux et prendre RDV en ligne, afin d'éviter d'appeler. | 🟧 | Prise de RDV | ✅ |
| US-P08 | Modifier ou annuler un RDV (dans les délais). | 🟧 | RDV | 🎨 |
| US-P09 | Voir mes RDV à venir et mon historique. | 🟧 | Mes RDV | ✅ |
| US-P10 | Recevoir des rappels automatiques avant mon RDV. | 🟧 | Notifications | 🎨 |
| US-P11 | Demander à être rappelé par le cabinet. | 🟧 | RDV | 🎨 |
| US-P12 | M'inscrire sur liste d'attente pour un créneau libéré. | 🎭 | Liste d'attente | 🎨 |

## C. Patient — Tableau de bord & notifications

| ID | User story | Prio | Écran | Design |
|---|---|---|---|---|
| US-P13 | Un tableau de bord à l'ouverture (RDV, à signer/régler, messages, actions). | 🟧 | Tableau de bord | ✅ |
| US-P14 | Recevoir des notifications utiles sans données sensibles. | 🟧 | Notifications | 🎨 |

## D. Patient — Messagerie

| ID | User story | Prio | Écran | Design |
|---|---|---|---|---|
| US-P15 | Écrire au cabinet et joindre photos/documents. | 🟧 | Messagerie | ✅ |
| US-P16 | Voir le classement urgent/non urgent et recevoir les réponses. | 🟧 | Messagerie | ✅ |

## E. Patient — Dossier, documents & signature

| ID | User story | Prio | Écran | Design |
|---|---|---|---|---|
| US-P17 | Consulter mes documents par catégorie. | 🟧 | Coffre-fort | ✅ |
| US-P18 | Télécharger un document. | 🟧 | Coffre-fort | ✅ |
| US-P19 | Signer électroniquement un devis/consentement. | 🟧 | Signature | ✅ |
| US-P20 | Voir l'historique de mes signatures. | 🟧 | Signature | 🎨 |

## F. Patient — Espace financier (wedge côté patient)

| ID | User story | Prio | Écran | Design |
|---|---|---|---|---|
| US-P21 | Consulter devis/factures et le reste à régler. | 🟧 | Espace financier | ✅ |
| US-P22 | Payer un acompte en ligne (CB, Apple/Google Pay). | 🟧 | Paiement | ✅ |
| US-P23 | Voir mes échéances et recevoir des rappels de paiement. | 🎭 | Échéancier | ✅ |
| US-P24 | Souscrire un financement fractionné. | 🎭 | Financement | 🎨 |

## G. Patient — Suivi, plan de traitement, passeport, infos

| ID | User story | Prio | Écran | Design |
|---|---|---|---|---|
| US-P25 | Visualiser mon plan de traitement (faits/restants, coût, reste à charge). | 🎭 | Plan de traitement | ✅ |
| US-P26 | Consulter/télécharger mon passeport implantaire. | 🎭 | Passeport | ✅ |
| US-P27 | Recevoir des rappels de suivi/prévention. | 🟧 | Suivi & prévention | ✅ |
| US-P28 | Consulter les infos pratiques du cabinet. | 🟧 | Infos cabinet | ✅ |

---

## H. Secrétariat — Agenda, accueil, opérationnel

| ID | User story | Prio | Écran | Design |
|---|---|---|---|---|
| US-S01 | Voir et gérer l'agenda du cabinet. | 🟧 | Agenda cabinet | ✅ |
| US-S02 | Un tableau de bord opérationnel (RDV du jour, tâches, urgences). | 🟧 | Dashboard cabinet | ✅ |
| US-S03 | Gérer la liste d'attente et combler un trou. | 🎭 | Liste d'attente | 🎨 |
| US-S04 | Voir la fiche patient (volet administratif uniquement). | 🟧 | Fiche patient | 🎨 |
| US-S05 | Voir la salle d'attente en temps réel. | 🟧 | Salle d'attente live | ✅ |

## I. Secrétariat — Messagerie & relances

| ID | User story | Prio | Écran | Design |
|---|---|---|---|---|
| US-S06 | Une file de messages priorisée (urgents en tête). | 🟧 | Messagerie cabinet | ✅ |
| US-S07 | Répondre et convertir un message en RDV en 1 clic. | 🟧 | Messagerie cabinet | ✅ |
| US-S08 | Suivre les devis/paiements et relancer. | 🟧 | Suivi devis/paiements | 🎨 |

---

## J. Praticien — Clinique & devis

| ID | User story | Prio | Écran | Design |
|---|---|---|---|---|
| US-D01 | Voir mon agenda et le patient à l'arrivée. | 🟧 | Agenda | ✅ |
| US-D02 | Consulter la fiche patient complète (clinique). | 🟧 | Fiche patient | 🎨 |
| US-D03 | Créer/éditer un devis (lignes CCAM, AMO/AMC). | 🟧 | Création devis | ✅ |
| US-D04 | Envoyer le devis au patient pour signature. | 🟧 | Devis | ✅ |
| US-D05 | Voir le statut signature/paiement d'un devis. | 🟧 | Suivi devis | ✅ |
| US-D06 | Traiter les messages escaladés (niveau 3). | 🟧 | Messagerie | 🎨 |

---

## K. Transverse (toutes personas)

| ID | User story | Prio | Écran | Design |
|---|---|---|---|---|
| US-X01 | Interface claire, lisible et accessible (AA). | 🟧 | tous | 🎨 |
| US-X02 | Le secrétariat n'accède pas au contenu clinique. | 🟧 | rôles | ✅ |
| US-X03 | États vides, chargement et erreur soignés. | 🟧 | tous | 🎨 |
| US-X04 | Parcours démo scénarisé couvrant les 12 rubriques. | 🎭 | démo | 🎨 |

---

# MARKETPLACE — découverte & réservation globale
> Scope étendu (cf. `../docs/11`). `US-M` = patient marketplace. Le patient a **un compte unique** pour tous les praticiens/professions.

## L. Patient — Recherche d'un praticien

| ID | User story | Prio | Écran | Design |
|---|---|---|---|---|
| US-M01 | En tant que patient, je veux rechercher par **nom de praticien**, afin de retrouver un soignant précis. | 🟧 | Recherche | ✅ |
| US-M02 | …par **profession/spécialité** (dentiste, cardiologue, kiné…), afin de trouver le bon type de soignant. | 🟧 | Recherche | ✅ |
| US-M03 | …par **adresse/ville/code postal**, afin de chercher près d'un lieu donné. | 🟧 | Recherche | ✅ |
| US-M04 | …par **position GPS (autour de moi)**, afin de trouver au plus proche. | 🟧 | Recherche / Carte | ✅ |
| US-M05 | …par **besoin médical** en langage naturel (« mal de dent »), afin d'être orienté vers la bonne spécialité (sans diagnostic). | 🟧 | Recherche | ✅ |
| US-M06 | Filtrer les résultats (dispo, distance, secteur, tiers payant, téléconsult, PMR, langues, nouveau patient). | 🟧 | Résultats | ✅ |
| US-M07 | Trier (pertinence, distance, prochaine dispo, avis). | 🟧 | Résultats | 🎨 |
| US-M08 | Voir les résultats sur une **carte** avec pins et « rechercher dans cette zone ». | 🟧 | Carte | ✅ |

## M. Patient — Profil praticien & réservation

| ID | User story | Prio | Écran | Design |
|---|---|---|---|---|
| US-M09 | Consulter le **profil public** d'un praticien (spécialité vérifiée, adresse, tarifs/secteur, actes, horaires, langues, présentation). | 🟧 | Profil praticien | ✅ |
| US-M10 | Voir les **prochaines disponibilités** et choisir un créneau. | 🟧 | Profil / Réservation | ✅ |
| US-M11 | **Réserver** chez n'importe quel praticien (motif → créneau → confirmation), même nouveau patient. | 🟧 | Réservation | ✅ |
| US-M12 | Retrouver dans mon **espace patient global** tous mes RDV, tous praticiens confondus. | 🟧 | Mes RDV | 🎨 |
| US-M13 | Laisser/consulter un **avis** rattaché à un vrai RDV (modéré). | 🟧 | Avis | 🎨 |

## N. Patient — Salle d'attente virtuelle & téléconsultation

| ID | User story | Prio | Écran | Design |
|---|---|---|---|---|
| US-M14 | Voir ma **position dans la file** et le temps d'attente estimé le jour du RDV. | 🟧 | Salle d'attente virtuelle | ✅ |
| US-M15 | Recevoir une notif « **c'est bientôt à vous** » (5-10 min avant). | 🟧 | Notifications | 🎨 |
| US-M16 | Faire mon **check-in** à l'arrivée (QR / app / « je suis arrivé »). | 🟧 | Check-in | 🎨 |
| US-M17 | Réaliser une **téléconsultation vidéo** (avec salle d'attente virtuelle en amont). | 🟧 | Téléconsultation | ✅ |

## O. Praticien/cabinet — Côté annuaire

| ID | User story | Prio | Écran | Design |
|---|---|---|---|---|
| US-M18 | En tant que praticien, je veux **gérer mon profil public** (présentation, actes, tarifs, langues, photos), afin d'être bien référencé. | 🟧 | Profil (back-office) | 🎨 |
| US-M19 | …**ouvrir certains créneaux à la réservation en ligne**, afin de remplir mon agenda. | 🟧 | Agenda (back-office) | 🎨 |
| US-M20 | …**piloter ma file d'attente virtuelle** (appeler le suivant), afin de fluidifier l'accueil. | 🟧 | Salle d'attente (back-office) | 🎨 |

---

## Vue d'ensemble
- **Maquettes hi-fi livrées** (`mockups/nubia-maquettes.html`) : ~15 écrans patient + 4 écrans back-office, design system émeraude appliqué.
- **Flux écrits** : wedge (`04-ux-flows/01`) + parcours restants (`04-ux-flows/02`).
- **Reste à affiner (🎨)** : écrans secondaires (consentements, questionnaire, réglages, historique signatures, financement, fiche patient détaillée), microcopy (`05-ux-copy/`), audit a11y (`06-accessibilite/`), handoff (`07-handoff/`).

> Prochaine itération : critique design (`design-critique`), microcopy FR, audit accessibilité, puis handoff dev Flutter.
