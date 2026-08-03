//! Tests widget : panneau « Actes de la séance » (refonte consultation,
//! lot 2 — total en en-tête, dernier acte surligné, montants).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_practicien/features/consultation_clinique/widgets/session_act_row.dart';
import 'package:app_practicien/features/consultation_clinique/widgets/session_acts_panel.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: NubiaTheme.light,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

const _acts = [
  ClinicalAct(
      id: 'a1', ccamCode: 'LBLA001', label: 'Anesthésie', amountCents: null),
  ClinicalAct(
      id: 'a2',
      ccamCode: 'HBLD036',
      label: 'Pose implant',
      tooth: '26',
      amountCents: 95000),
];

ClinicalSession _session(List<ClinicalAct> acts,
        {String status = 'in_progress'}) =>
    ClinicalSession(id: 's1', appointmentId: 'ap1', status: status, acts: acts);

void main() {
  testWidgets('en-tête : nombre d\'actes et total', (tester) async {
    await tester.pumpWidget(_wrap(SessionActsPanel(session: _session(_acts))));

    expect(
      tester.widget<Text>(find.byKey(const Key('session_acts_total'))).data,
      '2 acte(s) CCAM · 950.00 €',
    );
  });

  testWidgets('lignes d\'actes : clé stable, dent, montant ou « incluse »',
      (tester) async {
    await tester.pumpWidget(_wrap(SessionActsPanel(session: _session(_acts))));

    expect(find.byKey(const Key('act_a1')), findsOneWidget);
    expect(find.byKey(const Key('act_a2')), findsOneWidget);
    expect(find.text('HBLD036 · Dent 26'), findsOneWidget);
    expect(find.text('950.00 €'), findsOneWidget);
    expect(find.text('incluse'), findsOneWidget);
  });

  testWidgets('le dernier acte est surligné tant que la séance est en cours',
      (tester) async {
    await tester.pumpWidget(_wrap(SessionActsPanel(session: _session(_acts))));

    final rows =
        tester.widgetList<SessionActRow>(find.byType(SessionActRow)).toList();
    expect(rows.first.highlighted, isFalse);
    expect(rows.last.highlighted, isTrue);
  });

  testWidgets('aucun acte surligné sur une séance terminée', (tester) async {
    await tester.pumpWidget(
        _wrap(SessionActsPanel(session: _session(_acts, status: 'completed'))));

    final rows =
        tester.widgetList<SessionActRow>(find.byType(SessionActRow)).toList();
    expect(rows.every((r) => !r.highlighted), isTrue);
  });

  testWidgets('sans acte : empty state', (tester) async {
    await tester
        .pumpWidget(_wrap(SessionActsPanel(session: _session(const []))));

    expect(find.byKey(const Key('consultation_empty')), findsOneWidget);
  });
}
