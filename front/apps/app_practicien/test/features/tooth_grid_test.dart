//! Tests widget : `ToothGrid`/`ToothButton` (#4940) — taille des cibles
//! tactiles, paramétrable sans régresser la taille par défaut (32×32).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app_practicien/features/dental_chart/tooth_grid.dart';

void main() {
  Widget buildGrid({Size? toothSize}) => MaterialApp(
        home: Material(
          child: ToothGrid(
            quadrants: FdiQuadrants.permanent,
            keyPrefix: 'tooth',
            colorFor: (_) => Colors.grey.shade100,
            onTap: (_) {},
            toothSize: toothSize ?? ToothButton.defaultSize,
          ),
        ),
      );

  testWidgets('taille par défaut des dents = 32×32 (schéma dentaire patient)',
      (tester) async {
    await tester.pumpWidget(buildGrid());

    final size = tester.getSize(find.byKey(const Key('tooth_11')));
    expect(size, const Size(32, 32));
  });

  testWidgets('taille des dents = 44×50 sur la consultation PC (#4940)',
      (tester) async {
    await tester.pumpWidget(buildGrid(toothSize: const Size(44, 50)));

    final size = tester.getSize(find.byKey(const Key('tooth_11')));
    expect(size, const Size(44, 50));
  });

  testWidgets('le libellé de la dent reste centré et lisible', (tester) async {
    await tester.pumpWidget(buildGrid(toothSize: const Size(44, 50)));

    expect(find.text('11'), findsOneWidget);
  });
}
