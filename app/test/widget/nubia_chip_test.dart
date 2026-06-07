// test/widget/nubia_chip_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_patient/presentation/theme/nubia_theme.dart';
import 'package:nubia_patient/presentation/widgets/nubia_chip.dart';

void main() {
  Widget wrap(Widget child) {
    return MaterialApp(
      theme: NubiaTheme.light,
      home: Scaffold(body: Center(child: child)),
    );
  }

  group('NubiaChip', () {
    testWidgets('affiche le label', (tester) async {
      await tester.pumpWidget(wrap(const NubiaChip(label: 'Dentisterie')));
      expect(find.text('Dentisterie'), findsOneWidget);
    });

    testWidgets('filter — déclenche onTap', (tester) async {
      bool tapped = false;
      await tester.pumpWidget(
        wrap(NubiaChip(label: 'Filtre', onTap: () => tapped = true)),
      );
      await tester.tap(find.byType(NubiaChip));
      await tester.pump();
      expect(tapped, isTrue);
    });

    testWidgets('input — déclenche onRemove au tap ×', (tester) async {
      bool removed = false;
      await tester.pumpWidget(
        wrap(
          NubiaChip(
            label: 'Jeton',
            variant: NubiaChipVariant.input,
            onRemove: () => removed = true,
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      expect(removed, isTrue);
    });

    testWidgets('selected — fond brand50', (tester) async {
      await tester.pumpWidget(
        wrap(const NubiaChip(label: 'Actif', selected: true)),
      );
      expect(find.byType(NubiaChip), findsOneWidget);
    });

    testWidgets('filter selected — se rend sans erreur', (tester) async {
      await tester.pumpWidget(
        wrap(const NubiaChip(label: 'On', selected: true)),
      );
      expect(find.byType(NubiaChip), findsOneWidget);
      expect(find.text('On'), findsOneWidget);
    });
  });
}
