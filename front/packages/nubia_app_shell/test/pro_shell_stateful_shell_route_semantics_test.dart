import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_app_shell/nubia_app_shell.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

const _destinations = [
  ProNavDestination(
      label: 'Agenda', icon: Icons.calendar_today, route: '/agenda'),
  ProNavDestination(label: 'Patients', icon: Icons.people, route: '/patients'),
];

const _config = ProConfig(
  appTitle: 'Nubia Pro',
  spaceLabel: 'Cabinet Test',
  destinations: _destinations,
);

const _session =
    AuthSession(kind: UserKind.pro, userId: 'u1', role: ProRole.practitioner);

class _Shell extends StatelessWidget {
  const _Shell({required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return ProShell(
      config: _config,
      session: _session,
      currentRoute: navigationShell.currentIndex == 0 ? '/agenda' : '/patients',
      onNavigate: (destination) => navigationShell.goBranch(
        destination.route == '/agenda' ? 0 : 1,
      ),
      body: navigationShell,
    );
  }
}

GoRouter _buildRouter() => GoRouter(
      initialLocation: '/agenda',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) =>
              _Shell(navigationShell: navigationShell),
          branches: [
            StatefulShellBranch(routes: [
              GoRoute(
                path: '/agenda',
                builder: (_, __) =>
                    const Scaffold(body: Center(child: Text('agenda content'))),
              ),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                path: '/patients',
                builder: (_, __) => const Scaffold(
                    body: Center(child: Text('patients content'))),
              ),
            ]),
          ],
        ),
      ],
    );

void main() {
  // #6310 — régression #6286/#6280 : quand `ProShell.body` héberge un
  // `StatefulNavigationShell` (`StatefulShellRoute`, praticien/secrétariat),
  // ce dernier embarque son propre `Navigator`. La route active de ce
  // `Navigator` imbriqué pousse un `BlockSemantics` qui masque, par ordre de
  // peinture et non par ascendance dans l'arbre de widgets, tout ce qui est
  // peint AVANT lui sous le plus proche ancêtre Semantics commun — ici le
  // rail/tiroir de `ProShell`, peint avant [body] dans le `Row`/`Column` du
  // rail. Rendus et cliquables à l'écran (indépendant des Semantics), mais
  // absents de l'arbre d'accessibilité (cf. `_RouteSemanticsBoundary`,
  // pro_shell.dart).
  testWidgets(
    'body StatefulShellRoute : le rail garde ses entrées dans l\'arbre '
    'Semantics (rail desktop)',
    (tester) async {
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(
        MaterialApp.router(
          theme: NubiaTheme.light,
          routerConfig: _buildRouter(),
        ),
      );
      await tester.pumpAndSettle();

      final agenda = tester.getSemantics(find.text('Agenda'));
      expect(agenda.flagsCollection.isButton, isTrue);
      expect(agenda.label, 'Agenda');

      final patients = tester.getSemantics(find.text('Patients'));
      expect(patients.flagsCollection.isButton, isTrue);
      expect(patients.label, 'Patients');

      handle.dispose();
    },
  );
}
