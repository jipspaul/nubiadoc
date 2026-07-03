import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

Widget _host(Widget child) => MaterialApp(
      theme: NubiaTheme.light,
      home: Scaffold(body: child),
    );

void main() {
  group('NubiaSnackbar', () {
    testWidgets('affiche le message et l\'icône success', (tester) async {
      await tester.pumpWidget(
        _host(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => NubiaSnackbar.show(
                context: context,
                message: 'Devis signé',
                variant: NubiaSnackbarVariant.success,
              ),
              child: const Text('Afficher'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Afficher'));
      await tester.pump(); // démarre l'animation du snackbar

      expect(find.text('Devis signé'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    });

    testWidgets('auto-dismiss 4 s sans action', (tester) async {
      await tester.pumpWidget(
        _host(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => NubiaSnackbar.show(
                context: context,
                message: 'Sans action',
              ),
              child: const Text('Afficher'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Afficher'));
      await tester.pump();
      final snack = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(snack.duration, const Duration(seconds: 4));
      expect(find.byType(SnackBarAction), findsNothing);
    });

    testWidgets('auto-dismiss 6 s avec action', (tester) async {
      await tester.pumpWidget(
        _host(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => NubiaSnackbar.show(
                context: context,
                message: 'Avec action',
                actionLabel: 'Annuler',
                onAction: () {},
              ),
              child: const Text('Afficher'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Afficher'));
      await tester.pump();
      final snack = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(snack.duration, const Duration(seconds: 6));
      expect(find.text('Annuler'), findsOneWidget);
      expect(find.byType(SnackBarAction), findsOneWidget);
    });
  });
}
