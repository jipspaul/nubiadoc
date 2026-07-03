import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import 'support/harness.dart';

void main() {
  group('NubiaRadio', () {
    testWidgets('affiche le label', (tester) async {
      await tester.pumpWidget(
        wrap(
          NubiaRadio<String>(
            value: 'a',
            groupValue: 'a',
            label: 'Choix A',
            onChanged: (_) {},
          ),
        ),
      );

      expect(find.text('Choix A'), findsOneWidget);
    });

    testWidgets('sélectionne au tap et renvoie sa valeur', (tester) async {
      String? received;
      await tester.pumpWidget(
        wrap(
          NubiaRadio<String>(
            value: 'b',
            groupValue: 'a',
            label: 'Choix B',
            onChanged: (v) => received = v,
          ),
        ),
      );

      await tester.tap(find.text('Choix B'));
      expect(received, 'b');
    });

    testWidgets('ne déclenche rien quand désactivé', (tester) async {
      String? received;
      await tester.pumpWidget(
        wrap(
          const NubiaRadio<String>(
            value: 'b',
            groupValue: 'a',
            label: 'Choix B',
            onChanged: null,
          ),
        ),
      );

      await tester.tap(find.text('Choix B'));
      expect(received, isNull);
    });
  });
}
