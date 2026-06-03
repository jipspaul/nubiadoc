# Inventaire des écrans & flux

> Cartographie issue des specs (`../docs/06`) et du périmètre démo (`../docs/02`). Sert de base au design : chaque écran a un état **prod 🟧** / **démo mocké 🎭**, et une référence d'épic (`E3.x` / `E4.x` / `E5.x`).
> À valider/compléter avant de dessiner.

## App patient (Flutter mobile) — rubriques 1-12 du PDF

| Écran | Rubrique | Épic | Démo |
|---|---|---|---|
| Onboarding / connexion / profil | 3 | E3.1 | 🟧 |
| Tableau de bord (accueil) | 10 | E3.3 | 🟧 |
| Prise / modif / annulation de RDV | 1 | E3.2 | 🟧 |
| RDV à venir + historique | 1 | E3.2 | 🟧 |
| Messagerie cabinet (fil, urgent/non urgent, photos) | 2 | E3.4 | 🟧 |
| Dossier & coffre-fort (docs, radios, ordo) | 3, 11 | E3.5 | 🟧 |
| Signature de devis / consentement | 4 | E3.6 | 🟧 |
| Notifications (centre + réglages) | 5 | E3.7 | 🟧 |
| Espace financier (devis, factures, restant) | 6 | E3.8 | 🟧 |
| Échéancier / financement | 6 | E3.8 | 🎭 |
| Plan de traitement | 7 | E3.9 | 🎭 |
| Passeport implantaire (+ export PDF) | 8 | E3.10 | 🎭 |
| Suivi & prévention (rappels) | 9 | E3.11 | 🟧 |
| Infos pratiques du cabinet | 12 | E3.12 | 🟧 |
| **Couverture santé** (régime oblig. : Régime général / AME / CSS ex-CMU-C ; n° sécu ; mutuelle + n° adhérent ; photo carte recto/verso ; tiers payant) | 3 | E3.1 | 🟧 |
| **Mes proches / ayants droit** (enfants : chacun sa propre couverture) | 3 | E3.1 | 🟧 |
| **Recherche de RDV** (slot-centré : « 1re dispo », bandeau de jours, créneaux) | 1 | E3.2 / E5(marketplace) | 🟧 |
| **Préparer mon RDV** (adresse + plan, **itinéraire & temps de trajet** voiture/transports/à pied, à apporter, infos pratiques, check-in) | 1 | E3.2 | 🟧 |
| Wedge **complet** : signature → paiement/acompte → reçu (3 variations) | 4, 6 | E3.6 / E5.x | 🟧 (hi-fi ✅) |
| **(exclu MVP, réintégrés marketplace)** téléconsult ✅ marketplace · chat IA ❌ · traduction ❌ · questionnaire intelligent ❌ · satisfaction ❌ | 13 | — | ❌/marketplace |

## Back-office (Flutter Web/Desktop) — praticien & secrétariat

| Écran | Rôle | Épic | Démo |
|---|---|---|---|
| Agenda cabinet (jour/semaine, créneaux) | S + D | E4.1 | 🟧 |
| Fiche patient (vue selon rôle) | S (admin) / D (clinique) | E4.2 | 🟧 |
| Création / suivi de devis (lignes CCAM) | D | E4.3 / E5.1 | 🟧 |
| File messagerie priorisée (triage visuel) | S + D | E4.4 | 🟧 |
| Liste d'attente / combler un trou | S | E4.5 | 🎭 |
| Salle d'attente live (WebSocket) | S + D | T16 | 🟧 |
| **Tableau de bord praticien** (journée clinique : agenda, patient suivant + alertes, à valider, production) | D | E4.6 | 🟧 (hi-fi ✅) |
| **Mes patients** (index des dossiers suivis : plan en cours, prochain RDV, solde, alertes) | D | E4.6 | 🟧 |
| **Consultation au fauteuil** (cœur clinique : contexte, **saisie d'actes CCAM**, note de séance, enchaînements) | D | E4.7 | 🟧 |
| **Plan de traitement & devis** (phases, chiffrage, base Sécu/mutuelle, **reste à charge**, acompte, envoi) | D | E4.3 / E5.1 | 🟧 |
| **Ordonnance / prescription** (document, signature électronique, envoi pharmacie) ⚠️ blocage allergie/interactions = **hors scope MDR** (cf. `../docs/07` §8) | D | E4.8 | 🟧 (display only) |
| **Journal clinique** (notes manuelles **globales** + **liées à un acte/dent**, horodatées, secret médical) | D | E4.2 | 🟧 (hi-fi ✅) |
| **App praticien — onboarding** : création de compte (rôle Praticien/Secrétariat), **inscription au service + vérification RPPS**, profil public & ouverture de créneaux | D/S | E4.9 | 🟧 |

> **Deux paradigmes de back-office** : V1 sidebar (`mockups/Nubia Back-office.html`) et V2 « Spotlight » command-palette + assistant (`mockups/Nubia Spotlight.html`). Voir `08-back-office-v2-spotlight.md`. À trancher.

## Marketplace (face patient découverte — cf. `../docs/11`)

| Écran | Rôle | Story | Démo |
|---|---|---|---|
| Recherche (barre multi-axes + lieu) | Patient | US-M01→M05 | 🟧 |
| Résultats + filtres | Patient | US-M06, M07 | 🟧 |
| Filtres (facettes) | Patient | US-M06 | 🟧 |
| Carte (pins + « rechercher dans cette zone ») | Patient | US-M08 | 🟧 |
| Profil praticien (dispos, prendre RDV) | Patient | US-M09, M10 | 🟧 |
| Réservation (motif → créneau → confirm) | Patient | US-M11 | 🟧 |
| Salle d'attente virtuelle (position file) | Patient | US-M14 | 🟧 |
| Check-in (QR / « je suis arrivé ») | Patient | US-M16 | 🟧 |
| Téléconsultation (salle d'attente + vidéo) | Patient | US-M17 | 🟧 |
| Notif « bientôt à vous » | Patient | US-M15 | 🟧 |
| Profil public + créneaux en ligne | Praticien | US-M18, M19 | 🟧 |
| Pilotage file d'attente | Praticien/Secr. | US-M20 | 🟧 |

> Maquettes hi-fi : `mockups/Nubia Patient.html`, `mockups/Nubia Back-office.html`, `mockups/Nubia Spotlight.html`, `mockups/Nubia Comparatif.html` (index : `mockups/README.md`). Flux : `04-ux-flows/03-recherche-reservation.md`.

## Parcours critiques à dessiner en priorité
1. **Le wedge** : Praticien crée un devis → patient le **signe** in-app → **paie l'acompte** → cabinet voit l'alerte. Doit être le flux le plus fluide (cf. `../docs/03`, `../docs/06` E5.x).
2. **Onboarding patient** + première prise de RDV.
3. **Tableau de bord** patient (agrégé) et **tableau de bord** secrétariat (opérationnel).
4. **Scénario de démo investisseurs** : enchaînement scénarisé couvrant les 12 rubriques (cf. jalon GD, `../docs/02`).

## À produire ensuite
- Diagrammes de flux dans `04-ux-flows/`.
- Wireframes → maquettes (assets dans `assets/`).
- Tokens & composants dans `03-design-system/`.
