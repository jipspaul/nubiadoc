# Design System

> Direction retenue : **premium / esthétique** · primaire **vert santé (émeraude)** · **clair + sombre** · **angles arrondis doux**.
> Construit avec la skill `design-system`. Pensé pour se traduire direct en **widgets Flutter**.

| Fichier | Contenu |
|---|---|
| [`01-tokens.md`](./01-tokens.md) | Couleurs (ramps marque/neutres/sémantiques, rôles light/dark, contrastes AA), typographie (Inter + Fraunces), espacements, rayons, ombres, motion. |
| [`02-composants.md`](./02-composants.md) | Composants cœur (Button, Input, Card, Badge statut, Tuile dashboard, Message row, Agenda slot, Carte devis) : variantes, états, accessibilité. |
| [`03-flutter-theme.md`](./03-flutter-theme.md) | Implémentation Flutter : `ColorScheme` + `ThemeData` clair/sombre + `ThemeExtension NubiaTokens` + constantes + `google_fonts`. |

Contraintes tenues : cohérent sur les 3 rôles (patient mobile + back-office desktop), **accessible AA** (contrastes vérifiés), lisible en data-dense côté cabinet, couleur jamais porteuse seule d'une information.

Prochaines étapes design : appliquer ces composants aux **flux clés** (`../04-ux-flows/`, en commençant par le wedge), puis la **copy** (`../05-ux-copy/`) et l'**audit a11y** (`../06-accessibilite/`).
