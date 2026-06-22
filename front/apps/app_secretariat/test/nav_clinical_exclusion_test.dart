import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_app_shell/nubia_app_shell.dart' as shell;
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

// Clinical icons under test — identical to the ones used in app_practicien's
// requiresClinical destinations. A secretary session must never reveal them.
const _consultationIcon = Icons.medical_services_outlined;
const _ordonnancesIcon = Icons.medication_outlined;
const _journalCliniqueIcon = Icons.medical_services;

// Shell config that deliberately includes the 3 clinical destinations so the
// ProShell filtering logic (canAccessClinical guard) is exercised, not just
// the absence of clinical entries in the real secretariat config.
const _testConfig = shell.ProConfig(
  appTitle: 'Test',
  spaceLabel: 'Cabinet Test',
  destinations: [
    shell.ProNavDestination(
      label: 'Agenda',
      icon: Icons.calendar_today,
      route: '/agenda',
    ),
    shell.ProNavDestination(
      label: 'Consultations',
      icon: _consultationIcon,
      route: '/consultation',
      requiresClinical: true,
    ),
    shell.ProNavDestination(
      label: 'Ordonnances',
      icon: _ordonnancesIcon,
      route: '/ordonnances',
      requiresClinical: true,
    ),
    shell.ProNavDestination(
      label: 'Journal clinique',
      icon: _journalCliniqueIcon,
      route: '/journal',
      requiresClinical: true,
    ),
  ],
);

const _secretarySession = AuthSession(
  kind: UserKind.pro,
  userId: 'sec-test',
  role: ProRole.secretary,
);

Widget _buildShell() => MaterialApp(
      theme: NubiaTheme.light,
      home: shell.ProShell(
        config: _testConfig,
        session: _secretarySession,
      ),
    );

void main() {
  group('nav_clinical_exclusion — secrétariat (canAccessClinical: false)', () {
    test('AuthSession secretary a canAccessClinical == false', () {
      expect(_secretarySession.canAccessClinical, isFalse);
    });

    testWidgets(
      'icône consultations masquée pour session secrétariat',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 900));
        addTearDown(tester.binding.reset);
        await tester.pumpWidget(_buildShell());
        await tester.pumpAndSettle();

        // Non-clinical destination still visible → confirms shell is rendered.
        expect(find.byIcon(Icons.calendar_today), findsWidgets);
        expect(find.byIcon(_consultationIcon), findsNothing);
      },
    );

    testWidgets(
      'icône ordonnances masquée pour session secrétariat',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 900));
        addTearDown(tester.binding.reset);
        await tester.pumpWidget(_buildShell());
        await tester.pumpAndSettle();

        expect(find.byIcon(_ordonnancesIcon), findsNothing);
      },
    );

    testWidgets(
      'icône journal-clinique masquée pour session secrétariat',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 900));
        addTearDown(tester.binding.reset);
        await tester.pumpWidget(_buildShell());
        await tester.pumpAndSettle();

        expect(find.byIcon(_journalCliniqueIcon), findsNothing);
      },
    );
  });
}
