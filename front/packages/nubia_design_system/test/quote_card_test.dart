import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

Widget _host(Widget child) => MaterialApp(
      theme: NubiaTheme.light,
      home: Scaffold(body: child),
    );

const _lines = [
  QuoteLine(label: 'Consultation & bilan radio', amount: '50 €'),
  QuoteLine(label: 'Implant titane (dent 26)', amount: '1 200 €'),
];

void main() {
  group('QuoteCard', () {
    testWidgets('affiche titre, lignes alignées et montants tabulaires', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const QuoteCard(
            title: 'Plan de soins implantaire',
            status: QuoteCardStatus.sent,
            lines: _lines,
            subtitle: 'Dr Claire Lefèvre',
            total: '2 060 €',
          ),
        ),
      );

      expect(find.text('Plan de soins implantaire'), findsOneWidget);
      expect(find.text('Consultation & bilan radio'), findsOneWidget);
      expect(find.text('Implant titane (dent 26)'), findsOneWidget);
      expect(find.text('Dr Claire Lefèvre'), findsOneWidget);

      final amount = tester.widget<Text>(find.text('1 200 €'));
      expect(
        amount.style?.fontFeatures,
        contains(const FontFeature.tabularFigures()),
      );
    });

    testWidgets('affiche le badge statut via StatusPill', (tester) async {
      await tester.pumpWidget(
        _host(
          const QuoteCard(
            title: 'Devis',
            status: QuoteCardStatus.signed,
            lines: _lines,
          ),
        ),
      );

      expect(find.byType(StatusPill), findsOneWidget);
      expect(find.text('Signé'), findsOneWidget);
    });

    testWidgets('déclenche le CTA principal', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        _host(
          QuoteCard(
            title: 'Devis',
            status: QuoteCardStatus.sent,
            lines: _lines,
            ctaLabel: 'Signer le devis',
            onCtaPressed: () => tapped = true,
          ),
        ),
      );

      expect(find.byType(NubiaButton), findsOneWidget);
      await tester.tap(find.text('Signer le devis'));
      expect(tapped, isTrue);
    });
  });
}
