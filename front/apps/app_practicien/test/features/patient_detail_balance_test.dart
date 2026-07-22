//! Tests widget : solde patient sur le VRAI écran de détail (#4045).
//!
//! `PatientDetailPage`/`_DetailView` (patients_page.dart) est l'écran
//! réellement routé (`/patients/:id`, app_router.dart) — distinct de
//! `PatientFiche` (patient_fiche.dart), qui n'est référencé par aucune route
//! et n'était donc jamais atteint par un utilisateur réel. Ce test cible
//! délibérément le vrai écran pour éviter de reproduire cette dérive.

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
        // Même structure que app_router.dart : PatientDetailPage est le
        // `body` d'un Scaffold externe, jamais pumpé seul en production.
        home: const Scaffold(body: PatientDetailPage(patientId: 'pat-1')),
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
      'les sections Étiquettes/Documents sont atteignables depuis le vrai écran (#4041/#4042)',
      (tester) async {
    when(() => bloc.state).thenReturn(
      PatientDetailLoaded(_patient(balanceDueCents: 0)),
    );
    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();

    expect(find.text('Étiquettes'), findsOneWidget);
    expect(find.text('Documents'), findsOneWidget);
  });

  testWidgets('0 lapin : affiché sans mise en avant (#4090)', (tester) async {
    when(() => bloc.state).thenReturn(
      PatientDetailLoaded(_patient(noShowCount: 0)),
    );
    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();

    expect(find.text('Lapins : 0'), findsOneWidget);
    final text =
        tester.widget<Text>(find.byKey(const Key('patient_no_show_count')));
    expect(text.style?.color, isNull);
  });

  testWidgets('3 lapins : affiché en évidence (couleur error) (#4090)',
      (tester) async {
    when(() => bloc.state).thenReturn(
      PatientDetailLoaded(_patient(noShowCount: 3)),
    );
    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();

    expect(find.text('Lapins : 3'), findsOneWidget);
    final text =
        tester.widget<Text>(find.byKey(const Key('patient_no_show_count')));
    expect(text.style?.color,
        Theme.of(tester.element(find.byType(Scaffold))).colorScheme.error);
  });

  testWidgets('noShowCount null : la ligne lapins est absente (#4090)',
      (tester) async {
    when(() => bloc.state).thenReturn(
      PatientDetailLoaded(_patient(noShowCount: null)),
    );
    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('patient_no_show_count')), findsNothing);
  });
}
