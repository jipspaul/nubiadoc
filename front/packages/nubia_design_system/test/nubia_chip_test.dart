import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import 'support/harness.dart';

void main() {
  group('NubiaChip', () {
    testWidgets('variante filter sans callback est annoncée désactivée', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(const NubiaChip(label: 'Suggestion')));

      final node = tester.getSemantics(find.byType(NubiaChip));
      expect(node.hasFlag(SemanticsFlag.hasEnabledState), isTrue);
      expect(node.hasFlag(SemanticsFlag.isEnabled), isFalse);
    });

    testWidgets('variante filter avec onTap est annoncée activée', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(NubiaChip(label: 'Filtre', onTap: () {})),
      );

      final node = tester.getSemantics(find.byType(NubiaChip));
      expect(node.hasFlag(SemanticsFlag.hasEnabledState), isTrue);
      expect(node.hasFlag(SemanticsFlag.isEnabled), isTrue);
    });
  });
}
