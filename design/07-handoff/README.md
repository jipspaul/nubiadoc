# Handoff dev — package complet

> Documentation de passation **prête à builder** l'app Nubia (Flutter Material 3 + Bloc). Équivaut à un dossier de specs Figma : fondations, bibliothèque de composants, specs écran, critères d'acceptation, edge cases, a11y.
> Source de vérité visuelle : `../03-design-system/` (tokens + thème Dart). Univers & navigation : `../ia-navigation.md`. Stories : `../user-stories.md`.

## Contenu
| Fichier | Contenu |
|---|---|
| [`00-fondations.md`](./00-fondations.md) | Grille & breakpoints (mobile + back-office), spacing px, type px exacte, couleurs/rôles, rayons/élévation, motion, iconographie, **a11y baseline**, contenu/i18n, naming dev. |
| [`01-composants.md`](./01-composants.md) | **22 composants** spécifiés (anatomie, mesures px, variantes, états, props Flutter `Nubia*`, interaction, a11y, do/don't). |
| [`02-ecrans.md`](./02-ecrans.md) | Specs écran par écran (Recherche, Profil/réservation, Wedge, Mes RDV/salle d'attente/téléconsult, Messagerie, Back-office) : layout, tokens, composants, états/interactions, responsive, **edge cases**, motion, a11y + **critères d'acceptation Gherkin**. |

## Maquettes de référence (à ouvrir au navigateur)
- ⭐ `../mockups/nubia-univers.html` — l'univers complet unifié (toutes les rubriques, nav commune).
- `../mockups/nubia-hifi.html` — **hi-fi + écran annoté « inspect »** (mesures + tokens), niveau handoff.
- Vues détaillées : `../mockups/nubia-maquettes.html`, `../mockups/nubia-marketplace.html`.

## Comment l'utiliser (côté dev)
1. Lire `00-fondations.md` → poser le thème (déjà en Dart dans `../03-design-system/03-flutter-theme.md`).
2. Construire la **bibliothèque `Nubia*`** depuis `01-composants.md` (un widget = un composant, avec ses états).
3. Implémenter écran par écran avec `02-ecrans.md` (chaque écran = `*Page` + `*Bloc`), en validant les **critères d'acceptation**.
4. Tests : widget tests par composant/état, `bloc_test` par Bloc, golden tests sur les écrans clés, intégration sur les parcours (wedge, recherche→réservation).

## Statut & limites
- Les **écrans prioritaires** sont spécifiés en détail. Les écrans secondaires (onboarding, profil/compte, suivi, plan/passeport, espace financier) suivent le **même gabarit + la bibliothèque** — à compléter à l'implémentation.
- Ce handoff est **vivant** : à enrichir avec la microcopy (`../05-ux-copy/`) et l'audit a11y formel (`../06-accessibilite/`).
