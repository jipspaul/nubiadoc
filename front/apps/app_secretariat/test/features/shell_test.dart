import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_app_shell/nubia_app_shell.dart' as shell;
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import 'package:app_secretariat/pro_config.dart';

void main() {
  // --- Invariants statiques ProConfig ------------------------------------------
  group('ProConfig — shell secrétariat (includeClinical: false)', () {
    test('includeClinical est false', () {
      expect(ProConfig.includeClinical, isFalse);
    });

    test('aucune destination ne requiert un accès clinique', () {
      final clinicalDests = ProConfig.shellConfig.destinations
          .where((d) => d.requiresClinical)
          .toList();
      expect(clinicalDests, isEmpty);
    });
  });

  // --- Widget tests : ProShell avec config secrétariat -------------------------
  group('ProShell — garde clinique secrétariat', () {
    const secretarySession = AuthSession(
      kind: UserKind.pro,
      userId: 'me',
      role: ProRole.secretary,
    );

    Widget buildShell() => MaterialApp(
          theme: NubiaTheme.light,
          home: shell.ProShell(
            config: ProConfig.shellConfig,
            session: secretarySession,
          ),
        );

    testWidgets(
      'affiche les destinations secrétariat configurées',
      (tester) async {
        await tester.pumpWidget(buildShell());
        await tester.pumpAndSettle();

        expect(find.text('Salle d\'attente'), findsWidgets);
        expect(find.text('Patients'), findsWidgets);
      },
    );

    testWidgets(
      'aucune surface clinique affichée (includeClinical: false)',
      (tester) async {
        await tester.pumpWidget(buildShell());
        await tester.pumpAndSettle();

        expect(find.text('Consultation'), findsNothing);
        expect(find.text('Journal clinique'), findsNothing);
      },
    );

    testWidgets(
      'ProShell ne contient aucune destination requiresClinical',
      (tester) async {
        await tester.pumpWidget(buildShell());
        await tester.pumpAndSettle();

        final shellWidget = tester.widget<shell.ProShell>(
          find.byType(shell.ProShell),
        );
        expect(
          shellWidget.config.destinations.any((d) => d.requiresClinical),
          isFalse,
        );
      },
    );
  });
}
