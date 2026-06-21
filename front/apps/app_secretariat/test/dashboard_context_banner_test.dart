import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import 'package:app_secretariat/features/dashboard/dashboard_page.dart';

void main() {
  group('ContextBanner', () {
    testWidgets('affiche le bandeau quand le label est fourni', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: NubiaTheme.light,
          home: const Scaffold(
            body: ContextBanner(
              label: 'Secrétariat "Dents & Co" — Établissement: Agence Lyon',
            ),
          ),
        ),
      );
      expect(find.byKey(const Key('context_banner')), findsOneWidget);
      expect(
        find.text('Secrétariat "Dents & Co" — Établissement: Agence Lyon'),
        findsOneWidget,
      );
    });

    testWidgets('masque le bandeau quand le label est null', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ContextBanner(label: null),
          ),
        ),
      );
      expect(find.byKey(const Key('context_banner')), findsNothing);
    });
  });
}
