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

| ID | Titre | Critères d'acceptation (résumé) | Tests | → |
|----|-------|----------------------------------|-------|---|
| **A1** | `flutter(app): domain billing — AmountCents + QuoteStatus + usecases (GetPendingQuotes/GetQuoteById/InitiateSignature/InitiateDeposit)` | `AmountCents` rejette négatifs/format ; usecases renvoient `Either<Failure,_>` ; aucun `import flutter` | unit (AmountCents edge cases, chaque usecase succès/échec) | — |
| **A2** | `flutter(app): data billing — QuoteDto + BillingApi (Dio/retrofit) + BillingRepositoryImpl` | mapping DTO↔entité ; 4 routes câblées ; erreurs → `Failure` | unit (mapping, 401/500→Failure) | A1 |
| **A3** | `flutter(app): QuoteListPage + QuoteDetailPage (lignes repliables, badge statut, CTA Signer)` | total + reste à charge en gras ; CTA désactivé si signé | widget (3 statuts, CTA disabled) | A2 |
| **A4** | `flutter(app): SignatureWebViewPage (InAppWebView Yousign + deep link callback)` | reprise si interrompu (statut reste `sent`) | widget (callback simulé → succès) | A3 |
| **A5** | `flutter(app): DepositPaymentPage (Stripe PaymentSheet + Apple/Google Pay + Idempotency-Key)` | clé idempotence générée avant 1er tap, réutilisée au retry ; états loading/disabled/error | unit (idempotency), widget (états) | A2 |
| **A6** | `flutter(app): PaymentSuccessPage + wiring wedge end-to-end + cas limites (RAC=0, devis expiré, paiement KO)` | RAC=0 → skip paiement ; expiré → CTA nouveau devis | widget (branches) | A4,A5 |
| **A7** | `flutter(app): deps pubspec — flutter_stripe + pay + flutter_inappwebview (versions épinglées)` | `flutter pub get` OK, build passe | — | — |

**Séquence interne** : `A1→A2→{A3→A4, A5}→A6`. `A7` indépendant mais prérequis build de `A5`.
