import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: NubiaTheme.light,
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  group('SegmentedControl', () {
    testWidgets('affiche tous les segments', (tester) async {
      await tester.pumpWidget(
        _wrap(
          SegmentedControl(
            segments: const ['À venir', 'Historique'],
            selectedIndex: 0,
            onChanged: (_) {},
          ),
        ),
      );

      expect(find.text('À venir'), findsOneWidget);
      expect(find.text('Historique'), findsOneWidget);
    });

    testWidgets('notifie l\'index au tap sur un segment', (tester) async {
      int? selected;
      await tester.pumpWidget(
        _wrap(
          SegmentedControl(
            segments: const ['À venir', 'Historique'],
            selectedIndex: 0,
            onChanged: (i) => selected = i,
          ),
        ),
      );

      await tester.tap(find.text('Historique'));
      await tester.pumpAndSettle();
      expect(selected, 1);
    });

    testWidgets('segment actif : texte brand et poids renforcé', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          SegmentedControl(
            segments: const ['À venir', 'Historique', 'Tous'],
            selectedIndex: 1,
            onChanged: (_) {},
          ),
        ),
      );

      final active = tester.widget<Text>(find.text('Historique'));
      expect(active.style?.color, NubiaTokens.light.primarySubtleFg);
      expect(active.style?.fontWeight, FontWeight.w600);

      final inactive = tester.widget<Text>(find.text('À venir'));
      expect(inactive.style?.fontWeight, FontWeight.w500);
    });
  });
}
