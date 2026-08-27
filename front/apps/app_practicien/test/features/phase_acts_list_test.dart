//! Tests widget : `PhaseActsList` (#5015) — rendu des actes d'une phase
//! (badge dent, libellé, chip CCAM, sous-titre, montant).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import 'package:app_practicien/features/treatment_plans/widgets/phase_acts_list.dart';

void main() {
  Widget buildList(List<PhaseActRow> acts) => MaterialApp(
        theme: NubiaTheme.light,
        home: Scaffold(body: PhaseActsList(acts: acts)),
      );

  testWidgets('liste vide ne rend rien', (tester) async {
    await tester.pumpWidget(buildList(const []));

    expect(find.byKey(const Key('treatment_phase_act_act-1')), findsNothing);
  });

  testWidgets('affiche badge dent, libellé, chip CCAM, sous-titre, montant',
      (tester) async {
    await tester.pumpWidget(buildList(const [
      PhaseActRow(
        id: 'act-1',
        tooth: '26',
        label: 'Restauration 2 faces',
        ccamCode: 'HBMD042',
        subtitle: 'Réalisé le 22/07',
        amountCents: 5350,
      ),
      PhaseActRow(
        id: 'act-2',
        tooth: null,
        label: 'Détartrage complet',
        ccamCode: 'HBJD001',
        subtitle: 'À programmer',
        amountCents: 2892,
      ),
    ]));

    expect(find.byKey(const Key('treatment_phase_act_act-1')), findsOneWidget);
    expect(find.byKey(const Key('treatment_phase_act_act-2')), findsOneWidget);

    expect(find.text('26'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
    expect(find.text('Restauration 2 faces'), findsOneWidget);
    expect(find.text('Détartrage complet'), findsOneWidget);
    expect(find.text('HBMD042'), findsOneWidget);
    expect(find.text('HBJD001'), findsOneWidget);
    expect(find.text('Réalisé le 22/07'), findsOneWidget);
    expect(find.text('À programmer'), findsOneWidget);
    expect(find.text('53,50 €'), findsOneWidget);
    expect(find.text('28,92 €'), findsOneWidget);

    final ccamText = tester.widget<Text>(find.text('HBMD042'));
    expect(ccamText.style?.fontFamily, 'monospace');
  });
}
