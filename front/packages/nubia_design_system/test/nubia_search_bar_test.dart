import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import 'support/harness.dart';

void main() {
  group('NubiaSearchBar', () {
    testWidgets('affiche la loupe et le hint', (tester) async {
      await tester.pumpWidget(
        wrap(const NubiaSearchBar(hint: 'Praticien, spécialité...')),
      );

      expect(find.byIcon(Icons.search), findsOneWidget);
      expect(find.text('Praticien, spécialité...'), findsOneWidget);
    });

    testWidgets('notifie onChanged à la saisie', (tester) async {
      String? typed;
      await tester.pumpWidget(
        wrap(NubiaSearchBar(onChanged: (v) => typed = v)),
      );

      await tester.enterText(find.byType(TextField), 'cardio');
      expect(typed, 'cardio');
    });

    testWidgets('le bouton clear apparaît et vide le champ', (tester) async {
      final controller = TextEditingController();
      bool cleared = false;
      await tester.pumpWidget(
        wrap(
          NubiaSearchBar(controller: controller, onClear: () => cleared = true),
        ),
      );

      await tester.enterText(find.byType(TextField), 'abc');
      await tester.pump();
      expect(find.byIcon(Icons.close), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      expect(controller.text, isEmpty);
      expect(cleared, isTrue);
    });

    testWidgets('affiche le chip lieu trailing', (tester) async {
      await tester.pumpWidget(
        wrap(const NubiaSearchBar(locationChip: NubiaChip(label: 'Paris'))),
      );

      expect(find.text('Paris'), findsOneWidget);
    });
  });
}
