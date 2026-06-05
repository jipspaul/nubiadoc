import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_demo/theme/nubia_colors.dart';
import 'package:flutter_demo/theme/nubia_tokens.dart';
import 'package:flutter_demo/widgets/nubia_chip.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: ThemeData(extensions: const [NubiaTokens.light]),
    home: Scaffold(body: Center(child: child)),
  );
}

Material _chipMaterial(WidgetTester tester) {
  return tester.widget<Material>(
    find.descendant(
      of: find.byType(NubiaChip),
      matching: find.byType(Material),
    ),
  );
}

void main() {
  group('NubiaChip', () {
    testWidgets('renders the label', (tester) async {
      await tester.pumpWidget(_wrap(const NubiaChip(label: 'Disponible')));
      expect(find.text('Disponible'), findsOneWidget);
    });

    testWidgets('calls onTap when tapped', (tester) async {
      var tapped = 0;
      await tester.pumpWidget(_wrap(
        NubiaChip(label: 'Filtre', onTap: () => tapped++),
      ));

      await tester.tap(find.byType(NubiaChip));
      await tester.pump();

      expect(tapped, 1);
    });

    testWidgets('input variant calls onRemove when × is tapped',
        (tester) async {
      var removed = 0;
      await tester.pumpWidget(_wrap(
        NubiaChip(
          label: 'Paris',
          variant: NubiaChipVariant.input,
          onRemove: () => removed++,
        ),
      ));

      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();

      expect(removed, 1);
    });

    testWidgets('selected: true shows brand50 background', (tester) async {
      await tester.pumpWidget(_wrap(
        NubiaChip(label: 'Actif', selected: true, onTap: () {}),
      ));

      expect(_chipMaterial(tester).color, NubiaColors.brand50);
    });

    testWidgets('exposes toggled semantics for the filter variant',
        (tester) async {
      await tester.pumpWidget(_wrap(
        NubiaChip(label: 'Filtre', selected: true, onTap: () {}),
      ));

      final semantics = tester.widget<Semantics>(
        find
            .descendant(
              of: find.byType(NubiaChip),
              matching: find.byType(Semantics),
            )
            .first,
      );
      expect(semantics.properties.toggled, isTrue);
    });
  });
}
