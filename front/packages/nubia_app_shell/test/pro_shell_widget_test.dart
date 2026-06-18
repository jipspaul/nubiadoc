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
}
