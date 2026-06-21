# Nubia — front (Flutter monorepo)

Three Flutter apps (**patient**, **praticien**, **secrétariat**) on **web / desktop / mobile**,
sharing one design system, hexagonal architecture, BLoC, Dio, and an **A2UI**
([a2ui.org](https://a2ui.org)) catalog + renderer.

It's a native **Dart pub workspace** (single lockfile, one `flutter pub get` at the root).
Melos 7 convenience scripts live in the root `pubspec.yaml` under the `melos:` key (there is
no separate `melos.yaml`).

## Layout

```
front/
├── pubspec.yaml                 # pub workspace root + Melos scripts (melos: key)
├── packages/
│   ├── nubia_domain             # pure Dart: entities, value objects, repo ports, use cases, Failure
│   ├── nubia_design_system      # theme + tokens + Nubia* widgets + A2UI prop mappers (DsProps)
│   ├── nubia_core               # Dio client, JWT refresh interceptor, storage, DI base, router primitives, AuthSession
│   ├── nubia_data               # DTOs, Dio APIs, repository impls, registerData()
│   └── nubia_a2ui               # catalog.json + renderer mapping catalog components → Nubia widgets
└── apps/
    ├── app_patient              # mobile-first, 5-tab shell
    ├── app_practicien           # desktop/tablet, clinical depth
    └── app_secretariat          # desktop/tablet, admin only — ZERO clinical access
```

Dependency edges: `domain` ← `core` ← `data`; `design_system` standalone; `a2ui` →
`design_system` + `core`; each app → all five packages.

## Architecture

- **Hexagonal**: `nubia_domain` is framework-free (no Flutter, no Dio). `nubia_data`
  implements its repository ports over Dio. Apps depend on ports, never impls.
- **DI**: hand-written GetIt registration (`registerCore` → `registerData` → app blocs).
  No build_runner needed. `gi()` infers each constructor dependency by type.
- **A2UI**: `nubia_a2ui/assets/catalog.json` declares components; `ComponentRegistry.nubiaDefault()`
  maps each catalog type 1:1 to a Nubia widget. A test asserts catalog ↔ registry parity.
  Transports (SSE/WebSocket) are interface stubs; the demo runs off a local fixture stream.

## Role differentiation (praticien vs secrétariat)

Both pro apps share the same login/core/domain/data. The secretariat's **zero clinical
access** is enforced in depth:

1. **DI exclusion** — `registerData(getIt, includeClinical: false)` never registers the
   clinical/prescription repos or use cases (no code path to clinical data in the binary).
2. **Nav exclusion** — `ProConfig.nav` ships no clinical destination.
3. **Runtime guard** — the dashboard filters destinations by `AuthSession.canAccessClinical`.
4. **Backend 403** — surfaced via `Failure` → error widgets.

## Run

```bash
# from front/
flutter pub get                 # resolves the whole workspace

# web
cd apps/app_patient    && flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8080/v1
cd apps/app_practicien && flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8080/v1
cd apps/app_secretariat&& flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8080/v1

# desktop (macOS)
cd apps/app_practicien && flutter run -d macos

# each app exposes an /a2ui-demo route rendering Nubia widgets from a local A2UI fixture
```

`API_BASE_URL` defaults to `https://api.nubia.health/v1` (see `nubia_core` `ApiConstants`).

## Checks

```bash
dart analyze .                          # whole workspace (currently: no issues)
cd packages/nubia_a2ui && flutter test  # catalog↔registry parity + binding

# Melos scripts (repo-pinned Melos 7 — no global install needed):
dart run melos analyze                  # dart analyze . across the workspace
dart run melos test                     # flutter test in every member with a test/ dir
dart run melos format                   # dart format .
dart run melos generate                 # build_runner in members that depend on it (nubia_data)
dart run melos clean                    # flutter clean across all members
dart run melos upgrade                  # upgrade deps (single shared lockfile)
```

The workspace is kept **`dart format`-clean** (default 80-col). Run `dart run melos format`
before committing so diffs stay free of unrelated reformatting.

## Historique

Les packages partagés ont été extraits de l'ancienne app patient `../app/`. Cette app
de référence a été supprimée (FR1.9) une fois la parité atteinte : toutes les
features patient (FR1.1 → FR1.8) vivent désormais dans `apps/app_patient/`.
