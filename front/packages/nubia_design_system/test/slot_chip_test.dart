import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: NubiaTheme.light,
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  group('SlotChip', () {
    testWidgets('état disponible : affiche le libellé et réagit au tap', (
      tester,
    ) async {
      var tapped = 0;
      await tester.pumpWidget(
        _wrap(SlotChip(label: '14:30', onTap: () => tapped++)),
      );

      expect(find.text('14:30'), findsOneWidget);
      await tester.tap(find.byType(SlotChip));
      await tester.pumpAndSettle();
      expect(tapped, 1);
    });

    testWidgets('état loading : affiche un spinner et pas de libellé', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(const SlotChip(label: '15:00', state: SlotChipState.loading)),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('15:00'), findsNothing);
    });

    testWidgets('état indisponible : n\'appelle pas onTap', (tester) async {
      var tapped = 0;
      await tester.pumpWidget(
        _wrap(
          SlotChip(
            label: '16:15',
            state: SlotChipState.unavailable,
            onTap: () => tapped++,
          ),
        ),
      );

      await tester.tap(find.byType(SlotChip));
      await tester.pumpAndSettle();
      expect(tapped, 0);

      // Indisponible : le libellé est barré.
      final label = tester.widget<Text>(find.text('16:15'));
      expect(label.style?.decoration, TextDecoration.lineThrough);
    });

    testWidgets('état sélectionné : fond brand/50 et texte brand', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          SlotChip(label: '14:30', state: SlotChipState.selected, onTap: () {}),
        ),
      );

      final material = tester.widget<Material>(
        find.descendant(
          of: find.byType(SlotChip),
          matching: find.byType(Material),
        ),
      );
      expect(material.color, NubiaTokens.light.primarySubtleBg);

      final label = tester.widget<Text>(find.text('14:30'));
      expect(label.style?.color, NubiaTokens.light.primarySubtleFg);
    });
  });
}
