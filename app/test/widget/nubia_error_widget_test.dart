// test/widget/nubia_error_widget_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_patient/presentation/widgets/nubia_error_widget.dart';

void main() {
  group('NubiaErrorWidget', () {
    testWidgets('affiche le message d\'erreur', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: NubiaErrorWidget(message: 'Erreur réseau.'),
          ),
        ),
      );
      expect(find.text('Erreur réseau.'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('masque le bouton Réessayer quand onRetry est null',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: NubiaErrorWidget(message: 'Erreur.'),
          ),
        ),
      );
      expect(find.text('Réessayer'), findsNothing);
    });

    testWidgets('affiche et déclenche le bouton Réessayer', (tester) async {
      bool retried = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NubiaErrorWidget(
              message: 'Connexion impossible.',
              onRetry: () => retried = true,
            ),
          ),
        ),
      );
      expect(find.text('Réessayer'), findsOneWidget);
      await tester.tap(find.text('Réessayer'));
      await tester.pump();
      expect(retried, isTrue);
    });
  });
}
