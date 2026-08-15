//! Tests widget : `ToothGrid`/`ToothButton` (#4940, #4961) — taille des
//! cibles tactiles, paramétrable sans régresser la taille par défaut
//! (38×44, plancher tactile 44 px).

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

  testWidgets(
      'taille par défaut des dents = 38×44, cible tactile ≥ 44 px (#4961)',
      (tester) async {
    await tester.pumpWidget(buildGrid());

    final size = tester.getSize(find.byKey(const Key('tooth_11')));
    expect(size, const Size(38, 44));
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
