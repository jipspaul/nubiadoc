import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import 'support/harness.dart';

const _items = <NubiaSelectItem<String>>[
  NubiaSelectItem(value: 'fr', label: 'France'),
  NubiaSelectItem(value: 'be', label: 'Belgique'),
  NubiaSelectItem(value: 'ch', label: 'Suisse'),
];

void main() {
  group('NubiaSelect', () {
    testWidgets('affiche le hint quand aucune valeur', (tester) async {
      await tester.pumpWidget(
        wrap(
          NubiaSelect<String>(
            items: _items,
            hint: 'Choisir un pays',
            onChanged: (_) {},
          ),
        ),
      );

      expect(find.text('Choisir un pays'), findsOneWidget);
      expect(find.byIcon(Icons.keyboard_arrow_down), findsOneWidget);
    });

    testWidgets('affiche le label de la valeur sélectionnée', (tester) async {
      await tester.pumpWidget(
        wrap(
          NubiaSelect<String>(items: _items, value: 'be', onChanged: (_) {}),
        ),
      );

      expect(find.text('Belgique'), findsOneWidget);
    });

    testWidgets('ouvre la feuille et sélectionne un élément', (tester) async {
      String? picked;
      await tester.pumpWidget(
        wrap(NubiaSelect<String>(items: _items, onChanged: (v) => picked = v)),
      );

      await tester.tap(find.byType(NubiaSelect<String>));
      await tester.pumpAndSettle();

      // La feuille liste tous les éléments.
      expect(find.text('Suisse'), findsOneWidget);

      await tester.tap(find.text('Suisse'));
      await tester.pumpAndSettle();
      expect(picked, 'ch');
    });

    testWidgets('désactivé si onChanged null : la feuille ne s ouvre pas', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          const NubiaSelect<String>(
            items: _items,
            hint: 'Fermé',
            onChanged: null,
          ),
        ),
      );

      await tester.tap(find.byType(NubiaSelect<String>));
      await tester.pumpAndSettle();
      // Aucun élément de feuille rendu.
      expect(find.text('France'), findsNothing);
    });
  });
}
