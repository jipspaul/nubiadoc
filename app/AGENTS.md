# app/ — Flutter (Bloc / Riverpod)

Tu es dans l'**app Flutter Nubia**. Stack Flutter (stable channel) + Dart + Bloc (état) / Riverpod (DI).

## Layout
- `lib/` — code de production.
  - `lib/features/<feature>/` — un dossier par feature (présentation + état + repository).
  - `lib/core/` — helpers transverses (réseau, theme, routing).
- `test/` — `widget_test.dart` + `<feature>_test.dart` (un par feature).
- `integration_test/` — E2E sur device/emulator.
- `pubspec.yaml` — épingle les versions (pas de `^`, du `>=X.Y.Z <X+1.0.0`).
- `analysis_options.yaml` — lints stricts (pas de désactivation locale sans justification).
- `ARCHITECTURE.md` — découpe couches.
- `IMPLEMENTATION_PLAN.md` — plan par sprint.

## Règles dures
1. **1 widget = 1 fichier.** Pas de `_buildXxx()` helpers dans la même classe — extrais en widget dédié.
2. **`StatelessWidget` par défaut.** `StatefulWidget` seulement si état UI local (animation, focus, controller).
3. **`const` constructors partout** où l'arbre le permet (perf rebuild).
4. **État via Bloc/Cubit ou Provider/Notifier** selon la lib déjà utilisée par la feature. **Ne mélange pas** deux libs d'état dans une même feature.
5. **Pas d'appel réseau direct depuis un widget.** Toujours via Repository → State → Widget.
6. **Theming via `ThemeData`** + tokens du design system (cf. `design/03-design-system/`). Jamais `Color(0xFF…)` en dur dans une feature.

## Tests
- Widget : `testWidgets("...", (tester) async { ... })` avec `ProviderScope`/`BlocProvider` overrides pour mock.
- Mocks Bloc : `MockBloc` de `bloc_test`.
- Golden tests : pour les composants du design system uniquement, pas pour les écrans métier (trop volatil).

## Avant de committer
- `flutter analyze --fatal-infos`
- `flutter test`
- `flutter format .` si tu as touché beaucoup de fichiers.

## Référence
- Design system : `design/03-design-system/` (tokens, composants, thème).
- Personas + écrans : `design/01-personas.md`, `design/02-inventaire-ecrans.md`.
- Copy UX : `design/05-ux-copy/`.
