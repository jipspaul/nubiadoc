# Flux — Marketplace : recherche → réservation → salle d'attente

> Face **patient/marketplace** (cf. `../../docs/11`). Le patient a **un compte global** et peut trouver/réserver chez **n'importe quel praticien**. Maquettes : `../mockups/nubia-marketplace.html`.
> Couvre US-M01→M17.

## Objectif
Permettre à un patient de **trouver le bon soignant** (par adresse, GPS, nom, spécialité ou besoin), de **réserver** en quelques taps, puis de vivre un **jour J fluide** (salle d'attente virtuelle, ou téléconsultation).

## 1. Recherche (US-M01→M05)
- **Barre unique** + sélecteur de **lieu** (« autour de moi » via GPS, ou saisie d'adresse/ville/CP).
- Saisie libre interprétée multi-axes : nom de praticien, profession/spécialité, établissement, **ou besoin** (« mal de dent » → suggère « chirurgien-dentiste · urgence »).
- Aides : spécialités populaires, recherches récentes, géoloc opt-in.
- **États** : géoloc refusée (fallback saisie adresse), aucun résultat (élargir le rayon / autre spécialité), suggestion d'orthographe.
- **Garde-fou** : le besoin **oriente vers une spécialité**, ne **diagnostique pas** (cf. `../../docs/07` §8).

## 2. Résultats — liste & filtres (US-M06, M07)
- Carte praticien : photo, nom, spécialité **(vérifiée RPPS)**, distance, prochaine dispo, secteur/tarif, badges (téléconsult, tiers payant, PMR).
- **Filtres** : disponibilité, distance, secteur 1/2/3, tiers payant, téléconsultation, PMR, langues, accepte nouveaux patients, prix.
- **Tri** : pertinence · distance · prochaine dispo · avis (tri **transparent**, neutralité — cf. `../../docs/11` §11).
- Bascule **liste ⇄ carte**.

## 3. Carte (US-M08)
- Pins par praticien/établissement, **clustering** au dézoom, bouton « **rechercher dans cette zone** ».
- Tap sur un pin → mini-carte praticien → profil.
- Fond de carte **européen/souverain**.

## 4. Profil praticien (US-M09, M10)
- En-tête : photo, nom, spécialité vérifiée, adresse + mini-carte, secteur & tarifs, langues, PMR, présentation.
- **Calendrier de disponibilités** (prochains créneaux), avis, **« Prendre RDV »**.
- **États** : aucune dispo en ligne (proposer liste d'attente / autre praticien), praticien ne prenant pas de nouveaux patients (message clair).

## 5. Réservation (US-M11)
- **Motif** → **créneau** → (nouveau patient : minimum d'infos + consentements) → **confirmation** → pré-check-in proposé.
- Le RDV apparaît dans l'**espace patient global** ; le cabinet le reçoit dans son back-office (tenant).
- **États/erreurs** : créneau pris entre-temps (réafficher dispos), session expirée, double réservation évitée.

## 6. Salle d'attente virtuelle (US-M14→M16)
- **Avant le RDV** : rappel + pré-check-in (questionnaire, mutuelle).
- **Jour J** : check-in (QR / app / « je suis arrivé » géofencing opt-in) → **file virtuelle** : position + **temps estimé** + notif « **c'est bientôt à vous** ».
- Présentiel : la file alimente la **salle d'attente live** du cabinet (WebSocket).
- **États** : retard signalé, appelé (« c'est à vous, salle 2 »), file qui avance.

## 7. Téléconsultation (US-M17)
- RDV vidéo : **salle d'attente virtuelle** jusqu'au démarrage par le praticien → appel vidéo (WebRTC EU) → après : ordonnance/CR dans le coffre-fort, paiement/tiers payant.
- **États** : attente, praticien prêt, problème réseau (reprise), fin de consultation.

## Accessibilité (US-X01) & garde-fous
- Recherche et carte utilisables au clavier + lecteur d'écran ; cibles ≥ 44 px ; alternatives textuelles aux pins.
- Géoloc **opt-in** (RGPD) ; avis **modérés** et rattachés à un vrai RDV ; **neutralité** du tri.
- Aucune promesse/décision clinique (orientation spécialité uniquement).

## Stories couvertes → statut
US-M01→M11, M14, M17 : maquette ✅ (`../mockups/nubia-marketplace.html`). M07, M12, M13, M15, M16, M18→M20 : 🎨 (à affiner).

> Côté praticien (annuaire) : gérer profil public, ouvrir des créneaux en ligne, piloter la file (US-M18→M20) — à détailler dans le back-office.
