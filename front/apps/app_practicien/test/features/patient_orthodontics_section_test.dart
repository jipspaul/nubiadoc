//! Tests widget : `PatientOrthodonticsSection` (#4135/#4136) — liste
//! triée par step_number, ajout d'étape en fin de liste.
//!
//! Pas de golden test : aucune infra golden-test n'existe dans ce dépôt
//! (même choix documenté que #4133, `patient_documents_section_test.dart`).
//! Ce test widget standard couvre la même assertion comportementale.

import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_practicien/features/patients/patient_fiche.dart';

class _MockListOrthodonticTreatments extends Mock
    implements ListOrthodonticTreatmentsUseCase {}

class _MockAddOrthodonticStep extends Mock
    implements AddOrthodonticStepUseCase {}

const _treatmentInProgress = OrthodonticTreatment(
  id: 'treat-1',
  type: 'multi-attache',
  semesterCount: 4,
  status: 'in_progress',
  steps: [
    OrthodonticStep(id: 'step-2', stepNumber: 2, kind: 'contention'),
    OrthodonticStep(id: 'step-1', stepNumber: 1, kind: 'bague'),
  ],
);

void main() {
  late _MockListOrthodonticTreatments listTreatments;
  late _MockAddOrthodonticStep addStep;

  setUp(() {
    listTreatments = _MockListOrthodonticTreatments();
    addStep = _MockAddOrthodonticStep();
    GetIt.instance.registerFactory<ListOrthodonticTreatmentsUseCase>(
      () => listTreatments,
    );
    GetIt.instance.registerFactory<AddOrthodonticStepUseCase>(() => addStep);
    addTearDown(GetIt.instance.reset);
  });

  Widget buildSection() => MaterialApp(
        theme: NubiaTheme.light,
        home: Scaffold(
          body: const PatientOrthodonticsSection(patientId: 'patient-1'),
        ),
      );

  testWidgets('aucun traitement en cours — affiche le message vide',
      (tester) async {
    when(() => listTreatments('patient-1'))
        .thenAnswer((_) async => const Right([]));

    await tester.pumpWidget(buildSection());
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('patient_orthodontics_empty')),
      findsOneWidget,
    );
  });

  testWidgets('liste triée par step_number même si l\'API renvoie 2 puis 1',
      (tester) async {
    when(() => listTreatments('patient-1'))
        .thenAnswer((_) async => const Right([_treatmentInProgress]));

    await tester.pumpWidget(buildSection());
    await tester.pumpAndSettle();

    final rows = tester
        .widgetList<ListRow>(find.byType(ListRow))
        .map((r) => r.title)
        .toList();
    expect(rows, ['1. Bague', '2. Contention']);
  });

  testWidgets('ajouter une étape l\'ajoute en fin de liste (step_number 3)',
      (tester) async {
    when(() => listTreatments('patient-1'))
        .thenAnswer((_) async => const Right([_treatmentInProgress]));
    when(() => addStep('treat-1', stepNumber: 3, kind: 'gouttiere'))
        .thenAnswer((_) async => const Right('step-3'));

    await tester.pumpWidget(buildSection());
    await tester.pumpAndSettle();

    await tester
        .tap(find.byKey(const Key('patient_orthodontics_add_step_button')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('ortho_step_kind_gouttiere')));
    await tester.pumpAndSettle();

    verify(() => addStep('treat-1', stepNumber: 3, kind: 'gouttiere'))
        .called(1);
  });
}
