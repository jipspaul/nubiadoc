import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_app_shell/nubia_app_shell.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

// Three destinations: two regular + one clinical-only.
const _destinations = [
  ProNavDestination(
    label: 'Agenda',
    icon: Icons.calendar_today,
    route: '/agenda',
  ),
  ProNavDestination(
    label: 'Patients',
    icon: Icons.people,
    route: '/patients',
  ),
  ProNavDestination(
    label: 'Journal clinique',
    icon: Icons.medical_services,
    route: '/journal',
    requiresClinical: true,
  ),
];

const _config = ProConfig(
  appTitle: 'Nubia Pro',
  spaceLabel: 'Cabinet Test',
  destinations: _destinations,
);

Widget _buildShell(AuthSession session) => MaterialApp(
      theme: NubiaTheme.light,
      home: ProShell(config: _config, session: session),
    );

// Default test surface is 800×600 — well above 720 px → desktop (NavigationRail).
void main() {
  group('ProShell — destinations', () {
    testWidgets('shows all destinations when canAccessClinical is true',
        (tester) async {
      const session = AuthSession(
        kind: UserKind.pro,
        userId: 'user-1',
        role: ProRole.practitioner,
      );
      await tester.pumpWidget(_buildShell(session));
      await tester.pumpAndSettle();

      expect(find.text('Agenda'), findsWidgets);
      expect(find.text('Patients'), findsWidgets);
      expect(find.text('Journal clinique'), findsWidgets);
    });

    testWidgets('hides clinical destination when not authorized',
        (tester) async {
      const session = AuthSession(
        kind: UserKind.pro,
        userId: 'user-2',
        role: ProRole.secretary, // canAccessClinical == false
      );
      await tester.pumpWidget(_buildShell(session));
      await tester.pumpAndSettle();

      expect(find.text('Agenda'), findsWidgets);
      expect(find.text('Patients'), findsWidgets);
      expect(find.text('Journal clinique'), findsNothing);
    });

    testWidgets('shows drawer on mobile layout (width < 720)', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      const session = AuthSession(
        kind: UserKind.pro,
        userId: 'user-3',
        role: ProRole.admin,
      );
      await tester.pumpWidget(_buildShell(session));
      await tester.pumpAndSettle();

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
      expect(scaffold.drawer, isNotNull);
    });
  });

  // --- Badges compteurs sur le rail (#5387) -----------------------------------
  group('ProShell — badges compteurs', () {
    const badgeDestinations = [
      ProNavDestination(
        label: 'Salle d\'attente',
        icon: Icons.meeting_room,
        route: '/salle-attente',
        badgeCount: 5,
      ),
      ProNavDestination(
        label: 'Agenda',
        icon: Icons.calendar_today,
        route: '/agenda',
      ),
      ProNavDestination(
        label: 'Devis',
        icon: Icons.description,
        route: '/devis',
        badgeCount: 0,
      ),
    ];

    const badgeConfig = ProConfig(
      appTitle: 'Nubia Pro',
      spaceLabel: 'Cabinet Test',
      destinations: badgeDestinations,
    );

    const session = AuthSession(
      kind: UserKind.pro,
      userId: 'user-4',
      role: ProRole.secretary,
    );

    testWidgets(
      'badgeCount > 0 : badge rouge visible avec le compteur (rail desktop)',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: NubiaTheme.light,
            home: ProShell(config: badgeConfig, session: session),
          ),
        );
        await tester.pumpAndSettle();

        final badges = tester.widgetList<Badge>(find.byType(Badge)).toList();
        final visible = badges.where((b) => b.isLabelVisible == true);
        expect(visible, hasLength(1));
        expect((visible.first.label as Text).data, '5');
      },
    );

    testWidgets(
      'badgeCount null ou 0 : aucun badge visible (pas de pastille vide)',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: NubiaTheme.light,
            home: ProShell(config: badgeConfig, session: session),
          ),
        );
        await tester.pumpAndSettle();

        final badges = tester.widgetList<Badge>(find.byType(Badge)).toList();
        // 3 destinations → 3 Badge wrappers, 2 masqués (null et 0).
        expect(badges.length, 3);
        expect(badges.where((b) => b.isLabelVisible == false), hasLength(2));
      },
    );

    testWidgets(
      'badgeCount > 0 : badge visible dans le drawer mobile',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(400, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          MaterialApp(
            theme: NubiaTheme.light,
            home: ProShell(config: badgeConfig, session: session),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(Icons.menu));
        await tester.pumpAndSettle();

        final badges = tester.widgetList<Badge>(find.byType(Badge)).toList();
        final visible = badges.where((b) => b.isLabelVisible == true);
        expect(visible, hasLength(1));
        expect((visible.first.label as Text).data, '5');
      },
    );
  });
}
