//! Tests widget : #8040 — « Nouveau devis »/« Démarrer une consultation »
//! doivent être atteignables depuis l'en-tête de la fiche patient réellement
//! routée (`PatientDetailPage`, `/patients/:id`), pas seulement au fond
//! d'un défilement de ~6700px. Même convention que `ordonnance_dead_end_test.dart`
//! : cible le VRAI écran routé via go_router.

import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_practicien/features/devis/devis_event.dart';
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

CabinetAppointment _appt({
  required String id,
  required DateTime startsAt,
  CabinetAppointmentStatus status = CabinetAppointmentStatus.confirmed,
}) =>
    CabinetAppointment(
      id: id,
      cabinetId: 'cab-1',
      patientId: 'pat-1',
      patientName: 'Jean Dupont',
      practitionerId: 'prat-1',
      practitionerName: 'Dr Martin',
      startsAt: startsAt,
      duration: const Duration(minutes: 30),
      motif: 'Contrôle',
      status: status,
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

    addTearDown(GetIt.instance.reset);
  });

  GoRouter buildRouter({void Function(Object?)? onDevisExtra}) => GoRouter(
        initialLocation: '/patients/pat-1',
        routes: [
          GoRoute(
            path: '/patients/pat-1',
            builder: (_, __) =>
                const Scaffold(body: PatientDetailPage(patientId: 'pat-1')),
          ),
          GoRoute(
            path: '/devis',
            builder: (_, state) {
              onDevisExtra?.call(state.extra);
              return Scaffold(
                body: Text(
                    'devis?patientId=${state.uri.queryParameters['patientId']}'),
              );
            },
          ),
          GoRoute(
            path: '/consultation',
            builder: (_, state) => Scaffold(
              body: Text('consultation?id=${state.uri.queryParameters['id']}'),
            ),
          ),
        ],
      );

  testWidgets(
      'fiche patient → bouton "Exporter PDF" de l\'en-tête dispatch '
      'PatientExportPdfRequested (#8057)', (tester) async {
    when(() => bloc.state).thenReturn(PatientDetailLoaded(_patient));

    await tester.pumpWidget(
      MaterialApp.router(theme: NubiaTheme.light, routerConfig: buildRouter()),
    );
    await tester.pumpAndSettle();

    final button = find.byKey(const Key('patient_export_button'));
    expect(button, findsOneWidget);
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();

    verify(() => bloc.add(PatientExportPdfRequested(_patient))).called(1);
  });

  testWidgets(
      'fiche patient → bouton "Nouveau devis" déclenche la création du '
      'devis du patient, pas une navigation vers sa liste existante (#8056)',
      (tester) async {
    when(() => bloc.state).thenReturn(PatientDetailLoaded(_patient));
    Object? capturedExtra;

    await tester.pumpWidget(
      MaterialApp.router(
        theme: NubiaTheme.light,
        routerConfig:
            buildRouter(onDevisExtra: (extra) => capturedExtra = extra),
      ),
    );
    await tester.pumpAndSettle();

    final button = find.byKey(const Key('patient_new_quote_button'));
    expect(button, findsOneWidget);
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(find.text('devis?patientId=pat-1'), findsOneWidget);
    expect(capturedExtra, isA<DevisNewQuoteRequested>());
    expect((capturedExtra as DevisNewQuoteRequested).patientId, 'pat-1');
  });

  testWidgets(
      'fiche patient → "Démarrer une consultation" désactivé sans RDV '
      'démarrable (#8040)', (tester) async {
    when(() => bloc.state).thenReturn(PatientDetailLoaded(_patient));

    await tester.pumpWidget(
      MaterialApp.router(theme: NubiaTheme.light, routerConfig: buildRouter()),
    );
    await tester.pumpAndSettle();

    final button = find.byKey(
      const Key('patient_start_consultation_button'),
    );
    expect(button, findsOneWidget);
    final widget = tester.widget<NubiaButton>(button);
    expect(widget.onPressed, isNull);
  });

  testWidgets(
      'fiche patient → "Démarrer une consultation" activé avec un RDV '
      'confirmé en cours, dispatch l\'appointmentId correspondant (#8040)',
      (tester) async {
    final appointment = _appt(id: 'appt-1', startsAt: DateTime.now());
    final loaded = PatientDetailLoaded(_patient, appointments: [appointment]);

    when(() => bloc.state).thenReturn(loaded);

    await tester.pumpWidget(
      MaterialApp.router(theme: NubiaTheme.light, routerConfig: buildRouter()),
    );
    await tester.pumpAndSettle();

    final button = find.byKey(
      const Key('patient_start_consultation_button'),
    );
    expect(button, findsOneWidget);
    final widget = tester.widget<NubiaButton>(button);
    expect(widget.onPressed, isNotNull);

    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();

    verify(() => bloc.add(const PatientsStartConsultationRequested('appt-1')))
        .called(1);
  });
}
