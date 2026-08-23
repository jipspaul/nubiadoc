# app_secretariat

## Mission

App **secrétariat** Nubia (tablette / desktop), **zéro accès clinique** (`includeClinical: false` —
constante dans `pro_config.dart`). Fonctionnalités : agenda RDV, créneaux bookables, salle d'attente,
liste patients (sans motif ni notes), liste d'attente, devis cabinet, admin membres + secrétariats,
messagerie cabinet. Aucun champ clinique n'est jamais affiché ni enregistré dans le DI.

## Run local

```bash
cd front/apps/app_secretariat
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8080/v1
```

## Tests

```bash
# Depuis front/apps/app_secretariat
flutter test

# Suite workspace complète (depuis front/)
dart run melos test
```

## Navigation — surface unique (#5154)

Décision tranchée : **(a)** `ProShell` enveloppe désormais **toutes** les routes
via `StatefulShellRoute.indexedStack` (`router/app_router.dart`), au lieu de
n'être rendu que par la Dashboard.

- **Avant** : `ProShell` n'était instancié que par `DashboardPage` (montée
  uniquement sur `/`). Cliquer une entrée du rail appelait
  `context.go(destination.route)`, qui démontait `DashboardPage` — et donc
  `ProShell` — pour afficher la route GoRouter correspondante en pleine page,
  sans rail ni drawer. La navigation ne restait donc utilisable qu'en restant
  sur `/` ; toute autre destination perdait la barre de navigation.
- **Maintenant** : une branche `StatefulShellBranch` par entrée de
  `ProConfig.shellConfig.destinations` (même ordre — source unique utilisée à
  la fois pour déclarer les branches et pour la resolution
  index ↔ route dans `SecretariatShell`, donc plus de divergence possible
  entre l'ordre des branches et `pro_config.dart`). `SecretariatShell`
  (`features/dashboard/dashboard_page.dart`) est le nouveau point d'entrée du
  shell : il reçoit le `StatefulNavigationShell` et le passe à `ProShell` en
  tant que `body`, le rail/drawer restant monté quelle que soit la
  destination active et l'URL réagissant en conséquence.
- **Chrome par destination** : `ProShell` ne construit son propre `AppBar`
  générique que lorsque `body` n'est pas fourni. En mode `StatefulShellRoute`,
  chaque branche réutilise l'écran « page complète » déjà existant (son
  propre `Scaffold`/`AppBar`/FAB — ex. `AdminSecretiariatsPage`,
  `WaitingRoomPage`) : zéro régression fonctionnelle (bouton actualiser,
  raccourcis clavier, FAB de création, etc. tous conservés), zéro AppBar
  dupliqué. Seules `/` (Dashboard) et `/agenda` n'ont pas de `Scaffold`
  propre — elles utilisent le `NubiaAppBar` générique de `ProShell`.
- **Suivi possible (non bloquant)** : extraire un variant « Body » dédié
  (sans `Scaffold`/`AppBar`) pour les écrans qui n'en ont pas encore
  (`Patients`, `Devis`, `Stock`, `Messages`, `Admin membres`,
  `Motifs de RDV`, `Liste d'attente`) — sur le modèle de
  `WaitingRoomBody`/`WaitingRoomPage` — pour unifier davantage l'AppBar sous
  `NubiaAppBar`. Aucun de ces écrans n'a de chrome dupliqué aujourd'hui
  (`ProShell` ne rend pas d'AppBar concurrent), donc rien d'urgent.
- **Hors shell, volontairement** : `/splash`, `/login`, `/onboard` (garde
  d'authentification, cf. `buildAuthGuard`), ainsi que les push secondaires
  qui ne sont pas des destinations de nav (`/team-messages`, `/a2ui-demo`,
  `/patients/new`, `/appointments`) — deep-links/flux ponctuels qui restent
  volontairement en pleine page.

## Plan

Avancement FR3.x → issues Forgejo (filtre `[flutter-front] FR3`) + `git log`.

Architecture, règles et commandes → [`front/AGENTS.md`](../../AGENTS.md).
