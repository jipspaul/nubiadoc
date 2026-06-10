# Lot B — Espace financier 🎭 [R2]

> ⬅️ [Master](../../IMPLEMENTATION_PLAN.md) · [conventions](01-conventions.md) · [état réel](00-etat-reel.md)
> Dépend de : [lot A](lot-a-wedge.md). Données échéancier = **fictives** (🎭).

## Détail fonctionnel

- `FinancialSpacePage` (devis → renvoi [lot A](lot-a-wedge.md), factures, historique règlements, reste dû).
- `PaymentSchedulePage` (échéancier statuts payé/à venir/en retard — **fictif**).
- `InvoiceDetailPage` (PDF).

Accès via l'onglet Documents (« + finances », cf. `route_names`).

## Backlog atomique

| ID | Titre | Critères | Tests | → |
|----|-------|----------|-------|---|
| **B1** | `flutter(app): FinancialSpacePage (devis/factures/historique/reste dû)` | agrège lot A + factures ; renvoi vers QuoteDetail | widget (vide/rempli) | A3 |
| **B2** | `flutter(app): PaymentSchedulePage 🎭 (échéancier statuts payé/à venir/en retard, données fictives)` | 3 statuts visuellement distincts | widget | — |
| **B3** | `flutter(app): InvoiceDetailPage (détail + téléchargement PDF via DocumentOpener)` | ouvre PDF facture | widget | B1 |
