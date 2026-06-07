// test/widget/nubia_button_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_patient/presentation/widgets/nubia_button.dart';

void main() {
  group('NubiaButton', () {
    testWidgets('primary — se rend sans erreur', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(child: NubiaButton(label: 'Valider')),
          ),
        ),
      );
      expect(find.byType(NubiaButton), findsOneWidget);
      expect(find.text('Valider'), findsOneWidget);
    });

    testWidgets('primary — déclenche onPressed au tap', (tester) async {
      bool pressed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: NubiaButton(
                label: 'Valider',
                onPressed: () => pressed = true,
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(NubiaButton));
      await tester.pump();
      expect(pressed, isTrue);
    });

    testWidgets('désactivé quand onPressed est null', (tester) async {
      bool pressed = false;
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: NubiaButton(
                label: 'Désactivé',
                onPressed: null,
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(NubiaButton));
      await tester.pump();
      expect(pressed, isFalse);
    });

    testWidgets('secondary — se rend sans erreur', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: NubiaButton(
                label: 'Annuler',
                variant: NubiaButtonVariant.secondary,
              ),
            ),
          ),
        ),
      );
      expect(find.byType(OutlinedButton), findsOneWidget);
    });

    testWidgets('tertiary — se rend sans erreur', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: NubiaButton(
                label: 'En savoir plus',
                variant: NubiaButtonVariant.tertiary,
              ),
            ),
          ),
        ),
      );
      expect(find.byType(TextButton), findsOneWidget);
    });

    testWidgets('destructive — se rend sans erreur', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: NubiaButton(
                label: 'Supprimer',
                variant: NubiaButtonVariant.destructive,
                onPressed: () {},
              ),
            ),
          ),
        ),
      );
      expect(find.text('Supprimer'), findsOneWidget);
    });

    testWidgets('size sm — se rend sans erreur', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: NubiaButton(
                label: 'Petit',
                size: NubiaButtonSize.sm,
                onPressed: () {},
              ),
            ),
          ),
        ),
      );
      expect(find.byType(NubiaButton), findsOneWidget);
    });

    testWidgets('size lg — se rend sans erreur', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: NubiaButton(
                label: 'Grand',
                size: NubiaButtonSize.lg,
                onPressed: () {},
              ),
            ),
          ),
        ),
      );
      expect(find.byType(NubiaButton), findsOneWidget);
    });

    testWidgets('isLoading — affiche CircularProgressIndicator', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: NubiaButton(
                label: 'Chargement',
                onPressed: () {},
                isLoading: true,
              ),
            ),
          ),
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('icon — affiche l\'icône', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: NubiaButton(
                label: 'Avec icône',
                icon: Icons.add,
                onPressed: () {},
              ),
            ),
          ),
        ),
      );
      expect(find.byIcon(Icons.add), findsOneWidget);
    });
  });
}
