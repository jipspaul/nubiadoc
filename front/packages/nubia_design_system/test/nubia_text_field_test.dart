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
  });
}
