import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

Widget _host(Widget child) => MaterialApp(
      theme: NubiaTheme.light,
      home: Scaffold(body: child),
    );

void main() {
  group('AmountHeader', () {
    testWidgets('affiche label + montant en chiffres tabulaires', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const AmountHeader(
            label: 'Total du plan de soins',
            amount: '2 060 €',
            caption: 'Plan de soins · Dr Lefèvre',
          ),
        ),
      );

      expect(find.text('Total du plan de soins'), findsOneWidget);
      expect(find.text('Plan de soins · Dr Lefèvre'), findsOneWidget);

      final amount = tester.widget<Text>(find.text('2 060 €'));
      expect(
        amount.style?.fontFeatures,
        contains(const FontFeature.tabularFigures()),
      );
    });

    testWidgets('affiche le bandeau reste à charge quand fourni', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const AmountHeader(
            label: 'Total',
            amount: '2 060 €',
            remainingLabel: 'Reste à charge',
            remainingAmount: '1 550 €',
            remainingCaption: 'après remboursements',
          ),
        ),
      );

      expect(find.text('Reste à charge'), findsOneWidget);
      expect(find.text('après remboursements'), findsOneWidget);

      final remaining = tester.widget<Text>(find.text('1 550 €'));
      expect(
        remaining.style?.fontFeatures,
        contains(const FontFeature.tabularFigures()),
      );
    });

    testWidgets('masque le bandeau sans remainingAmount', (tester) async {
      await tester.pumpWidget(
        _host(const AmountHeader(label: 'Total', amount: '2 060 €')),
      );

      expect(find.text('Reste à charge'), findsNothing);
    });
  });
}
