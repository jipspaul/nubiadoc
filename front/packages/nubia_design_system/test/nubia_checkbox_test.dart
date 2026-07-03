import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import 'support/harness.dart';

void main() {
  group('NubiaCheckbox', () {
    testWidgets('affiche le label et la coche quand coché', (tester) async {
      await tester.pumpWidget(
        wrap(NubiaCheckbox(value: true, label: 'Accepter', onChanged: (_) {})),
      );

      expect(find.text('Accepter'), findsOneWidget);
      expect(find.byIcon(Icons.check), findsOneWidget);
    });

    testWidgets('affiche le tiret en état mixed', (tester) async {
      await tester.pumpWidget(
        wrap(NubiaCheckbox(value: null, tristate: true, onChanged: (_) {})),
      );

      expect(find.byIcon(Icons.remove), findsOneWidget);
    });

    testWidgets('bascule off -> on au tap', (tester) async {
      bool? received;
      await tester.pumpWidget(
        wrap(
          NubiaCheckbox(
            value: false,
            label: 'Option',
            onChanged: (v) => received = v,
          ),
        ),
      );

      await tester.tap(find.text('Option'));
      expect(received, isTrue);
    });

    testWidgets('désactivé quand onChanged est null', (tester) async {
      await tester.pumpWidget(
        wrap(const NubiaCheckbox(value: false, label: 'Off')),
      );

      // Aucun callback : le tap ne doit rien lever.
      await tester.tap(find.text('Off'));
      expect(find.text('Off'), findsOneWidget);
    });
  });
}
