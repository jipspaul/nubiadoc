import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_practicien/features/patients/patient_fiche.dart';

class _MockListPatientDocuments extends Mock
    implements ListPatientDocumentsUseCase {}

class _MockListPatientJournal extends Mock
    implements ListPatientJournalUseCase {}

class _MockGetMedicalRecord extends Mock implements GetMedicalRecordUseCase {}

class _MockListTreatmentPlans extends Mock
    implements ListTreatmentPlansUseCase {}

class _MockListOrthodonticTreatments extends Mock
    implements ListOrthodonticTreatmentsUseCase {}

class _MockGetCabinetMedicalQuestionnaire extends Mock
    implements GetCabinetMedicalQuestionnaireUseCase {}

final _patient = CabinetPatient(
  id: 'pat-1',
  cabinetId: 'cab-1',
  firstName: 'Julie',
  lastName: 'Martin',
  createdAt: DateTime(2024, 1, 1),
);

// #4982, maquette design-v2 point 8 : cinq onglets (Journal, Plans de
// traitement, Documents, Questionnaire médical, Facturation) en lieu et
// place des deux onglets Résumé/Documents de #4133.
void main() {
  late _MockListTreatmentPlans listTreatmentPlans;

  setUp(() {
    final listDocuments = _MockListPatientDocuments();
    when(() => listDocuments(any(), category: any(named: 'category')))
        .thenAnswer((_) async => const Right([]));
    GetIt.instance
        .registerFactory<ListPatientDocumentsUseCase>(() => listDocuments);

    final listJournal = _MockListPatientJournal();
    when(() => listJournal(any())).thenAnswer((_) async => const Right([]));
    GetIt.instance
        .registerFactory<ListPatientJournalUseCase>(() => listJournal);

    final getMedicalRecord = _MockGetMedicalRecord();
    when(() => getMedicalRecord(any())).thenAnswer(
      (_) async =>
          const Right(MedicalRecordSummary(allergies: [], treatments: [])),
    );
    GetIt.instance
        .registerFactory<GetMedicalRecordUseCase>(() => getMedicalRecord);

    listTreatmentPlans = _MockListTreatmentPlans();
    when(() => listTreatmentPlans(any()))
        .thenAnswer((_) async => const Right([]));
    GetIt.instance
        .registerFactory<ListTreatmentPlansUseCase>(() => listTreatmentPlans);

    final listOrthodonticTreatments = _MockListOrthodonticTreatments();
    when(() => listOrthodonticTreatments(any()))
        .thenAnswer((_) async => const Right([]));
    GetIt.instance.registerFactory<ListOrthodonticTreatmentsUseCase>(
      () => listOrthodonticTreatments,
    );

    final getQuestionnaire = _MockGetCabinetMedicalQuestionnaire();
    when(() => getQuestionnaire(any()))
        .thenAnswer((_) async => const Right(null));
    GetIt.instance.registerFactory<GetCabinetMedicalQuestionnaireUseCase>(
      () => getQuestionnaire,
    );

    addTearDown(GetIt.instance.reset);
  });

  Finder tabLabel(String text) => find.descendant(
        of: find.byKey(const Key('patient_fiche_tabs')),
        matching: find.text(text),
      );

  Future<void> pumpFiche(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: NubiaTheme.light,
        home: PatientFiche(patient: _patient),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('affiche cinq onglets, dans l\'ordre de la maquette',
      (tester) async {
    await pumpFiche(tester);

    expect(find.byKey(const Key('patient_fiche_tabs')), findsOneWidget);
    expect(find.byWidgetPredicate((w) => w is Tab), findsNWidgets(5));

    for (final label in const [
      'Journal',
      'Plans de traitement',
      'Documents',
      'Questionnaire médical',
      'Facturation',
    ]) {
      expect(tabLabel(label), findsOneWidget, reason: label);
    }
  });

  testWidgets(
      'le badge « Plans de traitement » affiche le compte une fois les '
      'plans chargés', (tester) async {
    when(() => listTreatmentPlans(any())).thenAnswer(
      (_) async => Right([
        TreatmentPlan(
          id: 'plan-1',
          title: 'Réhabilitation complète',
          status: 'in_progress',
          createdAt: DateTime(2024, 1, 1),
          phases: const [],
        ),
        TreatmentPlan(
          id: 'plan-2',
          title: 'Implant 26',
          status: 'draft',
          createdAt: DateTime(2024, 2, 1),
          phases: const [],
        ),
      ]),
    );

    await pumpFiche(tester);

    final planTab = find.ancestor(
      of: tabLabel('Plans de traitement'),
      matching: find.byWidgetPredicate((w) => w is Tab),
    );
    expect(
        find.descendant(of: planTab, matching: find.text('2')), findsOneWidget);
  });

  testWidgets('aucun badge sur « Documents » quand la liste est vide',
      (tester) async {
    await pumpFiche(tester);

    final documentsTab = find.ancestor(
      of: tabLabel('Documents'),
      matching: find.byWidgetPredicate((w) => w is Tab),
    );
    expect(find.descendant(of: documentsTab, matching: find.byType(NubiaBadge)),
        findsNothing);
  });

  testWidgets(
      'l\'onglet Plans de traitement affiche l\'encart des plans et le '
      'suivi orthodontique — plus dans le défilement unique', (tester) async {
    await pumpFiche(tester);

    await tester.ensureVisible(tabLabel('Plans de traitement'));
    await tester.tap(tabLabel('Plans de traitement'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('patient_treatment_plans_card')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('patient_orthodontics_section')),
      findsOneWidget,
    );
  });

  testWidgets(
      'l\'onglet Questionnaire médical affiche '
      'MedicalQuestionnaireReviewSection', (tester) async {
    await pumpFiche(tester);

    await tester.ensureVisible(tabLabel('Questionnaire médical'));
    await tester.tap(tabLabel('Questionnaire médical'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('medical_questionnaire_review_section')),
      findsOneWidget,
    );
  });

  testWidgets('l\'onglet Facturation affiche un placeholder', (tester) async {
    await pumpFiche(tester);

    await tester.ensureVisible(tabLabel('Facturation'));
    await tester.tap(tabLabel('Facturation'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('patient_fiche_billing_placeholder')),
      findsOneWidget,
    );
  });
}
