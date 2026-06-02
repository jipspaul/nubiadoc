# Design System

> À construire avec la skill **`design-system`**. Objectif : des tokens et composants qui se traduisent proprement en **widgets Flutter** (thème + composants Bloc-friendly).

À produire ici :
- **Tokens** : couleurs (+ thème clair/sombre), typographie, échelle d'espacements, rayons, ombres, états.
- **Composants** : boutons, champs, cartes, listes, badges (urgent/statut), tuiles de dashboard, fil de messagerie, ligne d'agenda, carte de devis.
- **États** : default / hover / focus / disabled / loading / erreur / vide.
- **Mapping Flutter** : nom du token → `ThemeData` / constantes ; un composant = un widget réutilisable.

Contraintes : cohérent sur les 3 rôles (patient mobile + back-office desktop), accessible (contrastes AA), lisible en data-dense côté cabinet.
