//! Tests widget : panneau « Prochaine étape » (refonte consultation, lot 2 —
//! décompte de séances #4120).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_practicien/features/consultation_clinique/widgets/next_step_panel.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: NubiaTheme.light,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  testWidgets('affiche phase, décompte de séances et phase suivante',
      (tester) async {
    await tester.pumpWidget(_wrap(const NextStepPanel(
      phase: CurrentPhase(
        planId: 'p1',
        planTitle: 'Pose implant 26',
        phaseId: 'ph2',
        phaseTitle: 'Chirurgie implantaire',
        position: 2,
        phaseCount: 3,
        plannedSessions: 3,
        completedSessions: 1,
        nextPhaseTitle: 'Pilier + couronne céramique',
      ),
    )));

    expect(find.text('Chirurgie implantaire'), findsOneWidget);
    final details =
        tester.widget<Text>(find.byKey(const Key('next_step_details'))).data!;
    expect(details, contains('Phase 2/3'));
    expect(details, contains('Séance 1/3'));
    expect(find.text('Ensuite : Pilier + couronne céramique'), findsOneWidget);
  });

  testWidgets('sans planned_sessions : pas de décompte de séances',
      (tester) async {
    await tester.pumpWidget(_wrap(const NextStepPanel(
      phase: CurrentPhase(
        planId: 'p1',
        planTitle: 'Plan',
        phaseId: 'ph1',
        phaseTitle: 'Phase unique',
        position: 1,
        phaseCount: 1,
        completedSessions: 0,
      ),
    )));

    final details =
        tester.widget<Text>(find.byKey(const Key('next_step_details'))).data!;
    expect(details, isNot(contains('Séance')));
    expect(find.textContaining('Ensuite'), findsNothing);
  });
}
