import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_practicien/features/consultation_clinique/widgets/active_plan_box.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        theme: NubiaTheme.light,
        home: Scaffold(body: child),
      );

  const plan = ActivePlanSummary(
    id: 'plan-1',
    title: 'Réhabilitation secteur 2',
    currentPhase: 2,
    totalPhases: 3,
    totalCostCents: 163592,
  );

  testWidgets(
      'affiche le titre du plan, la progression et le montant en euros',
      (tester) async {
    await tester.pumpWidget(
      wrap(const ActivePlanBox(patientId: 'patient-1', plan: plan)),
    );

    expect(find.byKey(const Key('active_plan_box')), findsOneWidget);
    expect(find.text('Plan en cours'), findsOneWidget);
    expect(find.text('Réhabilitation secteur 2'), findsOneWidget);
    expect(find.text('Phase 2 sur 3 · 1 635,92 €'), findsOneWidget);
    expect(find.byIcon(Icons.assignment), findsOneWidget);
    expect(find.text('Ouvrir le plan'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_forward), findsOneWidget);
    expect(find.byKey(const Key('active_plan_open_link')), findsOneWidget);
  });
}
