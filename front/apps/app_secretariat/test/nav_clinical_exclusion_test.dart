import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_app_shell/nubia_app_shell.dart' as shell;
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

// Clinical icons that the AppShell must never render when canAccessClinical is
// false (secretary role).
const _iconConsultation = Icons.medical_services_outlined;
const _iconOrdonnances = Icons.medication_outlined;
const _iconJournalClinique = Icons.notes_outlined;

// A shell config that includes clinical destinations so the ProShell filtering
// logic is exercised, regardless of what the secretariat's own ProConfig declares.
const _configWithClinical = shell.ProConfig(
  appTitle: 'Test Shell',
  spaceLabel: 'Test',
  destinations: [
    shell.ProNavDestination(
      label: 'Tableau de bord',
      icon: Icons.dashboard_outlined,
      route: '/',
    ),
    shell.ProNavDestination(
      label: 'Consultations',
      icon: _iconConsultation,
      route: '/consultation',
      requiresClinical: true,
    ),
    shell.ProNavDestination(
      label: 'Ordonnances',
      icon: _iconOrdonnances,
      route: '/ordonnances',
      requiresClinical: true,
    ),
    shell.ProNavDestination(
      label: 'Journal clinique',
      icon: _iconJournalClinique,
      route: '/journal-clinique',
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
        config: _configWithClinical,
        session: _secretarySession,
      ),
    );

void main() {
  group(
    'nav_clinical_exclusion — session secrétariat (canAccessClinical=false)',
    () {
      testWidgets(
        'aucune icône consultations (medical_services) visible',
        (tester) async {
          await tester.binding.setSurfaceSize(const Size(800, 900));
          addTearDown(tester.binding.reset);
          await tester.pumpWidget(_buildShell());
          await tester.pumpAndSettle();

          expect(find.byIcon(_iconConsultation), findsNothing);
        },
      );

      testWidgets(
        'aucune icône ordonnances (medication) visible',
        (tester) async {
          await tester.binding.setSurfaceSize(const Size(800, 900));
          addTearDown(tester.binding.reset);
          await tester.pumpWidget(_buildShell());
          await tester.pumpAndSettle();

          expect(find.byIcon(_iconOrdonnances), findsNothing);
        },
      );

      testWidgets(
        'aucune icône journal-clinique (notes) visible',
        (tester) async {
          await tester.binding.setSurfaceSize(const Size(800, 900));
          addTearDown(tester.binding.reset);
          await tester.pumpWidget(_buildShell());
          await tester.pumpAndSettle();

          expect(find.byIcon(_iconJournalClinique), findsNothing);
        },
      );
    },
  );
}
