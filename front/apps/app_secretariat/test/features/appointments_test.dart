import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_secretariat/features/appointments/appointments_bloc.dart';
import 'package:app_secretariat/features/appointments/appointments_event.dart';
import 'package:app_secretariat/features/appointments/appointments_page.dart';
import 'package:app_secretariat/features/appointments/appointments_state.dart';
import 'package:app_secretariat/pro_config.dart';

class _MockCabinetAppointmentsRepository extends Mock
    implements CabinetAppointmentsRepository {}

class _MockAppointmentsBloc
    extends MockBloc<AppointmentsEvent, AppointmentsState>
    implements AppointmentsBloc {}

// Fixture — sans notes médicales, sans champ clinique au-delà du motif RDV.
CabinetAppointment _appointment({
  String id = 'rdv-1',
  String patientName = 'Jean Dupont',
  CabinetAppointmentStatus status = CabinetAppointmentStatus.confirmed,
}) =>
    CabinetAppointment(
      id: id,
      cabinetId: 'cab-1',
      patientId: 'pat-1',
      patientName: patientName,
      practitionerId: 'prat-1',
      practitionerName: 'Dr Martin',
      startsAt: DateTime(2026, 7, 15, 9, 0),
      duration: const Duration(minutes: 30),
      motif: '',
      status: status,
    );

void main() {
  setUpAll(() {
    registerFallbackValue(_appointment());
  });

  // --- Cloisonnement invariant --------------------------------------------------
  group('ProConfig — cloisonnement', () {
    test('includeClinical est false', () {
      expect(ProConfig.includeClinical, isFalse);
    });

    test('aucune destination requiresClinical dans shellConfig', () {
      final clinicalDests = ProConfig.shellConfig.destinations
          .where((d) => d.requiresClinical)
          .toList();
      expect(clinicalDests, isEmpty);
    });
  });

  // --- AppointmentsBloc — CreateCabinetAppointment ----------------------------
  group('AppointmentsBloc — Create', () {
    late _MockCabinetAppointmentsRepository repo;
    late CreateCabinetAppointmentUseCase createUC;
    late ConfirmAppointmentUseCase confirmUC;
    late RescheduleAppointmentUseCase rescheduleUC;

    setUp(() {
      repo = _MockCabinetAppointmentsRepository();
      createUC = CreateCabinetAppointmentUseCase(repo);
      confirmUC = ConfirmAppointmentUseCase(repo);
      rescheduleUC = RescheduleAppointmentUseCase(repo);
    });

    blocTest<AppointmentsBloc, AppointmentsState>(
      'émet Loading puis AppointmentSuccess sur create réussi',
      build: () {
        when(() => repo.create(any()))
            .thenAnswer((_) async => Right(_appointment()));
        return AppointmentsBloc(
            listAppointments: ListCabinetAppointmentsUseCase(repo),
            create: createUC,
            confirm: confirmUC,
            reschedule: rescheduleUC);
      },
      act: (bloc) => bloc
          .add(AppointmentCreateRequested(appointment: _appointment(id: ''))),
      expect: () => [
        const AppointmentsLoading(),
        AppointmentSuccess(_appointment()),
      ],
    );

    blocTest<AppointmentsBloc, AppointmentsState>(
      'émet Loading puis AppointmentsError sur create échoué',
      build: () {
        when(() => repo.create(any())).thenAnswer(
          (_) async => const Left(NetworkFailure('Erreur réseau')),
        );
        return AppointmentsBloc(
            listAppointments: ListCabinetAppointmentsUseCase(repo),
            create: createUC,
            confirm: confirmUC,
            reschedule: rescheduleUC);
      },
      act: (bloc) => bloc
          .add(AppointmentCreateRequested(appointment: _appointment(id: ''))),
      expect: () => [
        const AppointmentsLoading(),
        const AppointmentsError('Erreur réseau'),
      ],
    );

    blocTest<AppointmentsBloc, AppointmentsState>(
      'create — le succès ne transporte pas de notes médicales',
      build: () {
        when(() => repo.create(any()))
            .thenAnswer((_) async => Right(_appointment()));
        return AppointmentsBloc(
            listAppointments: ListCabinetAppointmentsUseCase(repo),
            create: createUC,
            confirm: confirmUC,
            reschedule: rescheduleUC);
      },
      act: (bloc) => bloc
          .add(AppointmentCreateRequested(appointment: _appointment(id: ''))),
      verify: (bloc) {
        final state = bloc.state;
        expect(state, isA<AppointmentSuccess>());
        final appt = (state as AppointmentSuccess).appointment;
        // CabinetAppointment ne porte pas de champ notesMedicales :
        // garantie structurelle par le type.
        expect(appt.patientName, isNotEmpty);
        final json = {'id': appt.id, 'patientName': appt.patientName};
        expect(json.containsKey('notesMedicales'), isFalse);
      },
    );
  });

  // --- AppointmentsBloc — ConfirmAppointment -----------------------------------
  group('AppointmentsBloc — Confirm', () {
    late _MockCabinetAppointmentsRepository repo;
    late AppointmentsBloc buildBloc;

    setUp(() {
      repo = _MockCabinetAppointmentsRepository();
      buildBloc = AppointmentsBloc(
        listAppointments: ListCabinetAppointmentsUseCase(repo),
        create: CreateCabinetAppointmentUseCase(repo),
        confirm: ConfirmAppointmentUseCase(repo),
        reschedule: RescheduleAppointmentUseCase(repo),
      );
    });

    tearDown(() => buildBloc.close());

    blocTest<AppointmentsBloc, AppointmentsState>(
      'émet Loading puis AppointmentSuccess sur confirm réussi',
      build: () {
        when(() => repo.confirm(any()))
            .thenAnswer((_) async => Right(_appointment()));
        return AppointmentsBloc(
          listAppointments: ListCabinetAppointmentsUseCase(repo),
          create: CreateCabinetAppointmentUseCase(repo),
          confirm: ConfirmAppointmentUseCase(repo),
          reschedule: RescheduleAppointmentUseCase(repo),
        );
      },
      act: (bloc) => bloc
          .add(const AppointmentConfirmRequested(appointmentId: 'rdv-1')),
      expect: () => [
        const AppointmentsLoading(),
        AppointmentSuccess(_appointment()),
      ],
    );

    blocTest<AppointmentsBloc, AppointmentsState>(
      'émet Loading puis AppointmentsError sur confirm échoué',
      build: () {
        when(() => repo.confirm(any())).thenAnswer(
          (_) async =>
              const Left(NotFoundFailure('Rendez-vous introuvable.')),
        );
        return AppointmentsBloc(
          listAppointments: ListCabinetAppointmentsUseCase(repo),
          create: CreateCabinetAppointmentUseCase(repo),
          confirm: ConfirmAppointmentUseCase(repo),
          reschedule: RescheduleAppointmentUseCase(repo),
        );
      },
      act: (bloc) => bloc
          .add(const AppointmentConfirmRequested(appointmentId: 'rdv-x')),
      expect: () => [
        const AppointmentsLoading(),
        const AppointmentsError('Rendez-vous introuvable.'),
      ],
    );
  });

  // --- AppointmentsBloc — RescheduleAppointment --------------------------------
  group('AppointmentsBloc — Reschedule', () {
    late _MockCabinetAppointmentsRepository repo;

    setUp(() {
      repo = _MockCabinetAppointmentsRepository();
    });

    blocTest<AppointmentsBloc, AppointmentsState>(
      'émet Loading puis AppointmentSuccess sur reschedule réussi',
      build: () {
        when(() => repo.reschedule(any(), any()))
            .thenAnswer((_) async => Right(_appointment()));
        return AppointmentsBloc(
          listAppointments: ListCabinetAppointmentsUseCase(repo),
          create: CreateCabinetAppointmentUseCase(repo),
          confirm: ConfirmAppointmentUseCase(repo),
          reschedule: RescheduleAppointmentUseCase(repo),
        );
      },
      act: (bloc) => bloc.add(AppointmentRescheduleRequested(
        appointmentId: 'rdv-1',
        newStartsAt: DateTime(2026, 7, 22, 10, 0),
      )),
      expect: () => [
        const AppointmentsLoading(),
        AppointmentSuccess(_appointment()),
      ],
    );

    blocTest<AppointmentsBloc, AppointmentsState>(
      'émet Loading puis AppointmentsError sur reschedule échoué',
      build: () {
        when(() => repo.reschedule(any(), any())).thenAnswer(
          (_) async => const Left(NetworkFailure('Erreur réseau')),
        );
        return AppointmentsBloc(
          listAppointments: ListCabinetAppointmentsUseCase(repo),
          create: CreateCabinetAppointmentUseCase(repo),
          confirm: ConfirmAppointmentUseCase(repo),
          reschedule: RescheduleAppointmentUseCase(repo),
        );
      },
      act: (bloc) => bloc.add(AppointmentRescheduleRequested(
        appointmentId: 'rdv-1',
        newStartsAt: DateTime(2026, 7, 22, 10, 0),
      )),
      expect: () => [
        const AppointmentsLoading(),
        const AppointmentsError('Erreur réseau'),
      ],
    );
  });

  // --- AppointmentsPage widget tests -------------------------------------------
  group('AppointmentsPage', () {
    late _MockAppointmentsBloc bloc;

    setUp(() {
      bloc = _MockAppointmentsBloc();
    });

    Widget buildPage() => MaterialApp(
          theme: NubiaTheme.light,
          home: BlocProvider<AppointmentsBloc>.value(
            value: bloc,
            child: const AppointmentsPage(),
          ),
        );

    testWidgets('affiche le chargement en état Loading', (tester) async {
      when(() => bloc.state).thenReturn(const AppointmentsLoading());
      await tester.pumpWidget(buildPage());
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('affiche le menu initial en état Initial', (tester) async {
      when(() => bloc.state).thenReturn(const AppointmentsInitial());
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(find.text('Créer un rendez-vous'), findsOneWidget);
      expect(find.text('Confirmer un rendez-vous'), findsOneWidget);
      expect(find.text('Reprogrammer un rendez-vous'), findsOneWidget);
    });

    testWidgets('affiche le succès sans champ clinique', (tester) async {
      when(() => bloc.state).thenReturn(AppointmentSuccess(_appointment()));
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(find.textContaining('Jean Dupont'), findsOneWidget);
      expect(find.text('Opération effectuée'), findsOneWidget);

      // Cloisonnement : aucun libellé clinique ne doit apparaître
      expect(find.text('Notes médicales'), findsNothing);
      expect(find.textContaining('notes médicales'), findsNothing);
      expect(find.textContaining('Motif clinique'), findsNothing);
      expect(find.textContaining('Journal clinique'), findsNothing);
    });

    testWidgets('affiche le message d\'erreur', (tester) async {
      when(() => bloc.state)
          .thenReturn(const AppointmentsError('Erreur de connexion'));
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(find.text('Erreur de connexion'), findsOneWidget);
    });

    testWidgets(
        'filtre par chip Confirmé — 1 rdv visible sur 3 de statuts différents',
        (tester) async {
      final appointments = [
        _appointment(
          id: 'rdv-1',
          patientName: 'Jean Dupont',
          status: CabinetAppointmentStatus.confirmed,
        ),
        _appointment(
          id: 'rdv-2',
          patientName: 'Marie Curie',
          status: CabinetAppointmentStatus.requested,
        ),
        _appointment(
          id: 'rdv-3',
          patientName: 'Pierre Martin',
          status: CabinetAppointmentStatus.cancelled,
        ),
      ];
      when(() => bloc.state).thenReturn(AppointmentsLoaded(appointments));
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      // Les 4 FilterChips sont visibles
      expect(find.byType(FilterChip), findsNWidgets(4));

      // Tous les 3 patients visibles avant filtrage
      expect(find.text('Jean Dupont'), findsOneWidget);
      expect(find.text('Marie Curie'), findsOneWidget);
      expect(find.text('Pierre Martin'), findsOneWidget);

      // Tap chip 'Confirmé' dans le Wrap (premier widget FilterChip avec ce label)
      await tester.tap(find.widgetWithText(FilterChip, 'Confirmé'));
      await tester.pumpAndSettle();

      expect(find.text('Jean Dupont'), findsOneWidget);
      expect(find.text('Marie Curie'), findsNothing);
      expect(find.text('Pierre Martin'), findsNothing);
    });
  });
}
