# Lot H — Dette & hygiène [R8]

> ⬅️ [Master](../../IMPLEMENTATION_PLAN.md) · [conventions](01-conventions.md) · [état réel](00-etat-reel.md)
> Continu / opportuniste. `H1` débloque le polish [F3](lot-f-polish.md).

## Détail fonctionnel

Refonte `HomeScreen` sur composants Nubia, nettoyage `billing/.gitkeep`, ajout deps `pubspec`, durcissement lints.

## Backlog atomique

| ID | Titre | Critères | Tests | → |
|----|-------|----------|-------|---|
| **H1** | `flutter(app): refonte HomeScreen sur composants Nubia (NubiaAppBar + NubiaSkeletonLoader + NubiaErrorWidget)` | plus d'`AppBar`/spinner bruts | widget (loading/error/loaded) | — |
| **H2** | `flutter(app): nettoyage data/remote/billing (.gitkeep) + arbo cohérente` | dossier propre | — | A2 |
| **H3** | `flutter(app): durcissement lints (very_good_analysis) + CI analyze --fatal-infos` | analyze vert sans warnings | — | — |
