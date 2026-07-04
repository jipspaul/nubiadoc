import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: NubiaTheme.light,
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  group('MetricTile', () {
    testWidgets('affiche icône, valeur et libellé', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const MetricTile(
            icon: Icons.description_outlined,
            value: '3',
            label: 'À signer',
          ),
        ),
      );

      expect(find.text('3'), findsOneWidget);
      expect(find.text('À signer'), findsOneWidget);
      expect(find.byIcon(Icons.description_outlined), findsOneWidget);
    });

    testWidgets('variante alerte : pastille teintée danger', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const MetricTile(
            icon: Icons.warning_amber_rounded,
            value: '2',
            label: 'En retard',
            variant: MetricTileVariant.danger,
          ),
        ),
      );

      final tokens = NubiaTokens.light;
      final iconWidget = tester.widget<Icon>(
        find.byIcon(Icons.warning_amber_rounded),
      );
      expect(iconWidget.color, tokens.dangerFg);
    });

    testWidgets('interactive quand onTap fourni', (tester) async {
      var tapped = 0;
      await tester.pumpWidget(
        _wrap(
          MetricTile(
            icon: Icons.euro,
            value: '1 240 €',
            label: 'À régler',
            onTap: () => tapped++,
          ),
        ),
      );

      expect(find.byType(InkWell), findsOneWidget);
      await tester.tap(find.byType(MetricTile));
      await tester.pumpAndSettle();
      expect(tapped, 1);
    });
  });
}
