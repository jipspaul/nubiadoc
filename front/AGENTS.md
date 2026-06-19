# front/ — Flutter monorepo (3 apps + 7 packages)

Tu es dans le **monorepo Flutter Nubia** : trois apps (patient / praticien / secrétariat) partageant une architecture hexagonale, BLoC, Dio, un design system et un workspace Dart natif.

## Layout

```
front/
├── pubspec.yaml          # workspace root (lockfile unique)
├── packages/
│   ├── nubia_domain      # Dart pur : entités, value objects, ports repo, use cases, Failure
│   ├── nubia_design_system  # thème + tokens + widgets Nubia* + mappers A2UI (DsProps)
│   ├── nubia_core        # Dio client, intercepteur JWT refresh, storage, DI base, AuthSession
│   ├── nubia_data        # DTOs, Dio APIs, repo impls, registerData() / registerCore()
│   ├── nubia_a2ui        # catalog.json + registry de rendu A2UI → widgets Nubia
│   ├── nubia_app_shell   # ProShell (nav rail desktop / drawer mobile) + ProConfig + ProNavDestination
│   └── nubia_test_harness  # pumpApp, MockRepositories, MockBlocs (test seulement)
└── apps/
    ├── app_patient       # mobile-first, shell 5 onglets
    ├── app_practicien    # desktop/tablet, accès clinique complet
    └── app_secretariat   # desktop/tablet, ZÉRO accès clinique
```

Dépendances : `domain` ← `core` ← `data` ; `design_system` standalone ; `a2ui` → `design_system` + `core` ; `app_shell` → `core` + `design_system` ; chaque app → tous les packages.

## Architecture

- **Hexagonale** : `nubia_domain` est framework-free (ni Flutter ni Dio). `nubia_data` implémente les ports repo via Dio. Les apps dépendent des ports, jamais des implémentations.
- **DI** : GetIt hand-written (`registerCore` → `registerData` → blocs app). Pas de build_runner pour le DI. `gi<T>()` résout par type.
- **BLoC** : état métier via `Bloc` / `Cubit` (`flutter_bloc`). Un bloc par feature, enregistré dans le DI de l'app.
- **Routing** : `go_router` ; routes déclarées dans `app_router.dart` de chaque app.
- **Cache offline** : `nubia_data` expose un pattern repo décoré via `CachedAppointmentsRepositoryImpl` (Drift + `cacheFirst`). `registerData(useCache: true)` active le cache.

## Cloisonnement clinique (praticien vs secrétariat)

Le cloisonnement est défensif en profondeur :

1. **DI** — `registerData(includeClinical: false)` n'enregistre jamais les repos/UC consultation ni les prescriptions.
2. **Nav** — `ProConfig.shellConfig` ne déclare aucune destination `requiresClinical` dans `app_secretariat`.
3. **Runtime** — `ProShell` filtre les destinations si `!session.canAccessClinical`.
4. **Backend** — 403 surfacé via `Failure` → widget d'erreur.
5. **Tests** — assert binaire : aucun `ConsultationRepository` / `PrescriptionRepository` enregistré dans `app_secretariat`.

## Règles dures

1. **1 widget = 1 fichier.** Pas de méthode `_buildXxx()` — extrais en widget dédié.
2. **`StatelessWidget` par défaut.** `StatefulWidget` seulement si état UI local (animation, focus, controller).
3. **`const` constructors** partout où l'arbre le permet.
4. **État via BLoC/Cubit** (jamais setState pour de l'état métier).
5. **Pas d'appel réseau depuis un widget.** Toujours : Repository → Bloc/State → Widget.
6. **Theming via `ThemeData` + tokens DS** (`nubia_design_system`). Jamais `Color(0xFF…)` hard-codé dans une feature.
7. **Zéro PII dans les logs.** Pas de `print` commité en production.
8. **`includeClinical: false`** dans `bootstrap.dart` de `app_secretariat` — ne jamais passer `true`.

## Packages partagés — résumé des responsabilités

| Package | Ce qu'il expose |
|---|---|
| `nubia_domain` | Entités, ports repo (abstractions), use cases, `Failure`, `AmountCents` |
| `nubia_design_system` | `NubiaTheme`, `NubiaColors`, widgets (`NubiaButton`, `NubiaAppBar`, `NubiaEmptyState`…) |
| `nubia_core` | `DioClient`, `JwtRefreshInterceptor`, `AuthSession`, `ApiConstants`, `gi()` |
| `nubia_data` | DTOs, API Dio, `*RepositoryImpl`, `registerCore()`, `registerData()`, cache Drift |
| `nubia_a2ui` | `ComponentRegistry`, `A2UIRenderer`, `catalog.json` |
| `nubia_app_shell` | `ProShell`, `ProConfig`, `ProNavDestination` |
| `nubia_test_harness` | `pumpApp(widget)`, `Mock*Repository`, helpers mocktail |

## Structure type d'une feature

```
apps/app_<x>/lib/features/<feature>/
├── <feature>_bloc.dart      # Bloc (events + states + transitions)
├── <feature>_page.dart      # Widget racine (BlocProvider ou BlocConsumer)
└── widgets/                 # Sous-widgets extraits (≥ 1 widget = 1 fichier)

apps/app_<x>/test/features/
└── <feature>_test.dart      # tests widget + tests bloc
```

## Tests

- **Widget** : `testWidgets(...)` via `pumpApp()` du `nubia_test_harness`, overrides BLoC/Cubit.
- **Bloc** : `blocTest(...)` de `bloc_test` ; états et transitions vérifiés.
- **Objectif** : ≥ 5 tests par feature (2–3 widget + 2–3 bloc). Viser la couverture des cas succès / vide / erreur.
- **Pas de golden tests** sur les écrans métier (trop volatil) — réservés au design system.
- **Smoke tests** : chaque package doit avoir un dossier `test/` (requis par `melos test`).

## Avant de committer

```bash
# depuis front/
dart run melos analyze          # analyse statique workspace complet
dart run melos test             # flutter test sur tous les packages avec test/
```

La CI Forgejo (`front-test`) exécute exactement ces deux commandes. Rouge localement = rouge CI.

## Commandes utiles

```bash
# Depuis front/
flutter pub get                             # résout le workspace entier
dart run melos format                       # formate tout le Dart

# Lancer une app (web)
cd apps/app_patient    && flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8080/v1
cd apps/app_practicien && flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8080/v1
cd apps/app_secretariat&& flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8080/v1

# Tests ciblés
cd apps/app_patient && flutter test test/features/mes_rdv_test.dart
```

## Référence

- Routes API : `docs/12-reference-api.md`.
- Design tokens : `design/03-design-system/`.
- Plan atomique features : `web-console/PLAN-ATOMIC.md` §I.
- État courant : `PROGRESS.md`.
