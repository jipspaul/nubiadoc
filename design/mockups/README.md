# Maquettes hi-fi — Nubia

> Maquettes **hi-fi interactives** issues de Claude Design (claude.ai/design), itérées avec Xav puis exportées comme handoff. Provenance (transcripts + README de handoff d'origine) dans `_provenance/`.
> Medium = HTML/CSS/JS (prototypes), pas du code de prod. Cible d'implémentation = **Flutter + Bloc** (cf. `../03-design-system/03-flutter-theme.md`). On reproduit le **rendu**, pas la structure interne du proto.
> ⚠️ Design system appliqué : émeraude `#047857`, neutres pierre, Inter (+ Fraunces côté patient), clair **et** sombre, arrondi doux (cf. `../03-design-system/`).

## Les 4 fichiers

| Fichier | Cible | Contenu |
|---|---|---|
| **`Nubia Patient.html`** | App patient (mobile, cadre iPhone) | Les 5 onglets + le **wedge de bout en bout** (devis → signature → paiement → reçu) en 3 variations (A sobre, B premium sable, C reste-à-charge-first), réservation (motif → créneau → confirmation), **recherche de RDV** (slot-centré) + **préparer mon RDV** (adresse, itinéraire, temps de trajet, à apporter, infos pratiques), onboarding/connexion (téléphone / FranceConnect), profil, **couverture santé** (régime obligatoire AME/CSS, mutuelle, carte recto/verso, tiers payant), **mes proches / ayants droit**, notifications, plan de traitement, passeport implantaire, suivi & prévention. |
| **`Nubia Back-office.html`** | Back-office (desktop/tablette, cadre fenêtre navigateur) | **Version 1 = sidebar classique.** Secrétariat : tableau de bord (3 directions A/B/C) enrichi (flux du jour, encaissements de la semaine), agenda, fiche patient **administrative** (cloisonnement : dossier clinique masqué), suivi devis & paiements, liste d'attente. Praticien : tableau de bord clinique, **mes patients**, **consultation au fauteuil** (saisie CCAM, note de séance), **plan de traitement & devis**, **ordonnance**, fiche clinique (odontogramme + **journal clinique** notes globales/par acte), salle d'attente live. **App praticien** : création de compte, **inscription au service avec vérification RPPS**, profil public & ouverture de créneaux. |
| **`Nubia Spotlight.html`** | Back-office **Version 2** (prototype vivant) | Paradigme **command-palette façon Spotlight macOS** : barre de recherche translucide centrée (autofocus, navigation clavier ↑/↓/Entrée/Échap, ⌘K), ouverture des **mêmes écrans que la V1 sans sidebar** en **plein écran par défaut**, réductibles en fenêtre, multi-fenêtres, **dock** qui se remplit des vues ouvertes. Premier résultat = **« Demander à Nubia »** (assistant langage naturel : résumés, relances, chiffres du jour, vues personnalisées). Contrôles de fenêtre **maison** (pas les pastilles Apple). |
| **`Nubia Comparatif.html`** | Aide à la décision | Écrans **figés** organisés **par user story**, V1 (sidebar) ⟷ V2 (plein écran) ⟷ V2 (fenêtré/multi) côte à côte. Sert à trancher entre les deux paradigmes back-office. Chargement paresseux (lazy-mount). |

## Décision ouverte
Le back-office a **deux propositions de paradigme** (V1 sidebar / V2 Spotlight). **À trancher avec Xav** (cf. `../08-back-office-v2-spotlight.md`). La V1 est validée comme base ; la V2 est une alternative différenciante (recherche + assistant en cœur de navigation).

## Fichiers techniques
`lib/` (tokens.css + modules d'écrans), `design-canvas.jsx`, `ios-frame.jsx`, `browser-window.jsx` = dépendances des `.html`. Les captures d'écran d'origine ne sont pas versionnées (poids) ; régénérables en ouvrant les `.html`.
