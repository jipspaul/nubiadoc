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
            stateFor: (_) => ToothVisual(background: Colors.grey.shade100),
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

  testWidgets(
      'rétrécit les dents pour tenir dans une carte étroite plutôt que de '
      'les laisser déborder hors champ et incliquables (#6978)',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 600,
              child: ToothGrid(
                quadrants: FdiQuadrants.permanent,
                keyPrefix: 'tooth',
                stateFor: (_) => ToothVisual(background: Colors.grey.shade100),
                onTap: (_) {},
                toothSize: const Size(44, 50),
              ),
            ),
          ),
        ),
      ),
    );

    final gridRight = tester.getRect(find.byType(ToothGrid)).right;
    final tooth28Right = tester.getRect(find.byKey(const Key('tooth_28'))).right;
    expect(tooth28Right, lessThanOrEqualTo(gridRight + 0.5));

    final size = tester.getSize(find.byKey(const Key('tooth_11')));
    expect(size.width, lessThan(44));
    expect(size.height, 50);

    String? tapped;
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 600,
              child: ToothGrid(
                quadrants: FdiQuadrants.permanent,
                keyPrefix: 'tooth',
                stateFor: (_) => ToothVisual(background: Colors.grey.shade100),
                onTap: (code) => tapped = code,
                toothSize: const Size(44, 50),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('tooth_28')));
    expect(tapped, '28');
  });
}
