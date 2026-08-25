import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import 'support/harness.dart';

void main() {
  group('NubiaTextField — variantes de saisie', () {
    testWidgets('amount affiche le suffixe € et un clavier numérique', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          const NubiaTextField(
            variant: NubiaTextFieldVariant.amount,
            label: 'Montant',
          ),
        ),
      );

      expect(find.text('€'), findsOneWidget);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(
        field.keyboardType,
        const TextInputType.numberWithOptions(decimal: true),
      );
    });

    testWidgets('phone utilise le clavier téléphone et une icône préfixe', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          const NubiaTextField(
            variant: NubiaTextFieldVariant.phone,
            label: 'Téléphone',
          ),
        ),
      );

      expect(find.byIcon(Icons.phone_outlined), findsOneWidget);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.keyboardType, TextInputType.phone);
    });

    testWidgets('multiline autorise plusieurs lignes', (tester) async {
      await tester.pumpWidget(
        wrap(
          const NubiaTextField(
            variant: NubiaTextFieldVariant.multiline,
            label: 'Notes',
          ),
        ),
      );

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.maxLines, 4);
    });

    testWidgets('amount notifie onChanged', (tester) async {
      String? typed;
      await tester.pumpWidget(
        wrap(
          NubiaTextField(
            variant: NubiaTextFieldVariant.amount,
            onChanged: (v) => typed = v,
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), '42');
      expect(typed, '42');
    });

    // #4538 : Entrée doit soumettre (réflexe universel dans un chat) quand
    // onSubmitted est fourni — comportement inchangé (pas de textInputAction
    // forcé) sinon.
    testWidgets('onSubmitted appelé à la validation clavier (Entrée)', (
      tester,
    ) async {
      String? submitted;
      await tester.pumpWidget(
        wrap(
          NubiaTextField(
            hint: 'Écrire un message…',
            onSubmitted: (v) => submitted = v,
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'Bonjour');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump();

      expect(submitted, 'Bonjour');
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.textInputAction, TextInputAction.send);
    });

    testWidgets('sans onSubmitted, textInputAction reste par défaut (null)', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(const NubiaTextField(hint: 'Nom')),
      );

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.textInputAction, isNull);
    });

    // #5177 : quantité stock — clavier numérique, pas à pas, plancher à 1.
    group('numberStepper', () {
      testWidgets('utilise un clavier numérique et filtre les non-chiffres', (
        tester,
      ) async {
        final controller = TextEditingController(text: '1');
        await tester.pumpWidget(
          wrap(
            NubiaTextField(
              key: const Key('qty'),
              variant: NubiaTextFieldVariant.numberStepper,
              controller: controller,
              label: 'Qté',
            ),
          ),
        );

        final field = tester.widget<TextField>(find.byType(TextField));
        expect(field.keyboardType, TextInputType.number);

        await tester.enterText(find.byType(TextField), 'abc12def');
        expect(controller.text, '12');
      });

      testWidgets('le bouton + incrémente la valeur', (tester) async {
        final controller = TextEditingController(text: '1');
        await tester.pumpWidget(
          wrap(
            NubiaTextField(
              variant: NubiaTextFieldVariant.numberStepper,
              controller: controller,
              label: 'Qté',
            ),
          ),
        );

        await tester.tap(find.byIcon(Icons.add));
        await tester.pump();

        expect(controller.text, '2');
      });

      testWidgets('le bouton - est désactivé au plancher (1)', (
        tester,
      ) async {
        final controller = TextEditingController(text: '1');
        await tester.pumpWidget(
          wrap(
            NubiaTextField(
              variant: NubiaTextFieldVariant.numberStepper,
              controller: controller,
              label: 'Qté',
            ),
          ),
        );

        final minusButton = tester.widget<IconButton>(
          find.ancestor(
            of: find.byIcon(Icons.remove),
            matching: find.byType(IconButton),
          ),
        );
        expect(minusButton.onPressed, isNull);

        await tester.tap(find.byIcon(Icons.add));
        await tester.pump();
        expect(controller.text, '2');

        await tester.tap(find.byIcon(Icons.remove));
        await tester.pump();
        expect(controller.text, '1');
      });

      testWidgets('la perte de focus ramène une valeur invalide à 1', (
        tester,
      ) async {
        final controller = TextEditingController(text: '1');
        await tester.pumpWidget(
          wrap(
            Column(
              children: [
                NubiaTextField(
                  variant: NubiaTextFieldVariant.numberStepper,
                  controller: controller,
                  label: 'Qté',
                ),
                const TextField(),
              ],
            ),
          ),
        );

        await tester.enterText(find.byType(TextField).first, '');
        await tester.tap(find.byType(TextField).last);
        await tester.pump();

        expect(controller.text, '1');
      });
    });
  });
}
