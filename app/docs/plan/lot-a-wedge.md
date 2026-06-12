# Lot A — Wedge : devis → signature → acompte [R1]

> ⬅️ [Master](../../IMPLEMENTATION_PLAN.md) · [conventions](01-conventions.md) · [état réel](00-etat-reel.md)
> Réf UX : `../../../design/04-ux-flows/01-wedge-devis-signature-acompte.md`. **Le flux le plus vendeur.**
> Dépend de : M3 ✅, M6 ✅. Débloque : [lot B](lot-b-financier.md), [G3](lot-g-integration.md).

## Détail fonctionnel

- **Domaine** : value object `AmountCents` (validation + format via `CurrencyUtils`), `QuoteLineItem`, enum `QuoteStatus` ; usecases `GetPendingQuotesUseCase`, `GetQuoteByIdUseCase`, `InitiateSignatureUseCase`, `InitiateDepositUseCase`.
- **Data** : `QuoteDto`, `BillingApi` (`GET /v1/billing/quotes`, `GET /v1/billing/quotes/:id`, `POST /v1/billing/quotes/:id/sign`, `POST /v1/billing/quotes/:id/deposit`), `BillingRepositoryImpl`.
- **Présentation** : `QuoteListPage`, `QuoteDetailPage`, `SignatureWebViewPage` (InAppWebView + retour deep link `nubia://signature/callback`), `DepositPaymentPage` (Stripe PaymentSheet + Apple/Google Pay, **Idempotency-Key**), `PaymentSuccessPage`.
- **Cas limites** : signature interrompue (statut `sent`), paiement échoué (retry même clé), devis expiré (CTA « demander nouveau devis »), reste à charge = 0 (skip paiement).

## Backlog atomique

> **État au 12/06** : A1-A5 + A7 ✅ mergés sur `main` (commits 4bb12aa, da95208, 9167d8d, 380f101, 274d3ab, 7153bee). A6 🟡 PARTIAL (PaymentSuccessPage existe mais wiring E2E à confirmer). **NE PLUS DISPATCHER A1-A5/A7 — un agent re-essayant produira un PR vide (cf. POSTMORTEM 2026-06-12).**

| ID | Statut | Titre | Commit |
|----|--------|-------|--------|
| **A1** | ✅ DONE | domain billing — AmountCents + QuoteStatus + usecases | `4bb12aa` (PR #1441, issue #1410) |
| **A2** | ✅ DONE | data billing — QuoteDto + BillingApi + BillingRepositoryImpl | `da95208` (PR #1448, issue #1411) |
| **A3** | ✅ DONE | QuoteListPage + QuoteDetailPage | `9167d8d` (issue #1412) |
| **A4** | ✅ DONE | SignatureWebViewPage (InAppWebView Yousign + deep link callback) | `380f101` (issue #1350 / T14) |
| **A5** | ✅ DONE | DepositPaymentPage (Stripe PaymentSheet + Apple/Google Pay + Idempotency-Key) | `274d3ab` (issue #1414) |
| **A6** | 🟡 PARTIAL | PaymentSuccessPage + wiring wedge end-to-end + cas limites (RAC=0, devis expiré, paiement KO) | partiel `4bb12aa`. **À FAIRE** : vérifier wiring `wedge_bloc` (RAC=0 skip, devis expiré CTA, retry KO). 1 issue ≤80 lignes. |
| **A7** | ✅ DONE | deps pubspec — flutter_stripe + flutter_inappwebview (versions épinglées) | `7153bee` (PR #1434, issue #1416). Note: `pay:` peut être absent (Stripe seul suffit MVP). |

**Reste à faire (lot A)** : finir A6 uniquement.

**Séquence interne** : `A1→A2→{A3→A4, A5}→A6`. `A7` indépendant.
