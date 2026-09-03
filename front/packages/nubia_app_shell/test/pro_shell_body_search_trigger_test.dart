import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_app_shell/nubia_app_shell.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

const _destinations = [
  ProNavDestination(
      label: 'Agenda', icon: Icons.calendar_today, route: '/agenda'),
];

const _config = ProConfig(
  appTitle: 'Nubia Pro',
  spaceLabel: 'Cabinet Test',
  destinations: _destinations,
);

const _session =
    AuthSession(kind: UserKind.pro, userId: 'u1', role: ProRole.secretary);

void main() {
  // #6316 — en mode [ProShell.body] (StatefulShellRoute), le NubiaAppBar
  // générique est court-circuité et emportait avec lui le déclencheur de
  // recherche globale, alors que seule la duplication du titre était voulue.
  // Le raccourci ⌘K restait fonctionnel mais n'avait plus de point d'entrée
  // visible à l'écran.
  testWidgets(
    'body StatefulShellRoute + searchHint/onSearchTap : le déclencheur de '
    'recherche est rendu (rail desktop)',
    (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: NubiaTheme.light,
          home: ProShell(
            config: _config,
            session: _session,
            searchHint: 'Patient, devis, commande…',
            onSearchTap: () => tapped = true,
            body: const Scaffold(body: Center(child: Text('contenu routé'))),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('global_search_trigger')), findsOneWidget);
      expect(find.textContaining('Patient, devis, commande…'), findsOneWidget);

      await tester.tap(find.byKey(const Key('global_search_trigger')));
      expect(tapped, isTrue);
    },
  );

  testWidgets(
    'body StatefulShellRoute sans searchHint/onSearchTap : pas de '
    'déclencheur de recherche',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: NubiaTheme.light,
          home: ProShell(
            config: _config,
            session: _session,
            body: const Scaffold(body: Center(child: Text('contenu routé'))),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('global_search_trigger')), findsNothing);
    },
  );
}
