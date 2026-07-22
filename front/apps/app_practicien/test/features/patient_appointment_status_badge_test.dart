//! Tests widget : badge de statut RDV dans l'historique de la fiche patient
//! (#4089), sur le VRAI écran de détail routé (`PatientDetailPage`,
//! patients_page.dart) — même stratégie que patient_detail_balance_test.dart
//! (#4045) : cible délibérément le vrai écran, pas une doublure locale.

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

final _patient = CabinetPatient(
  id: 'pat-1',
  cabinetId: 'cab-1',
  firstName: 'Jean',
  lastName: 'Dupont',
  createdAt: DateTime(2026, 1, 1),
);

CabinetAppointment _appointment(String id, CabinetAppointmentStatus status) =>
    CabinetAppointment(
      id: id,
      cabinetId: 'cab-1',
      patientId: 'pat-1',
      patientName: 'Jean Dupont',
      practitionerId: 'prat-1',
      practitionerName: 'Dr Martin',
      startsAt: DateTime(2026, 3, 1, 9),
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
    GetIt.instance.registerFactory<ListPatientDocumentsUseCase>(
      () => listDocuments,
    );

    addTearDown(GetIt.instance.reset);
  });

  Widget buildPage() => MaterialApp(
        theme: NubiaTheme.light,
        home: const Scaffold(body: PatientDetailPage(patientId: 'pat-1')),
      );

  testWidgets(
      'liste mixte (honoré/annulé/non venu) : un badge de statut par ligne',
      (tester) async {
    when(() => bloc.state).thenReturn(
      PatientDetailLoaded(
        _patient,
        appointments: [
          _appointment('a1', CabinetAppointmentStatus.completed),
          _appointment('a2', CabinetAppointmentStatus.cancelled),
          _appointment('a3', CabinetAppointmentStatus.noShow),
        ],
      ),
    );
    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('patient_appt_status_a1')), findsOneWidget);
    expect(find.byKey(const Key('patient_appt_status_a2')), findsOneWidget);
    expect(find.byKey(const Key('patient_appt_status_a3')), findsOneWidget);
    expect(find.text('Honoré'), findsOneWidget);
    expect(find.text('Annulé'), findsOneWidget);
    expect(find.text('Non venu'), findsOneWidget);
  });

  testWidgets('statut confirmed : badge "Confirmé"', (tester) async {
    when(() => bloc.state).thenReturn(
      PatientDetailLoaded(
        _patient,
        appointments: [_appointment('a1', CabinetAppointmentStatus.confirmed)],
      ),
    );
    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();

    expect(find.text('Confirmé'), findsOneWidget);
  });
}
