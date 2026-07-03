# Synthèse design cible — refonte UI moderne (handoff agents)

> Source unique pour les issues de refonte UI. Extrait de `design/03-design-system/`,
> `design/mockups/` et `design/07-handoff/`. Objectif : amener les 3 apps Flutter
> à un design **moderne, premium, cohérent** (référence : Doctolib/Linear —
> cartes arrondies, whitespace généreux, accents émeraude, typo soignée).
>
> **Règle d'or** : aucune feature ne doit utiliser de widget Material brut
> (`ListTile`, `Card` par défaut, `OutlineInputBorder`, `ElevatedButton`…) là où
> un composant `nubia_design_system` existe. Toujours passer par le DS.

## 1. Design tokens (déjà dans `nubia_design_system`, à utiliser partout)

### Couleurs — marque Émeraude
`brand/700 #047857` = primaire (clair) · `brand/600 #059669` = identité/hover ·
`brand/400 #34D399` = primaire (sombre) · `brand/50 #ECFDF5` = fond subtil.

### Neutres chauds (Stone)
`n0 #FFFFFF` · `n50 #FAFAF9` (fond page) · `n100 #F5F5F4` · `n200 #E7E5E4`
(bordure subtile) · `n500 #78716C` (texte secondaire) · `n900 #1C1917` (texte principal).

### Sémantiques
success `#15803D`/bg `#DCFCE7` · warning `#B45309`/bg `#FEF3C7` ·
danger `#B91C1C`/bg `#FEE2E2` · info `#0E7490`/bg `#CFFAFE`.

### Typographie
- **Inter** (400/500/600) pour tout l'UI ; **Fraunces** (600) pour les grands titres héros / empty states premium uniquement.
- Échelle : display 32/40 · h1 28/36 · h2 24/32 · h3 20/28 · title 18/26 (500) · body-lg 16/26 · body 14/22 · label 14/20 (500) · caption 13/18 · micro 12/16 (500).
- Montants : `FontFeature.tabularFigures()`.

### Espacement (base 4) · Rayons · Ombres
- Marge écran **16**, padding carte 16 (mobile) / 24 (desktop), gap section 24–32.
- Rayons : boutons/inputs **8** (md), **cartes 12** (lg), sheets 16 (xl), pills/avatars 999.
- Ombres douces : `sm 0 1px 2px rgba(28,25,23,.05)` (cartes), `md 0 2px 8px rgba(28,25,23,.07)`, `lg 0 8px 24px rgba(28,25,23,.10)` (modales). En sombre : bordure subtile plutôt qu'ombre.
- Motion : 120 ms (hover), 200 ms (standard), 320 ms (entrée écran). Respecter `prefers-reduced-motion`.

## 2. Principes « moderne »
1. **Cartes** partout (radius 12, ombre sm, padding 16–24) au lieu de lignes brutes.
2. **Whitespace généreux** : respiration, pas de listes denses collées.
3. **Hiérarchie claire** : titre (h1/h2) + sous-titres + métadonnées en caption.
4. **Accent émeraude** cohérent (primaire, sélection, badges success).
5. **Jamais la couleur seule** : statut = icône + texte + couleur.
6. **États vides soignés** (icône 48 + titre + sous-texte + CTA) — jamais un écran vide.
7. **Skeletons** au chargement plutôt qu'un spinner nu.
8. **Contraste AA** (clair + sombre), **cibles tactiles ≥ 44px**, focus ring visible.

## 3. Composants DS à compléter/créer (fondation — bloque les écrans)

Existants (à utiliser) : `NubiaButton`, `NubiaTextField`, `NubiaChip`, `NubiaCard`,
`NubiaBadge`/StatusPill, `NubiaAvatar`, `NubiaAppBar`, `NubiaBottomNav`,
`NubiaEmptyState`, `NubiaSkeletonLoader`.

À créer (priorité Haute 🔴) :
- **ProviderCard** — résultat recherche : avatar + nom (title/500) + spécialité + badge RPPS + distance (caption) + dispo (badge success) + chevron. Interactive, min-h 84.
- **SlotChip** — créneau : ~36px, états dispo/sélectionné/indispo, clavier.
- **SearchBar** — loupe + input + chip lieu, 48px, suggestions.
- **ListRow** — leading (avatar/icône) + titre/sous-titre + trailing (badge/valeur/chevron), min-h 56, séparateur, état non-lu (point + poids).
- **QuoteCard / AmountHeader** — écran WEDGE (devis→signature→paiement) : montant h2 tabulaire, bandeau reste-à-charge `brand/50`, lignes actes alignées, CTA sticky, badges statut.
- **NubiaSelect / Dropdown**, **NubiaToggle/Checkbox/Radio** (consentements), **BottomSheet/Modal**, **Snackbar/Toast**, **MetricTile** (tuiles dashboard), **SegmentedControl** (À venir/Historique, liste/carte).

## 4. Direction par écran (mockups : `design/mockups/*.html`)

### Patient (`Nubia Patient.html`)
- **Recherche/annuaire** (`/appointments`, onglet racine) : SearchBar + carte + **ProviderCard** en liste (pas de ListTile brut).
- **Accueil/dashboard** : salutation, 3 **MetricTile** (à signer / à régler / prochain RDV), cloche notifs.
- **Réservation** : profil praticien (avatar lg, badge RPPS), **SlotChip** par jour (scroll H), étapes motif→créneau→confirmation, CTA sticky.
- **Mes RDV** : **SegmentedControl** À venir/Historique, cartes RDV avec badges statut + actions.
- **Messagerie** : **ListRow** (avatar + expéditeur + extrait + horodatage), badge urgent.
- **Documents** : liste par type avec icônes, cartes.
- **WEDGE financier** (le plus soigné) : **QuoteCard**/AmountHeader, signature, paiement, reçu (check animé).
- Profil, couverture santé, proches, notifications : formulaires DS (NubiaTextField/Select/Toggle), cartes.

### Praticien (`Nubia Back-office.html`, sidebar 240px / rail 72px / drawer mobile)
- Dashboard clinique (MetricTile production/agenda/patient suivant), agenda jour/semaine (pastilles statut), fiche patient (rows denses), consultation CCAM (saisie acte+dent+montant), plan/devis (QuoteCard), ordonnance, journal clinique.

### Secrétariat (même shell, ZÉRO clinique)
- Dashboard opérationnel (flux du jour), agenda cabinet, créneaux réservables, salle d'attente live, liste d'attente, devis, messagerie priorisée, fiche patient (admin only), admin membres.

## 5. Ordre recommandé
1. **Fondation DS** : compléter les composants §3 (ProviderCard, SlotChip, SearchBar, ListRow, QuoteCard, MetricTile, Select/Toggle, BottomSheet, Snackbar, SegmentedControl).
2. **Écrans patient** (les plus visibles) : recherche, réservation, mes-rdv, messagerie, WEDGE financier.
3. **Back-office** praticien puis secrétariat.

Chaque écran refondu doit : n'utiliser QUE des composants DS, respecter tokens/espacements, gérer les états loading (skeleton)/vide/erreur, passer `dart analyze` + tests, et rester fidèle au mockup correspondant.
