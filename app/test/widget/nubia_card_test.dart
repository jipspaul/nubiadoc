// test/widget/nubia_card_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_patient/presentation/theme/nubia_theme.dart';
import 'package:nubia_patient/presentation/widgets/nubia_card.dart';

void main() {
  Widget wrap(Widget child) {
    return MaterialApp(
      theme: NubiaTheme.light,
      home: Scaffold(body: Padding(padding: const EdgeInsets.all(16), child: child)),
    );
  }

  group('NubiaCard', () {
    testWidgets('static — se rend sans erreur', (tester) async {
      await tester.pumpWidget(
        wrap(const NubiaCard(child: Text('Contenu'))),
      );
      expect(find.byType(NubiaCard), findsOneWidget);
      expect(find.text('Contenu'), findsOneWidget);
    });

    testWidgets('interactive — déclenche onTap', (tester) async {
      bool tapped = false;
      await tester.pumpWidget(
        wrap(
          NubiaCard(
            state: NubiaCardState.interactive,
            onTap: () => tapped = true,
            child: const Text('Cliquable'),
          ),
        ),
      );
      await tester.tap(find.byType(NubiaCard));
      await tester.pump();
      expect(tapped, isTrue);
    });

    testWidgets('selected — se rend sans erreur', (tester) async {
      await tester.pumpWidget(
        wrap(
          const NubiaCard(
            state: NubiaCardState.selected,
            child: Text('Sélectionnée'),
          ),
        ),
      );
      expect(find.text('Sélectionnée'), findsOneWidget);
    });
  });
}
