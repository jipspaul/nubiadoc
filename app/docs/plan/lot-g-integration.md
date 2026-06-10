# Lot G — Tests d'intégration E2E [R7]

> ⬅️ [Master](../../IMPLEMENTATION_PLAN.md) · [conventions](01-conventions.md) · [état réel](00-etat-reel.md)
> Dépend de : [lot A](lot-a-wedge.md) (pour G3), features ✅ existantes.

## Détail fonctionnel

7 flows dans `integration_test/flows/` : auth, booking, **wedge** ★, messaging, documents, coverage, push→deep-link.

**Stratégie de mock** : `MockWebServer` (dio-http-mock-adapter), FCM test doubles, WebView stub (`InAppWebView` mock + retour deep link simulé).

**CI** : `.forgejo/workflows/flutter-integration.yml`, runner `flutter-ci:stable` (arm64), exécution headless (`flutter test integration_test/`), gated `test-integrity` avant auto-merge.

## Backlog atomique

| ID | Titre | Critères | → |
|----|-------|----------|---|
| **G1** | `flutter(app): integration — auth_flow (onboarding→login→accueil)` | vert headless | M1 ✅ |
| **G2** | `flutter(app): integration — booking_flow (recherche créneau→confirmation→liste)` | vert | M3 ✅ |
| **G3** | `flutter(app): integration — wedge_flow ★ (devis→signature→paiement→succès)` | vert, MockWebServer + WebView stub | A6 |
| **G4** | `flutter(app): integration — messaging_flow (envoi + pièce jointe → badge dashboard)` | vert | M4 ✅ |
| **G5** | `flutter(app): integration — documents_flow (accès + PDF viewer)` | vert | M6 ✅ |
| **G6** | `flutter(app): integration — coverage_flow (mise à jour couverture, n° sécu jamais loggé)` | vert | M8 ✅ |
| **G7** | `flutter(app): integration — push→deep-link (réception simulée → page correcte)` | vert | M9 ✅ |
| **G8** | `flutter(app): CI — .forgejo/workflows/flutter-integration.yml (runner stable, gated test-integrity)` | pipeline vert sur PR | G1..G7 |
