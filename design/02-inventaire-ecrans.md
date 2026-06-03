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
| Suivi & prévention (rappels) | 9 | E3.11 | 🟧/🎭 |
| Infos pratiques du cabinet | 12 | E3.12 | 🟧 |
| **(exclu)** téléconsult, chat IA, traduction, questionnaire intelligent, satisfaction | 13 | — | ❌ |

## Back-office (Flutter Web/Desktop) — praticien & secrétariat

| Écran | Rôle | Épic | Démo |
|---|---|---|---|
| Agenda cabinet (jour/semaine, créneaux) | S + D | E4.1 | 🟧 |
| Fiche patient (vue selon rôle) | S (admin) / D (clinique) | E4.2 | 🟧 |
| Création / suivi de devis (lignes CCAM) | D | E4.3 / E5.1 | 🟧 |
| File messagerie priorisée (triage visuel) | S + D | E4.4 | 🟧 |
| Liste d'attente / combler un trou | S | E4.5 | 🎭 |
| Salle d'attente live (WebSocket) | S + D | T16 | 🟧 |

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

> Maquettes : `mockups/nubia-marketplace.html`. Flux : `04-ux-flows/03-recherche-reservation.md`.

## Parcours critiques à dessiner en priorité
1. **Le wedge** : Praticien crée un devis → patient le **signe** in-app → **paie l'acompte** → cabinet voit l'alerte. Doit être le flux le plus fluide (cf. `../docs/03`, `../docs/06` E5.x).
2. **Onboarding patient** + première prise de RDV.
3. **Tableau de bord** patient (agrégé) et **tableau de bord** secrétariat (opérationnel).
4. **Scénario de démo investisseurs** : enchaînement scénarisé couvrant les 12 rubriques (cf. jalon GD, `../docs/02`).

## À produire ensuite
- Diagrammes de flux dans `04-ux-flows/`.
- Wireframes → maquettes (assets dans `assets/`).
- Tokens & composants dans `03-design-system/`.
