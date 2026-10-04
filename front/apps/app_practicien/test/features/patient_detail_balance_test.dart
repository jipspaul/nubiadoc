//! Tests widget : solde patient sur le VRAI écran de détail (#4045).
//!
//! `PatientDetailPage` (patients_page.dart) est l'écran réellement routé
//! (`/patients/:id`, app_router.dart) ; depuis #6919, une fois le patient
//! chargé il délègue à `PatientFiche` (journal unifié, onglets, barre
//! d'actions) plutôt qu'à l'ancienne pile de sections — ce test cible
//! toujours délibérément le vrai écran routé, pas une doublure locale.

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

class _MockListPatientDocuments extends Mock
    implements ListPatientDocumentsUseCase {}

class _MockListPatientJournal extends Mock
    implements ListPatientJournalUseCase {}

class _MockGetMedicalRecord extends Mock implements GetMedicalRecordUseCase {}

class _MockListTreatmentPlans extends Mock
    implements ListTreatmentPlansUseCase {}

CabinetPatient _patient({int? balanceDueCents, int? noShowCount}) =>
    CabinetPatient(
      id: 'pat-1',
      cabinetId: 'cab-1',
      firstName: 'Jean',
      lastName: 'Dupont',
      createdAt: DateTime(2026, 1, 1),
      balanceDueCents: balanceDueCents,
      noShowCount: noShowCount,
    );

void main() {
  late _MockPatientsBloc bloc;

  setUp(() {
    bloc = _MockPatientsBloc();
    GetIt.instance.registerFactory<PatientsBloc>(() => bloc);

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

    final listTreatmentPlans = _MockListTreatmentPlans();
    when(() => listTreatmentPlans(any()))
        .thenAnswer((_) async => const Right([]));
    GetIt.instance
        .registerFactory<ListTreatmentPlansUseCase>(() => listTreatmentPlans);

    addTearDown(GetIt.instance.reset);
  });

  Widget buildPage() => MaterialApp(
        theme: NubiaTheme.light,
        // Même structure que app_router.dart : `PatientDetailPage` fournit
        // désormais son propre `Scaffold` (via `PatientFiche`), jamais
        // englobé par un `Scaffold` externe.
        home: const PatientDetailPage(patientId: 'pat-1'),
      );

  testWidgets('solde = 0 : affiché sans mise en avant', (tester) async {
    when(() => bloc.state).thenReturn(
      PatientDetailLoaded(_patient(balanceDueCents: 0)),
    );
    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();

    expect(find.text('Solde : 0,00 €'), findsOneWidget);
    final text = tester.widget<Text>(find.byKey(const Key('patient_balance')));
    expect(text.style?.color, isNull);
  });

  testWidgets('solde > 0 : affiché en évidence (couleur error)',
      (tester) async {
    when(() => bloc.state).thenReturn(
      PatientDetailLoaded(_patient(balanceDueCents: 3050)),
    );
    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();

    expect(find.text('Solde : 30,50 €'), findsOneWidget);
    final text = tester.widget<Text>(find.byKey(const Key('patient_balance')));
    expect(text.style?.color,
        Theme.of(tester.element(find.byType(Scaffold))).colorScheme.error);
  });

  testWidgets('balanceDueCents null : la ligne solde est absente',
      (tester) async {
    when(() => bloc.state).thenReturn(
      PatientDetailLoaded(_patient(balanceDueCents: null)),
    );
    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('patient_balance')), findsNothing);
  });

  testWidgets(
      'l\'onglet Documents est atteignable depuis le vrai écran (#4042)',
      (tester) async {
    when(() => bloc.state).thenReturn(
      PatientDetailLoaded(_patient(balanceDueCents: 0)),
    );
    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();

    final documentsTab = find.descendant(
      of: find.byKey(const Key('patient_fiche_tabs')),
      matching: find.text('Documents'),
    );
    await tester.ensureVisible(documentsTab);
    await tester.tap(documentsTab);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('patient_documents_section')), findsOneWidget);
  });

  testWidgets('0 rendez-vous manqué : affiché sans mise en avant (#4090)',
      (tester) async {
    when(() => bloc.state).thenReturn(
      PatientDetailLoaded(_patient(noShowCount: 0)),
    );
    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();

    expect(find.text('Rendez-vous manqués : 0'), findsOneWidget);
    final text =
        tester.widget<Text>(find.byKey(const Key('patient_no_show_count')));
    expect(text.style?.color, isNull);
  });

  testWidgets(
      '3 rendez-vous manqués : affiché en évidence (couleur error) (#4090)',
      (tester) async {
    when(() => bloc.state).thenReturn(
      PatientDetailLoaded(_patient(noShowCount: 3)),
    );
    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();

    expect(find.text('Rendez-vous manqués : 3'), findsOneWidget);
    final text =
        tester.widget<Text>(find.byKey(const Key('patient_no_show_count')));
    expect(text.style?.color,
        Theme.of(tester.element(find.byType(Scaffold))).colorScheme.error);
  });

  testWidgets(
      'noShowCount null : la ligne rendez-vous manqués est absente (#4090)',
      (tester) async {
    when(() => bloc.state).thenReturn(
      PatientDetailLoaded(_patient(noShowCount: null)),
    );
    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('patient_no_show_count')), findsNothing);
  });
}
