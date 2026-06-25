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

## Pull-to-refresh pattern

Pour toutes les pages à liste rechargeable (patients, RDV, salles d'attente…), combine `RefreshIndicator` avec un `Completer` résolu dans un `BlocListener`.

```dart
class _MyListPageState extends State<MyListPage> {
  Completer<void>? _refreshCompleter;

  @override
  Widget build(BuildContext context) {
    return BlocListener<MyBloc, MyState>(
      listener: (context, state) {
        if (state is MyLoaded || state is MyError) {
          _refreshCompleter?.complete();
          _refreshCompleter = null;
        }
      },
      child: RefreshIndicator(
        onRefresh: () {
          _refreshCompleter = Completer<void>();
          context.read<MyBloc>().add(const LoadEvent());
          return _refreshCompleter!.future;
        },
        child: /* liste scrollable */,
      ),
    );
  }
}
```

**Règles** :
- `onRefresh` retourne une `Future` qui se résout quand le chargement est terminé — sinon le spinner tourne indéfiniment.
- Le `Completer` est résolu dans le `BlocListener`, jamais dans `onRefresh` lui-même.
- Résoudre dans les deux branches (`MyLoaded` **et** `MyError`) pour éviter un spinner bloqué sur erreur réseau.
- `StatefulWidget` est justifié ici : le `Completer` est un état UI local (cycle de vie de l'indicateur).

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

## Widget test pattern (mocktail)

Pattern répété dans 20+ fichiers de test. Squelette canonique.

**Déclarer les mocks** (en haut du fichier de test) :

```dart
// Mock BLoC (bloc_test) : permet when(() => bloc.state).thenReturn(...)
class MockPatientsBloc extends MockBloc<PatientsEvent, PatientsState>
    implements PatientsBloc {}

// Mock repo/use-case (mocktail) : pour les tests Bloc
class MockPatientRepository extends Mock implements PatientRepository {}
```

**Widget test avec pumpApp** :

```dart
testWidgets('affiche la liste quand Loaded', (tester) async {
  final bloc = MockPatientsBloc();
  when(() => bloc.state).thenReturn(PatientsLoaded(patients: [alice]));

  await tester.pumpApp(
    BlocProvider<PatientsBloc>.value(
      value: bloc,
      child: const PatientsPage(),
    ),
  );
  await tester.pumpAndSettle();

  expect(find.text('Alice Martin'), findsOneWidget);
});
```

**Bloc test avec verify sur le repo** :

```dart
blocTest<PatientsBloc, PatientsState>(
  'appelle le repo une seule fois sur LoadPatients',
  build: () {
    when(() => repo.list()).thenAnswer((_) async => Right([alice]));
    return PatientsBloc(listPatients: ListPatientsUseCase(repo));
  },
  act: (bloc) => bloc.add(const LoadPatientsEvent()),
  expect: () => [const PatientsLoading(), PatientsLoaded(patients: [alice])],
  verify: (_) => verify(() => repo.list()).called(1),
);
```

**Règles** :
- `MockBloc<E, S>` (de `bloc_test`) pour les blocs ; `Mock` (de `mocktail`) pour les repos/use-cases.
- `pumpApp` injecte le thème Nubia — ne jamais wrapper manuellement dans `MaterialApp`.
- `when().thenReturn(...)` pour les getters sync ; `when().thenAnswer((_) async => ...)` pour les `Future`.
- Résoudre les états `Loaded` **et** `Error` pour éviter un spinner bloqué sur erreur réseau.

## Tests d'intégration (E2E)

Chaque app possède un dossier `integration_test/` couvert par `flutter test integration_test/` :

```
apps/app_<x>/integration_test/
└── app_test.dart      # parcours clés : login + invariants de cloisonnement
```

**Pattern obligatoire** :

```dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await GetIt.instance.reset();
    registerCore(GetIt.instance);
    registerData(GetIt.instance, includeClinical: …, includePro: …);
    registerPatient/registerPro(GetIt.instance); // selon l'app
  });
  tearDown(() async => GetIt.instance.reset());
  // …
}
```

**Règles** :
- DI **réel** (pas de mocks) — on teste le câblage complet.
- Viser les **invariants structurels** (textes du login, présence de pages, `ProConfig.includeClinical`) plutôt que des flux réseau qui nécessitent un backend live.
- Aucun appel réseau réel attendu : les tests doivent passer sans serveur.
- `includeClinical: false` **codé en dur** dans `app_secretariat/integration_test/app_test.dart`.

**Lancement** (device nécessaire) :

```bash
cd apps/app_patient
flutter test integration_test/app_test.dart -d chrome
```

Les tests d'intégration ne sont **pas** exécutés par `melos test` (pas de runner headless en CI) — ils sont réservés à la validation manuelle sur device/émulateur.

## Avant de committer

```bash
# depuis front/
dart run melos format           # dart format . — le workspace est gardé propre
dart run melos analyze          # analyse statique workspace complet
dart run melos test             # flutter test sur tous les packages avec test/
```

La CI Forgejo (`front-test`) exécute exactement `analyze` + `test`. Rouge localement = rouge CI.

**Formatage** : le workspace est maintenu `dart format`-propre. Lance `dart run melos format`
avant de committer (largeur de ligne par défaut 80). Un diff bruité par du reformatage non lié
signale que la convention n'a pas été suivie sur le commit précédent.

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
- État courant : issues Forgejo (label `state:*`) + `git log`.
