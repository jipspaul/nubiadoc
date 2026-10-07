//! Tests widget : #6854 — les 4 actions cliniques (schéma dentaire, bilan
//! parodontal, plan de traitement, créer une ordonnance) de la fiche
//! patient menaient à une impasse (403 « relation de soin » absente, §14)
//! quand le praticien n'a jamais suivi ce patient. Elles doivent être
//! désactivées plutôt que de laisser l'utilisateur naviguer (ou, pour
//! l'ordonnance, remplir tout le compositeur) vers un refus garanti.

import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_practicien/features/patients/patients_bloc.dart';
import 'package:app_practicien/features/patients/patients_event.dart';
import 'package:app_practicien/features/patients/patients_page.dart';
import 'package:app_practicien/features/patients/patients_state.dart';

class _MockPatientsBloc extends MockBloc<PatientsEvent, PatientsState>
    implements PatientsBloc {}

class _MockListPatientTags extends Mock implements ListPatientTagsUseCase {}

class _MockListPatientDocuments extends Mock
    implements ListPatientDocumentsUseCase {}

class _MockListPatientJournal extends Mock
    implements ListPatientJournalUseCase {}

class _MockGetMedicalRecord extends Mock implements GetMedicalRecordUseCase {}

final _patient = CabinetPatient(
  id: 'pat-1',
  cabinetId: 'cab-1',
  firstName: 'Jean',
  lastName: 'Dupont',
  createdAt: DateTime(2026, 1, 1),
);

void main() {
  late _MockPatientsBloc bloc;

  setUp(() {
    bloc = _MockPatientsBloc();
    GetIt.instance.registerFactory<PatientsBloc>(() => bloc);

    final listTags = _MockListPatientTags();
    when(() => listTags(any())).thenAnswer((_) async => const Right([]));
    GetIt.instance.registerFactory<ListPatientTagsUseCase>(() => listTags);

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

    final getMedicalRecord = _MockGetMedicalRecord();
    when(() => getMedicalRecord(any())).thenAnswer(
      (_) async => const Right(
        MedicalRecordSummary(allergies: [], treatments: []),
      ),
    );
    GetIt.instance.registerFactory<GetMedicalRecordUseCase>(
      () => getMedicalRecord,
    );

    addTearDown(GetIt.instance.reset);
  });

  Widget buildPage() => MaterialApp(
        theme: NubiaTheme.light,
        home: const Scaffold(body: PatientDetailPage(patientId: 'pat-1')),
      );

  testWidgets(
      'patient jamais suivi (notesAccessDenied) : les 4 actions cliniques '
      'sont désactivées et un message explicite remplace "ce rôle" (#6854)',
      (tester) async {
    when(() => bloc.state).thenReturn(
      PatientDetailLoaded(_patient, notesAccessDenied: true),
    );
    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();

    for (final key in [
      'btn_dental_chart',
      'btn_periodontal_chart',
      'btn_treatment_plans',
      'btn_create_ordonnance',
    ]) {
      final button = tester.widget<NubiaButton>(find.byKey(Key(key)));
      expect(button.onPressed, isNull, reason: '$key doit être désactivé');
    }

    expect(
      find.byKey(const Key('patient_clinical_actions_access_denied')),
      findsOneWidget,
    );
  });

  testWidgets(
      'patient déjà suivi : les 4 actions cliniques restent actives (#6854)',
      (tester) async {
    when(() => bloc.state).thenReturn(
      PatientDetailLoaded(_patient, notesAccessDenied: false),
    );
    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();

    for (final key in [
      'btn_dental_chart',
      'btn_periodontal_chart',
      'btn_treatment_plans',
      'btn_create_ordonnance',
    ]) {
      final button = tester.widget<NubiaButton>(find.byKey(Key(key)));
      expect(button.onPressed, isNotNull, reason: '$key doit rester actif');
    }

    expect(
      find.byKey(const Key('patient_clinical_actions_access_denied')),
      findsNothing,
    );
  });
}
