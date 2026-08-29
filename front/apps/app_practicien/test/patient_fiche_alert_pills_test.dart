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

final _patient = CabinetPatient(
  id: 'pat-1',
  cabinetId: 'cab-1',
  firstName: 'Julie',
  lastName: 'Martin',
  createdAt: DateTime(2024, 1, 1),
);

// #4974 : pastilles d'alerte clinique (allergies + traitements à risque)
// dans l'en-tête du dossier patient, à côté du nom.
void main() {
  setUp(() {
    final listDocuments = _MockListPatientDocuments();
    when(() => listDocuments(any(), category: any(named: 'category')))
        .thenAnswer((_) async => const Right([]));
    GetIt.instance.registerFactory<ListPatientDocumentsUseCase>(
      () => listDocuments,
    );

    final listJournal = _MockListPatientJournal();
    when(() => listJournal(any())).thenAnswer((_) async => const Right([]));
    GetIt.instance.registerFactory<ListPatientJournalUseCase>(
      () => listJournal,
    );

    // #4982 — onglet « Plans de traitement », adjacent à l'onglet initial
    // (Journal) : `TabBarView` le pré-construit (cache du `PageView`),
    // donc son `initState` s'exécute même sans y naviguer.
    final listTreatmentPlans = _MockListTreatmentPlans();
    when(() => listTreatmentPlans(any()))
        .thenAnswer((_) async => const Right([]));
    GetIt.instance.registerFactory<ListTreatmentPlansUseCase>(
      () => listTreatmentPlans,
    );

    final listOrthodonticTreatments = _MockListOrthodonticTreatments();
    when(() => listOrthodonticTreatments(any()))
        .thenAnswer((_) async => const Right([]));
    GetIt.instance.registerFactory<ListOrthodonticTreatmentsUseCase>(
      () => listOrthodonticTreatments,
    );

    addTearDown(GetIt.instance.reset);
  });

  Future<void> registerMedicalRecord(List<MedicalAlert> alerts) async {
    final getMedicalRecord = _MockGetMedicalRecord();
    when(() => getMedicalRecord(any())).thenAnswer(
      (_) async => Right(
        MedicalRecordSummary(
          allergies: const [],
          treatments: const [],
          medicalAlerts: alerts,
        ),
      ),
    );
    GetIt.instance.registerFactory<GetMedicalRecordUseCase>(
      () => getMedicalRecord,
    );
  }

  testWidgets(
      'affiche une pastille error pour une allergie et warning pour un '
      'traitement à risque, dans l\'en-tête', (tester) async {
    await registerMedicalRecord(const [
      MedicalAlert(kind: 'allergie', label: 'Pénicilline'),
      MedicalAlert(kind: 'medico_legal', label: 'Anticoagulant (AVK)'),
    ]);

    await tester.pumpWidget(
      MaterialApp(
          theme: NubiaTheme.light, home: PatientFiche(patient: _patient)),
    );
    await tester.pumpAndSettle();

    final allergyPill = find.byKey(
      const Key('patient_fiche_alert_pill_allergie_Pénicilline'),
    );
    final riskPill = find.byKey(
      const Key('patient_fiche_alert_pill_medico_legal_Anticoagulant (AVK)'),
    );

    expect(allergyPill, findsOneWidget);
    expect(riskPill, findsOneWidget);
    expect(
      tester.widget<StatusPill>(allergyPill).variant,
      StatusPillVariant.error,
    );
    expect(
      tester.widget<StatusPill>(riskPill).variant,
      StatusPillVariant.warning,
    );
    // #4975 — les mêmes alertes apparaissent aussi dans la carte « Alertes
    // cliniques » de la colonne gauche (même référentiel) : on scope la
    // recherche du libellé aux pastilles d'en-tête pour ne pas dépendre du
    // nombre total d'occurrences à l'écran.
    expect(
      find.descendant(
        of: find.byKey(const Key('patient_fiche_header')),
        matching: find.text('Allergie Pénicilline'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('patient_fiche_header')),
        matching: find.text('Anticoagulant (AVK)'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('les pastilles restent visibles après changement d\'onglet',
      (tester) async {
    await registerMedicalRecord(const [
      MedicalAlert(kind: 'allergie', label: 'Pénicilline'),
    ]);

    await tester.pumpWidget(
      MaterialApp(
          theme: NubiaTheme.light, home: PatientFiche(patient: _patient)),
    );
    await tester.pumpAndSettle();

    final allergyPill = find.byKey(
      const Key('patient_fiche_alert_pill_allergie_Pénicilline'),
    );
    expect(allergyPill, findsOneWidget);

    await tester.tap(find.descendant(
      of: find.byKey(const Key('patient_fiche_tabs')),
      matching: find.text('Documents'),
    ));
    await tester.pumpAndSettle();

    expect(allergyPill, findsOneWidget);
  });

  testWidgets('aucune pastille quand le dossier n\'a aucune alerte',
      (tester) async {
    await registerMedicalRecord(const []);

    await tester.pumpWidget(
      MaterialApp(
          theme: NubiaTheme.light, home: PatientFiche(patient: _patient)),
    );
    await tester.pumpAndSettle();

    expect(find.byType(StatusPill), findsNothing);
  });
}
