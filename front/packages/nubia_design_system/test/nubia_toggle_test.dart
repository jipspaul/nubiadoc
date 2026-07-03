import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import 'support/harness.dart';

void main() {
  group('NubiaToggle', () {
    testWidgets('affiche le label et la piste', (tester) async {
      await tester.pumpWidget(
        wrap(
          NubiaToggle(value: true, label: 'Notifications', onChanged: (_) {}),
        ),
      );

      expect(find.text('Notifications'), findsOneWidget);
      expect(find.byType(NubiaToggle), findsOneWidget);
    });

    testWidgets('bascule la valeur au tap', (tester) async {
      bool? received;
      await tester.pumpWidget(
        wrap(
          NubiaToggle(
            value: false,
            label: 'Activer',
            onChanged: (v) => received = v,
          ),
        ),
      );

      await tester.tap(find.text('Activer'));
      expect(received, isTrue);
    });

    testWidgets('désactivé quand onChanged est null', (tester) async {
      await tester.pumpWidget(
        wrap(const NubiaToggle(value: false, label: 'Off')),
      );

      // Aucun callback : le tap ne doit rien lever.
      await tester.tap(find.text('Off'));
      expect(find.text('Off'), findsOneWidget);
    });
  });
}
