# Lot C — Écrans 🎭 démo [R3]

> ⬅️ [Master](../../IMPLEMENTATION_PLAN.md) · [conventions](01-conventions.md) · [état réel](00-etat-reel.md)
> Dépend de : M0 ✅. **Vraies pages Flutter, données statiques** (🎭). Débloque [E8](lot-e-compagnon.md).

## Détail fonctionnel

- `TreatmentPlanPage` (soins réalisés/restants, phases, coût global, reste à charge — statique).
- `ImplantPassportPage` (marque/réf/lot/position, export PDF — statique).
- `PreventionPage` (rappels, score de suivi, CTA re-réservation — dernier RDV réel si dispo).

## Backlog atomique

| ID | Titre | Critères | Tests | → |
|----|-------|----------|-------|---|
| **C1** | `flutter(app): TreatmentPlanPage 🎭 (phases, soins réalisés/restants, coût global/RAC)` | données statiques cohérentes démo | widget | — |
| **C2** | `flutter(app): ImplantPassportPage 🎭 (marque/réf/lot/position + export PDF)` | export image→PDF | widget | — |
| **C3** | `flutter(app): PreventionPage 🎭 (rappels + score suivi + CTA re-réservation)` | CTA → BookingFlow | widget | — |
