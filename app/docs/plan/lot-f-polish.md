# Lot F — i18n, a11y, polish & mode démo [R6]

> ⬅️ [Master](../../IMPLEMENTATION_PLAN.md) · [conventions](01-conventions.md) · [état réel](00-etat-reel.md)
> Transverse : dépend de l'avancement global. `F3` dépend de [H1](lot-h-dette.md).

## Détail fonctionnel

- **i18n** : créer `lib/l10n/app_en.arb` + `app_fr.arb`, `l10n.yaml`, extraire les chaînes.
- **a11y** : audit `Semantics`, contrastes AA, cibles 44×44.
- **Polish** : `Hero` cartes RDV/devis, `AnimatedSwitcher` états, `NubiaSkeletonLoader` partout.
- **Démo** : `--dart-define=DEMO_MODE=true` seed fictif + bypass auth.
- **Branding** : icons/splash via `flutter_launcher_icons` + `flutter_native_splash`.

## Backlog atomique

| ID | Titre | Critères | Tests | → |
|----|-------|----------|-------|---|
| **F1** | `flutter(app): i18n — l10n.yaml + app_fr.arb/app_en.arb + extraction des chaînes (auth/home/RDV)` | `flutter gen-l10n` OK ; FR par défaut | widget (locale switch) | — |
| **F2** | `flutter(app): a11y — audit Semantics + contrastes AA + cibles 44×44 sur écrans clés` | labels lecteur d'écran présents | widget (Semantics) | — |
| **F3** | `flutter(app): polish — Hero cartes RDV/devis + AnimatedSwitcher états + skeletons généralisés` | transitions fluides ; plus de spinner brut | widget | H1 |
| **F4** | `flutter(app): mode démo — DEMO_MODE seed fictif global + bypass auth` | `--dart-define=DEMO_MODE=true` démarre sans backend | widget (bootstrap démo) | — |
| **F5** | `flutter(app): branding — flutter_launcher_icons + flutter_native_splash` | icônes + splash générés iOS/Android | — | — |
| **F6** | `flutter(app): perf — passe profile listes (<16 ms/frame) + const audit` | Devtools timeline OK sur listes longues | — | — |
