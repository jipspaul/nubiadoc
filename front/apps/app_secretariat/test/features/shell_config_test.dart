import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_app_shell/nubia_app_shell.dart' as shell;
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import 'package:app_secretariat/pro_config.dart';

void main() {
  // Widget tests asserting that the secretariat shell is configured with
  // includeClinical: false — verifying both the static invariant and the
  // runtime guard of ProShell.
  group('Shell secrétariat — garde includeClinical: false', () {
    test('ProConfig.includeClinical est false', () {
      expect(ProConfig.includeClinical, isFalse);
    });

    test('shellConfig ne contient aucune destination requiresClinical', () {
      final clinicalDests = ProConfig.shellConfig.destinations
          .where((d) => d.requiresClinical)
          .toList();
      expect(clinicalDests, isEmpty);
    });

    testWidgets(
      'ProShell secrétariat affiche les destinations non-cliniques',
      (tester) async {
        const session = AuthSession(
          kind: UserKind.pro,
          userId: 'sec-1',
          role: ProRole.secretary,
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: NubiaTheme.light,
            home: shell.ProShell(
              config: ProConfig.shellConfig,
              session: session,
            ),
          ),
        );
        await tester.pumpAndSettle();

        for (final dest in ProConfig.shellConfig.destinations) {
          expect(find.text(dest.label), findsWidgets);
        }
      },
    );

    testWidgets(
      'ProShell masque toute destination requiresClinical pour un secrétaire',
      (tester) async {
        // Défense-en-profondeur : même si une destination clinique était
        // accidentellement ajoutée à la config, ProShell la filtrerait.
        final configWithClinical = shell.ProConfig(
          appTitle: ProConfig.appTitle,
          spaceLabel: ProConfig.spaceLabel,
          destinations: [
            ...ProConfig.shellConfig.destinations,
            const shell.ProNavDestination(
              label: 'Journal clinique',
              icon: Icons.medical_services,
              route: '/journal',
              requiresClinical: true,
            ),
          ],
        );

        const session = AuthSession(
          kind: UserKind.pro,
          userId: 'sec-2',
          role: ProRole.secretary, // canAccessClinical == false
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: NubiaTheme.light,
            home: shell.ProShell(config: configWithClinical, session: session),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Journal clinique'), findsNothing);
      },
    );
  });
}
