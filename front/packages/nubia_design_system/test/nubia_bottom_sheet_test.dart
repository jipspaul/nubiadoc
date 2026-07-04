import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

Widget _host(Widget child) => MaterialApp(
      theme: NubiaTheme.light,
      home: Scaffold(body: child),
    );

void main() {
  group('NubiaBottomSheet', () {
    testWidgets('ouvre une feuille contenant le child + poignée 32×4', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => NubiaBottomSheet.show(
                context: context,
                child: const Text('Contenu feuille'),
              ),
              child: const Text('Ouvrir'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Ouvrir'));
      await tester.pumpAndSettle();

      expect(find.text('Contenu feuille'), findsOneWidget);
      expect(find.byType(BottomSheet), findsOneWidget);
      // Poignée 32×4 présente dans la feuille.
      final handleSize = tester.getSize(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.byWidgetPredicate(
            (w) =>
                w is Container &&
                w.constraints ==
                    const BoxConstraints.tightFor(width: 32, height: 4),
          ),
        ),
      );
      expect(handleSize, const Size(32, 4));
    });

    testWidgets('renvoie la valeur passée à Navigator.pop', (tester) async {
      String? result;
      await tester.pumpWidget(
        _host(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await NubiaBottomSheet.show<String>(
                  context: context,
                  child: Builder(
                    builder: (ctx) => TextButton(
                      onPressed: () => Navigator.of(ctx).pop('ok'),
                      child: const Text('Valider'),
                    ),
                  ),
                );
              },
              child: const Text('Ouvrir'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Ouvrir'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Valider'));
      await tester.pumpAndSettle();

      expect(result, 'ok');
    });
  });
}
