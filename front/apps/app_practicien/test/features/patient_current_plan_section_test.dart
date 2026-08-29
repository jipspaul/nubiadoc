//! Tests widget : `PatientCurrentPlanSection` (#4977, maquette design-v2
//! §.bx) — encart résumant le plan de traitement actif du patient
//! (avancement, montant, trou de couverture), absent quand il n'y a pas de
//! plan `in_progress`.

import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_practicien/features/patients/patient_current_plan_section.dart';

class _MockListTreatmentPlans extends Mock implements ListTreatmentPlansUseCase {}

final _planInProgress = TreatmentPlan(
  id: 'plan-1',
  title: 'Réhabilitation secteur 2',
  status: 'in_progress',
  createdAt: DateTime(2026, 1, 1),
  phases: [
    TreatmentPhase(
      id: 'phase-1',
      position: 1,
      title: 'Détartrage',
      status: 'done',
      quoteRef: TreatmentPhaseQuoteRef(
        quoteNumber: 'DV-1',
        signedAt: DateTime(2025, 12, 1),
      ),
      acts: const [
        TreatmentPhaseAct(id: 'act-1', amountCents: 100000),
      ],
    ),
    TreatmentPhase(
      id: 'phase-2',
      position: 2,
      title: 'Couronne',
      status: 'in_progress',
      quoteRef: TreatmentPhaseQuoteRef(
        quoteNumber: 'DV-2',
        signedAt: DateTime(2026, 1, 5),
      ),
      acts: const [
        TreatmentPhaseAct(id: 'act-2', amountCents: 50000),
      ],
    ),
    const TreatmentPhase(
      id: 'phase-3',
      position: 3,
      title: 'Implant',
      status: 'requested',
      acts: [
        TreatmentPhaseAct(id: 'act-3', amountCents: 120000),
      ],
    ),
  ],
);

void main() {
  late _MockListTreatmentPlans listPlans;

  setUp(() {
    listPlans = _MockListTreatmentPlans();
    GetIt.instance.registerFactory<ListTreatmentPlansUseCase>(() => listPlans);
    addTearDown(GetIt.instance.reset);
  });

  Widget buildSection() => MaterialApp(
        theme: NubiaTheme.light,
        home: const Scaffold(
          body: PatientCurrentPlanSection(patientId: 'patient-1'),
        ),
      );

  testWidgets('aucun plan — encart absent', (tester) async {
    when(() => listPlans('patient-1')).thenAnswer((_) async => const Right([]));

    await tester.pumpWidget(buildSection());
    await tester.pumpAndSettle();

    expect(find.byType(NubiaCard), findsNothing);
  });

  testWidgets('aucun plan in_progress — encart absent', (tester) async {
    when(() => listPlans('patient-1')).thenAnswer(
      (_) async => Right([
        TreatmentPlan(
          id: 'plan-done',
          title: 'Ancien plan',
          status: 'done',
          createdAt: DateTime(2026, 1, 1),
          phases: const [],
        ),
      ]),
    );

    await tester.pumpWidget(buildSection());
    await tester.pumpAndSettle();

    expect(find.byType(NubiaCard), findsNothing);
  });

  testWidgets(
      'plan en cours — titre, avancement, montant et alerte de trou de couverture',
      (tester) async {
    when(() => listPlans('patient-1'))
        .thenAnswer((_) async => Right([_planInProgress]));

    await tester.pumpWidget(buildSection());
    await tester.pumpAndSettle();

    expect(find.text('Plan en cours'), findsOneWidget);
    expect(find.text('Réhabilitation secteur 2'), findsOneWidget);
    expect(find.text('phase 2 / 3'), findsOneWidget);
    expect(find.text('1 phase terminée sur 3'), findsOneWidget);
    expect(find.text('2 700,00 €'), findsOneWidget);
    expect(
      find.textContaining('1 200,00 €'),
      findsOneWidget,
    );
    expect(
      find.textContaining("la phase 3 n'a pas été acceptée par le patient"),
      findsOneWidget,
    );
  });

  testWidgets('plan sans trou de couverture — pas d\'alerte', (tester) async {
    when(() => listPlans('patient-1')).thenAnswer(
      (_) async => Right([
        TreatmentPlan(
          id: 'plan-covered',
          title: 'Plan couvert',
          status: 'in_progress',
          createdAt: DateTime(2026, 1, 1),
          phases: [
            TreatmentPhase(
              id: 'phase-1',
              position: 1,
              title: 'Détartrage',
              status: 'in_progress',
              quoteRef: TreatmentPhaseQuoteRef(
                quoteNumber: 'DV-1',
                signedAt: DateTime(2026, 1, 2),
              ),
              acts: const [
                TreatmentPhaseAct(id: 'act-1', amountCents: 10000),
              ],
            ),
          ],
        ),
      ]),
    );

    await tester.pumpWidget(buildSection());
    await tester.pumpAndSettle();

    expect(find.text('Plan couvert'), findsOneWidget);
    expect(find.byKey(const Key('patient_current_plan_gap_plan-covered')),
        findsNothing);
  });
}
