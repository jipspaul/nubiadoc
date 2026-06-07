// test/widget/nubia_empty_state_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_patient/presentation/widgets/nubia_empty_state.dart';

void main() {
  group('NubiaEmptyState', () {
    testWidgets('affiche le message sans CTA', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: NubiaEmptyState(
              message: 'Aucun document disponible.',
            ),
          ),
        ),
      );

      expect(find.text('Aucun document disponible.'), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('affiche le CTA quand onAction est non null', (tester) async {
      bool tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NubiaEmptyState(
              message: 'Aucun rendez-vous.',
              actionLabel: 'Prendre un RDV',
              onAction: () => tapped = true,
            ),
          ),
        ),
      );

      expect(find.text('Aucun rendez-vous.'), findsOneWidget);
      expect(find.text('Prendre un RDV'), findsOneWidget);

      await tester.tap(find.text('Prendre un RDV'));
      await tester.pump();

      expect(tapped, isTrue);
    });

    testWidgets('masque le CTA quand onAction est null', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: NubiaEmptyState(
              message: 'Aucun message.',
            ),
          ),
        ),
      );

      expect(find.byType(FilledButton), findsNothing);
    });
  });
}
