//! Tests widget : #4541 — impossible d'atteindre une ordonnance par clic.
//!
//! Cible délibérément les VRAIS écrans routés (`PatientDetailPage` via
//! `/patients/:id`, `OrdonnancesPage` via `/ordonnances`) plutôt que les
//! doubles de test utilisés dans `ordonnances_test.dart` (qui contournent
//! GetIt/go_router et n'auraient pas détecté ce cul-de-sac de navigation).

import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_practicien/features/ordonnances/ordonnances_bloc.dart';
import 'package:app_practicien/features/ordonnances/ordonnances_event.dart';
import 'package:app_practicien/features/ordonnances/ordonnances_page.dart';
import 'package:app_practicien/features/ordonnances/ordonnances_state.dart';
import 'package:app_practicien/features/patients/patients_bloc.dart';
import 'package:app_practicien/features/patients/patients_event.dart';
import 'package:app_practicien/features/patients/patients_page.dart';
import 'package:app_practicien/features/patients/patients_state.dart';

class _MockPatientsBloc extends MockBloc<PatientsEvent, PatientsState>
    implements PatientsBloc {}

class _MockListPatientTags extends Mock implements ListPatientTagsUseCase {}

class _MockListPatientDocuments extends Mock
    implements ListPatientDocumentsUseCase {}

class _MockOrdonnancesBloc extends MockBloc<OrdonnancesEvent, OrdonnancesState>
    implements OrdonnancesBloc {}

final _patient = CabinetPatient(
  id: 'pat-1',
  cabinetId: 'cab-1',
  firstName: 'Jean',
  lastName: 'Dupont',
  createdAt: DateTime(2026, 1, 1),
);

void main() {
  testWidgets(
      'fiche patient → bouton "Créer une ordonnance" navigue vers '
      '/ordonnances/new?patientId= (#4541)', (tester) async {
    final bloc = _MockPatientsBloc();
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

    when(() => bloc.state).thenReturn(PatientDetailLoaded(_patient));

    final router = GoRouter(
      initialLocation: '/patients/pat-1',
      routes: [
        GoRoute(
          path: '/patients/pat-1',
          builder: (_, __) =>
              const Scaffold(body: PatientDetailPage(patientId: 'pat-1')),
        ),
        GoRoute(
          path: '/ordonnances/new',
          builder: (_, __) => const Scaffold(body: Text('ordonnances/new')),
        ),
      ],
    );

    await tester.pumpWidget(
        MaterialApp.router(theme: NubiaTheme.light, routerConfig: router));
    await tester.pumpAndSettle();

    final button = find.byKey(const Key('btn_create_ordonnance'));
    expect(button, findsOneWidget);
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(find.text('ordonnances/new'), findsOneWidget);
  });

  testWidgets(
      'onglet Ordonnances sans patient → bouton "Choisir un patient" '
      'navigue vers /patients (#4541)', (tester) async {
    final bloc = _MockOrdonnancesBloc();
    GetIt.instance.registerFactory<OrdonnancesBloc>(() => bloc);
    addTearDown(GetIt.instance.reset);

    when(() => bloc.state).thenReturn(const OrdonnancesInitial());

    final router = GoRouter(
      initialLocation: '/ordonnances',
      routes: [
        GoRoute(
          path: '/ordonnances',
          builder: (_, __) => const Scaffold(body: OrdonnancesPage()),
        ),
        GoRoute(
          path: '/patients',
          builder: (_, __) => const Scaffold(body: Text('patients page')),
        ),
      ],
    );

    await tester.pumpWidget(
        MaterialApp.router(theme: NubiaTheme.light, routerConfig: router));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('ordonnances_initial_go_to_patients')),
      findsOneWidget,
    );
    await tester
        .tap(find.byKey(const Key('ordonnances_initial_go_to_patients')));
    await tester.pumpAndSettle();

    expect(find.text('patients page'), findsOneWidget);
  });
}
