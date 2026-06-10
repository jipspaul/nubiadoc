# Lot D — Marketplace / Recherche (E5.x) [R4]

> ⬅️ [Master](../../IMPLEMENTATION_PLAN.md) · [conventions](01-conventions.md) · [état réel](00-etat-reel.md)
> Dépend de : M1 ✅. `D5` dépend de l'arbitrage nav [#E0](lot-e-compagnon.md).

## Détail fonctionnel

- **Domaine/Data** : `Provider`/`ProviderSummary`, `ProviderRepository` (`searchProviders`, `getProviderProfile`), `SearchProvidersUseCase`. Les `reviews` (entité + usecases) sont **déjà présents** → réutiliser.
- **Présentation** : `SearchPage` (barre + filtres motif/géo/dispo + résultats), `ProviderProfilePage` (profil public, avis, créneaux), entrée vers `BookingFlowPage` existant (parcours invité → invite). Intégration nav : selon arbitrage [#E0](lot-e-compagnon.md).

## Backlog atomique

| ID | Titre | Critères | Tests | → |
|----|-------|----------|-------|---|
| **D1** | `flutter(app): domain provider — ProviderRepository + SearchProvidersUseCase + entités` | filtres motif/géo/dispo modélisés | unit | — |
| **D2** | `flutter(app): data provider — ProviderApi + ProviderRepositoryImpl` | `GET /v1/providers?…` mapping | unit | D1 |
| **D3** | `flutter(app): SearchPage (barre + filtres + résultats + état vide)` | recherche → liste ; empty state | widget | D2 |
| **D4** | `flutter(app): ProviderProfilePage (profil public + avis réutilisés + créneaux)` | réutilise `reviews` ; CTA réserver | widget | D3 |
| **D5** | `flutter(app): intégration nav Recherche (selon arbitrage #E0) + parcours invité→invite` | 5 onglets max respectés | widget (router) | D3,E0 |
