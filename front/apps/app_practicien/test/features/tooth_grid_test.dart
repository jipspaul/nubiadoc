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
      'replie les quadrants (empilés) plutôt que de rétrécir la case sous '
      'le plancher tactile de la maquette, quand les deux quadrants ne '
      'tiennent plus côte à côte à 44 px (#8203)',
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

    // Plancher tenu : la case ne rétrécit pas (contrairement à #8035/#8190,
    // où elle devenait la variable d'ajustement de la colonne centrale).
    final size = tester.getSize(find.byKey(const Key('tooth_11')));
    expect(size, const Size(44, 50));

    // Le quadrant haut-gauche (tooth_28) se replie sous le quadrant
    // haut-droit (tooth_11) au lieu de rester côte à côte hors cadre.
    final tooth11Rect = tester.getRect(find.byKey(const Key('tooth_11')));
    final tooth28Rect = tester.getRect(find.byKey(const Key('tooth_28')));
    expect(tooth28Rect.top, greaterThan(tooth11Rect.bottom - 0.5));

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

  testWidgets(
      'en dernier recours (fenêtre trop étroite même pour un quadrant seul '
      'au plancher), rétrécit la case plutôt que de déborder hors champ et '
      'incliquable (#6978)',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 300,
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
  });
}
