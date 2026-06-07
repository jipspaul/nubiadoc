// test/widget/nubia_text_field_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_patient/presentation/widgets/nubia_text_field.dart';

void main() {
  group('NubiaTextField', () {
    testWidgets('outlined — se rend sans erreur', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: EdgeInsets.all(16),
              child: NubiaTextField(label: 'Nom'),
            ),
          ),
        ),
      );
      expect(find.byType(NubiaTextField), findsOneWidget);
    });

    testWidgets('filled — se rend sans erreur', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: EdgeInsets.all(16),
              child: NubiaTextField(
                variant: NubiaTextFieldVariant.filled,
                label: 'Prénom',
              ),
            ),
          ),
        ),
      );
      expect(find.byType(NubiaTextField), findsOneWidget);
    });

    testWidgets('search — affiche l\'icône loupe', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: EdgeInsets.all(16),
              child: NubiaTextField(
                variant: NubiaTextFieldVariant.search,
                hint: 'Rechercher…',
              ),
            ),
          ),
        ),
      );
      expect(find.byIcon(Icons.search), findsOneWidget);
    });

    testWidgets('password — affiche l\'icône visibilité', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: EdgeInsets.all(16),
              child: NubiaTextField(
                variant: NubiaTextFieldVariant.password,
                label: 'Mot de passe',
              ),
            ),
          ),
        ),
      );
      expect(find.byIcon(Icons.visibility_off), findsOneWidget);
    });

    testWidgets('password — tap icône toggle bascule la visibilité',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: EdgeInsets.all(16),
              child: NubiaTextField(
                variant: NubiaTextFieldVariant.password,
                label: 'Mot de passe',
              ),
            ),
          ),
        ),
      );
      expect(find.byIcon(Icons.visibility_off), findsOneWidget);
      await tester.tap(find.byIcon(Icons.visibility_off));
      await tester.pump();
      expect(find.byIcon(Icons.visibility), findsOneWidget);
    });

    testWidgets('multiline — se rend sans erreur', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: EdgeInsets.all(16),
              child: NubiaTextField(
                variant: NubiaTextFieldVariant.multiline,
                label: 'Commentaire',
              ),
            ),
          ),
        ),
      );
      expect(find.byType(NubiaTextField), findsOneWidget);
    });

    testWidgets('withSuffix — affiche le widget suffixe', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: EdgeInsets.all(16),
              child: NubiaTextField(
                variant: NubiaTextFieldVariant.withSuffix,
                label: 'Montant',
                suffixWidget: Text('€'),
              ),
            ),
          ),
        ),
      );
      expect(find.text('€'), findsOneWidget);
    });

    testWidgets('errorText — affiche le message d\'erreur', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: EdgeInsets.all(16),
              child: NubiaTextField(
                label: 'Email',
                errorText: 'Email invalide',
              ),
            ),
          ),
        ),
      );
      expect(find.text('Email invalide'), findsOneWidget);
    });

    testWidgets('onChanged — appelé lors de la saisie', (tester) async {
      String value = '';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: NubiaTextField(
                label: 'Texte',
                onChanged: (v) => value = v,
              ),
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'bonjour');
      await tester.pump();
      expect(value, 'bonjour');
    });
  });
}
