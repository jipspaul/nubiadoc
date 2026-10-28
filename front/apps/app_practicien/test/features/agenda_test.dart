import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_practicien/features/agenda/agenda_bloc.dart';
import 'package:app_practicien/features/agenda/agenda_event.dart';
import 'package:app_practicien/features/agenda/agenda_page.dart';
import 'package:app_practicien/features/agenda/agenda_state.dart';
import 'package:app_practicien/features/patients/patients_bloc.dart';
import 'package:app_practicien/features/patients/patients_event.dart';
import 'package:app_practicien/features/patients/patients_state.dart';
import 'package:app_practicien/session/pro_auth_cubit.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockGetCabinetAgendaUseCase extends Mock
    implements GetCabinetAgendaUseCase {}

class MockConfirmAppointmentUseCase extends Mock
    implements ConfirmAppointmentUseCase {}

class MockStartConsultationUseCase extends Mock
    implements StartConsultationUseCase {}

class MockCreateAppointmentSeriesUseCase extends Mock
    implements CreateAppointmentSeriesUseCase {}

class MockCancelCabinetAppointmentUseCase extends Mock
    implements CancelCabinetAppointmentUseCase {}

class MockAgendaBloc extends MockBloc<AgendaEvent, AgendaState>
    implements AgendaBloc {}

class MockPatientsBloc extends MockBloc<PatientsEvent, PatientsState>
    implements PatientsBloc {}

class MockProAuthCubit extends MockCubit<AuthState> implements ProAuthCubit {}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

final _weekStart = DateTime(2026, 6, 16); // Monday

final _entry = AgendaEntry(
  id: 'ag-1',
  cabinetId: 'cab-1',
  practitionerId: 'prac-1',
  practitionerName: 'Dr. Dupont',
  startsAt: DateTime(2026, 6, 16, 9, 0),
  endsAt: DateTime(2026, 6, 16, 9, 30),
  patientId: 'pat-1',
  patientName: 'Marie Martin',
  motif: 'Détartrage',
  isFree: false,
);

final _appointment = CabinetAppointment(
  id: 'ag-1',
  cabinetId: 'cab-1',
  patientId: 'pat-1',
  patientName: 'Marie Martin',
  practitionerId: 'prac-1',
  practitionerName: 'Dr. Dupont',
  startsAt: DateTime(2026, 6, 16, 9, 0),
  duration: const Duration(minutes: 30),
  motif: 'Détartrage',
  status: CabinetAppointmentStatus.confirmed,
);

const _session = ClinicalSession(
  id: 'sess-1',
  appointmentId: 'ag-1',
  status: 'in_progress',
  acts: [],
);

final _seriesOccurrenceStart = DateTime(2026, 7, 1, 9, 0);
final _seriesOccurrenceEnd = DateTime(2026, 7, 1, 9, 30);

AgendaBloc _makeBloc({
  required MockGetCabinetAgendaUseCase getAgenda,
  required MockConfirmAppointmentUseCase confirm,
  required MockStartConsultationUseCase start,
  MockCreateAppointmentSeriesUseCase? createSeries,
  MockCancelCabinetAppointmentUseCase? cancel,
}) =>
    AgendaBloc(
      getAgenda: getAgenda,
      confirmAppointment: confirm,
      startConsultation: start,
      createAppointmentSeries:
          createSeries ?? MockCreateAppointmentSeriesUseCase(),
      cancelAppointment: cancel ?? MockCancelCabinetAppointmentUseCase(),
    );

Widget _wrap(AgendaBloc bloc) => MaterialApp(
      theme: NubiaTheme.light,
      home: BlocProvider.value(
        value: bloc,
        child: const Scaffold(body: _AgendaBodyDirect()),
      ),
    );

class _AgendaBodyDirect extends StatelessWidget {
  const _AgendaBodyDirect();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AgendaBloc, AgendaState>(
      builder: (context, state) {
        if (state is AgendaLoading || state is AgendaInitial) {
          return const Center(
            key: Key('agenda_loading'),
            child: CircularProgressIndicator(),
          );
        }
        if (state is AgendaError) {
          return Center(
            key: const Key('agenda_error'),
            child: Text(state.message),
          );
        }
        if (state is AgendaLoaded) {
          if (state.entries.isEmpty) {
            return const Center(
              key: Key('agenda_empty'),
              child: Text('Aucun rendez-vous cette semaine'),
            );
          }
          return ListView(
            children: [
              for (final e in state.entries)
                Text(key: Key('entry_${e.id}'), e.patientName ?? ''),
              ElevatedButton(
                key: const Key('confirm_ag-1'),
                onPressed: () => context.read<AgendaBloc>().add(
                      const AgendaAppointmentConfirmRequested(
                          appointmentId: 'ag-1'),
                    ),
                child: const Text('Confirmer'),
              ),
              ElevatedButton(
                key: const Key('start_ag-1'),
                onPressed: () => context.read<AgendaBloc>().add(
                      const AgendaConsultationStartRequested(
                          appointmentId: 'ag-1'),
                    ),
                child: const Text('Démarrer'),
              ),
            ],
          );
        }
        return const SizedBox.shrink();
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Bloc tests
// ---------------------------------------------------------------------------

void main() {
  late MockGetCabinetAgendaUseCase mockGetAgenda;
  late MockConfirmAppointmentUseCase mockConfirm;
  late MockStartConsultationUseCase mockStart;
  late MockCancelCabinetAppointmentUseCase mockCancel;

  setUp(() {
    mockGetAgenda = MockGetCabinetAgendaUseCase();
    mockConfirm = MockConfirmAppointmentUseCase();
    mockStart = MockStartConsultationUseCase();
    mockCancel = MockCancelCabinetAppointmentUseCase();
  });

  group('AgendaBloc', () {
    blocTest<AgendaBloc, AgendaState>(
      'émet Loading puis Loaded avec les entrées',
      build: () {
        when(() => mockGetAgenda(any()))
            .thenAnswer((_) async => Right([_entry]));
        return _makeBloc(
            getAgenda: mockGetAgenda, confirm: mockConfirm, start: mockStart);
      },
      act: (bloc) => bloc.add(AgendaLoadRequested(weekStart: _weekStart)),
      expect: () => [
        const AgendaLoading(),
        AgendaLoaded(entries: [_entry], weekStart: _weekStart),
      ],
    );

    blocTest<AgendaBloc, AgendaState>(
      'émet Loading puis Loaded vide quand agenda vide',
      build: () {
        when(() => mockGetAgenda(any()))
            .thenAnswer((_) async => const Right([]));
        return _makeBloc(
            getAgenda: mockGetAgenda, confirm: mockConfirm, start: mockStart);
      },
      act: (bloc) => bloc.add(AgendaLoadRequested(weekStart: _weekStart)),
      expect: () => [
        const AgendaLoading(),
        AgendaLoaded(entries: const [], weekStart: _weekStart),
      ],
    );

    blocTest<AgendaBloc, AgendaState>(
      'émet Error quand le chargement échoue',
      build: () {
        when(() => mockGetAgenda(any())).thenAnswer(
          (_) async => Left(NetworkFailure('Réseau indisponible')),
        );
        return _makeBloc(
            getAgenda: mockGetAgenda, confirm: mockConfirm, start: mockStart);
      },
      act: (bloc) => bloc.add(AgendaLoadRequested(weekStart: _weekStart)),
      expect: () => [
        const AgendaLoading(),
        const AgendaError('Réseau indisponible'),
      ],
    );

    blocTest<AgendaBloc, AgendaState>(
      'WeekChanged recharge l\'agenda pour la nouvelle semaine',
      build: () {
        when(() => mockGetAgenda(any()))
            .thenAnswer((_) async => Right([_entry]));
        return _makeBloc(
            getAgenda: mockGetAgenda, confirm: mockConfirm, start: mockStart);
      },
      act: (bloc) => bloc.add(AgendaWeekChanged(weekStart: _weekStart)),
      expect: () => [
        const AgendaLoading(),
        AgendaLoaded(entries: [_entry], weekStart: _weekStart),
      ],
    );

    blocTest<AgendaBloc, AgendaState>(
      'Confirm recharge l\'agenda après succès',
      build: () {
        when(() => mockGetAgenda(any()))
            .thenAnswer((_) async => Right([_entry]));
        when(() => mockConfirm(any()))
            .thenAnswer((_) async => Right(_appointment));
        return _makeBloc(
            getAgenda: mockGetAgenda, confirm: mockConfirm, start: mockStart);
      },
      seed: () => AgendaLoaded(entries: [_entry], weekStart: _weekStart),
      act: (bloc) => bloc
          .add(const AgendaAppointmentConfirmRequested(appointmentId: 'ag-1')),
      expect: () => [
        AgendaLoaded(
            entries: [_entry], weekStart: _weekStart, actionInProgress: true),
        const AgendaLoading(),
        AgendaLoaded(entries: [_entry], weekStart: _weekStart),
      ],
    );

    blocTest<AgendaBloc, AgendaState>(
      'Confirm conserve l\'état courant avec erreur en cas d\'échec',
      build: () {
        when(() => mockConfirm(any())).thenAnswer(
          (_) async => Left(NetworkFailure('Erreur réseau')),
        );
        return _makeBloc(
            getAgenda: mockGetAgenda, confirm: mockConfirm, start: mockStart);
      },
      seed: () => AgendaLoaded(entries: [_entry], weekStart: _weekStart),
      act: (bloc) => bloc
          .add(const AgendaAppointmentConfirmRequested(appointmentId: 'ag-1')),
      expect: () => [
        AgendaLoaded(
            entries: [_entry], weekStart: _weekStart, actionInProgress: true),
        AgendaLoaded(
          entries: [_entry],
          weekStart: _weekStart,
          actionInProgress: false,
          actionError: 'Erreur réseau',
        ),
      ],
    );

    blocTest<AgendaBloc, AgendaState>(
      'Cancel recharge l\'agenda après succès (#6699)',
      build: () {
        when(() => mockGetAgenda(any()))
            .thenAnswer((_) async => Right([_entry]));
        when(() => mockCancel(any()))
            .thenAnswer((_) async => Right(_appointment));
        return _makeBloc(
          getAgenda: mockGetAgenda,
          confirm: mockConfirm,
          start: mockStart,
          cancel: mockCancel,
        );
      },
      seed: () => AgendaLoaded(entries: [_entry], weekStart: _weekStart),
      act: (bloc) => bloc
          .add(const AgendaAppointmentCancelRequested(appointmentId: 'ag-1')),
      expect: () => [
        AgendaLoaded(
            entries: [_entry], weekStart: _weekStart, actionInProgress: true),
        const AgendaLoading(),
        AgendaLoaded(entries: [_entry], weekStart: _weekStart),
      ],
    );

    blocTest<AgendaBloc, AgendaState>(
      'Cancel conserve l\'état courant avec erreur en cas d\'échec (#6699)',
      build: () {
        when(() => mockCancel(any())).thenAnswer(
          (_) async => Left(NetworkFailure('Erreur réseau')),
        );
        return _makeBloc(
          getAgenda: mockGetAgenda,
          confirm: mockConfirm,
          start: mockStart,
          cancel: mockCancel,
        );
      },
      seed: () => AgendaLoaded(entries: [_entry], weekStart: _weekStart),
      act: (bloc) => bloc
          .add(const AgendaAppointmentCancelRequested(appointmentId: 'ag-1')),
      expect: () => [
        AgendaLoaded(
            entries: [_entry], weekStart: _weekStart, actionInProgress: true),
        AgendaLoaded(
          entries: [_entry],
          weekStart: _weekStart,
          actionInProgress: false,
          actionError: 'Erreur réseau',
        ),
      ],
    );

    blocTest<AgendaBloc, AgendaState>(
      'StartConsultation recharge l\'agenda et expose l\'id de séance (#3367)',
      build: () {
        when(() => mockGetAgenda(any()))
            .thenAnswer((_) async => Right([_entry]));
        when(() => mockStart(any()))
            .thenAnswer((_) async => const Right(_session));
        return _makeBloc(
            getAgenda: mockGetAgenda, confirm: mockConfirm, start: mockStart);
      },
      seed: () => AgendaLoaded(entries: [_entry], weekStart: _weekStart),
      act: (bloc) => bloc
          .add(const AgendaConsultationStartRequested(appointmentId: 'ag-1')),
      expect: () => [
        AgendaLoaded(
            entries: [_entry], weekStart: _weekStart, actionInProgress: true),
        const AgendaLoading(),
        AgendaLoaded(
          entries: [_entry],
          weekStart: _weekStart,
          startedConsultationId: _session.id,
        ),
      ],
    );

    blocTest<AgendaBloc, AgendaState>(
      'StartedConsultationConsumed remet startedConsultationId à null',
      build: () => _makeBloc(
          getAgenda: mockGetAgenda, confirm: mockConfirm, start: mockStart),
      seed: () => AgendaLoaded(
        entries: [_entry],
        weekStart: _weekStart,
        startedConsultationId: 'sess-1',
      ),
      act: (bloc) => bloc.add(const AgendaStartedConsultationConsumed()),
      expect: () => [
        AgendaLoaded(entries: [_entry], weekStart: _weekStart),
      ],
    );

    blocTest<AgendaBloc, AgendaState>(
      'SeriesCreateRequested recharge l\'agenda et expose le nombre créé (#4088)',
      build: () {
        final mockCreateSeries = MockCreateAppointmentSeriesUseCase();
        when(() => mockGetAgenda(any()))
            .thenAnswer((_) async => Right([_entry]));
        when(() => mockCreateSeries(
              practitionerId: any(named: 'practitionerId'),
              patientId: any(named: 'patientId'),
              motif: any(named: 'motif'),
              occurrences: any(named: 'occurrences'),
            )).thenAnswer((_) async => Right(CreatedAppointmentSeries(
              recurrenceId: 'rec-1',
              appointments: [
                CreatedAppointmentSeriesItem(
                  id: 'app-1',
                  recurrenceIndex: 1,
                  startsAt: _seriesOccurrenceStart,
                  endsAt: _seriesOccurrenceEnd,
                ),
              ],
            )));
        return _makeBloc(
          getAgenda: mockGetAgenda,
          confirm: mockConfirm,
          start: mockStart,
          createSeries: mockCreateSeries,
        );
      },
      seed: () => AgendaLoaded(entries: [_entry], weekStart: _weekStart),
      act: (bloc) => bloc.add(AgendaSeriesCreateRequested(
        practitionerId: 'prac-1',
        patientId: 'pat-1',
        motif: 'Parodontologie',
        occurrences: [
          AppointmentSeriesOccurrence(
            startsAt: DateTime(2026, 7, 1, 9, 0),
            endsAt: DateTime(2026, 7, 1, 9, 30),
          ),
        ],
      )),
      expect: () => [
        AgendaLoaded(
            entries: [_entry], weekStart: _weekStart, actionInProgress: true),
        const AgendaLoading(),
        AgendaLoaded(
          entries: [_entry],
          weekStart: _weekStart,
          seriesAppointmentsCreated: 1,
        ),
      ],
    );

    blocTest<AgendaBloc, AgendaState>(
      'SeriesCreateRequested conserve l\'état courant avec erreur en cas d\'échec',
      build: () {
        final mockCreateSeries = MockCreateAppointmentSeriesUseCase();
        when(() => mockCreateSeries(
              practitionerId: any(named: 'practitionerId'),
              patientId: any(named: 'patientId'),
              motif: any(named: 'motif'),
              occurrences: any(named: 'occurrences'),
            )).thenAnswer((_) async => const Left(
              ServerFailure(message: 'Ce créneau vient d\'être pris.'),
            ));
        return _makeBloc(
          getAgenda: mockGetAgenda,
          confirm: mockConfirm,
          start: mockStart,
          createSeries: mockCreateSeries,
        );
      },
      seed: () => AgendaLoaded(entries: [_entry], weekStart: _weekStart),
      act: (bloc) => bloc.add(AgendaSeriesCreateRequested(
        practitionerId: 'prac-1',
        patientId: 'pat-1',
        motif: 'Parodontologie',
        occurrences: [
          AppointmentSeriesOccurrence(
            startsAt: DateTime(2026, 7, 1, 9, 0),
            endsAt: DateTime(2026, 7, 1, 9, 30),
          ),
        ],
      )),
      expect: () => [
        AgendaLoaded(
            entries: [_entry], weekStart: _weekStart, actionInProgress: true),
        AgendaLoaded(
          entries: [_entry],
          weekStart: _weekStart,
          actionInProgress: false,
          actionError: 'Ce créneau vient d\'être pris.',
        ),
      ],
    );

    blocTest<AgendaBloc, AgendaState>(
      'SeriesCreatedConsumed remet seriesAppointmentsCreated à null',
      build: () => _makeBloc(
          getAgenda: mockGetAgenda, confirm: mockConfirm, start: mockStart),
      seed: () => AgendaLoaded(
        entries: [_entry],
        weekStart: _weekStart,
        seriesAppointmentsCreated: 3,
      ),
      act: (bloc) => bloc.add(const AgendaSeriesCreatedConsumed()),
      expect: () => [
        AgendaLoaded(entries: [_entry], weekStart: _weekStart),
      ],
    );
  });

  // ---------------------------------------------------------------------------
  // Widget tests
  // ---------------------------------------------------------------------------

  group('AgendaPage (widget)', () {
    testWidgets('affiche le chargement initialement', (tester) async {
      when(() => mockGetAgenda(any())).thenAnswer((_) async => Right([_entry]));
      final bloc = _makeBloc(
          getAgenda: mockGetAgenda, confirm: mockConfirm, start: mockStart);
      await tester.pumpWidget(_wrap(bloc));
      expect(find.byKey(const Key('agenda_loading')), findsOneWidget);
    });

    testWidgets('affiche la liste après chargement', (tester) async {
      when(() => mockGetAgenda(any())).thenAnswer((_) async => Right([_entry]));
      final bloc = _makeBloc(
          getAgenda: mockGetAgenda, confirm: mockConfirm, start: mockStart)
        ..add(AgendaLoadRequested(weekStart: _weekStart));
      await tester.pumpWidget(_wrap(bloc));
      await tester.pump();
      expect(find.byKey(const Key('entry_ag-1')), findsOneWidget);
    });

    testWidgets('affiche l\'état vide quand aucun rendez-vous', (tester) async {
      when(() => mockGetAgenda(any())).thenAnswer((_) async => const Right([]));
      final bloc = _makeBloc(
          getAgenda: mockGetAgenda, confirm: mockConfirm, start: mockStart)
        ..add(AgendaLoadRequested(weekStart: _weekStart));
      await tester.pumpWidget(_wrap(bloc));
      await tester.pump();
      expect(find.byKey(const Key('agenda_empty')), findsOneWidget);
    });

    testWidgets('affiche une erreur en cas d\'échec', (tester) async {
      when(() => mockGetAgenda(any())).thenAnswer(
        (_) async => Left(NetworkFailure('Pas de réseau')),
      );
      final bloc = _makeBloc(
          getAgenda: mockGetAgenda, confirm: mockConfirm, start: mockStart)
        ..add(AgendaLoadRequested(weekStart: _weekStart));
      await tester.pumpWidget(_wrap(bloc));
      await tester.pump();
      expect(find.byKey(const Key('agenda_error')), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // FAB consultation widget tests
  // ---------------------------------------------------------------------------

  group('AgendaPage — FAB consultation (widget)', () {
    testWidgets('FAB tap ouvre le bottom sheet sélecteur patient',
        (tester) async {
      final mockBloc = MockAgendaBloc();
      when(() => mockBloc.state).thenReturn(
        AgendaLoaded(entries: const [], weekStart: _weekStart),
      );

      final patient = CabinetPatient(
        id: 'pat-1',
        cabinetId: 'cab-1',
        firstName: 'Marie',
        lastName: 'Martin',
        createdAt: DateTime(2026, 1, 1),
      );
      final mockPatientsBloc = MockPatientsBloc();
      when(() => mockPatientsBloc.state).thenReturn(PatientsLoaded([patient]));

      GetIt.instance.registerFactory<AgendaBloc>(() => mockBloc);
      GetIt.instance.registerFactory<PatientsBloc>(() => mockPatientsBloc);
      addTearDown(GetIt.instance.reset);

      await tester.pumpWidget(
          MaterialApp(theme: NubiaTheme.light, home: const AgendaPage()));
      await tester.pump();

      expect(find.byKey(const Key('agenda_fab_consultation')), findsOneWidget);

      await tester.tap(find.byKey(const Key('agenda_fab_consultation')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('patient_picker_title')), findsOneWidget);
      expect(find.byKey(const Key('patient_pick_pat-1')), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // AppBar "Série de RDV" widget tests (#4088)
  // ---------------------------------------------------------------------------

  group('AgendaPage — AppBar Série de RDV (widget)', () {
    testWidgets(
        'tap ouvre le sélecteur patient puis le formulaire de série',
        (tester) async {
      final mockBloc = MockAgendaBloc();
      when(() => mockBloc.state).thenReturn(
        AgendaLoaded(entries: const [], weekStart: _weekStart),
      );

      final patient = CabinetPatient(
        id: 'pat-1',
        cabinetId: 'cab-1',
        firstName: 'Marc',
        lastName: 'Dubois',
        createdAt: DateTime(2026, 1, 1),
      );
      final mockPatientsBloc = MockPatientsBloc();
      when(() => mockPatientsBloc.state).thenReturn(PatientsLoaded([patient]));

      final mockAuthCubit = MockProAuthCubit();
      when(() => mockAuthCubit.state).thenReturn(
        const AuthAuthenticated(
          AuthSession(
            kind: UserKind.pro,
            userId: 'user-1',
            role: ProRole.practitioner,
            practitionerId: 'prac-1',
          ),
        ),
      );

      GetIt.instance.registerFactory<AgendaBloc>(() => mockBloc);
      GetIt.instance.registerFactory<PatientsBloc>(() => mockPatientsBloc);
      addTearDown(GetIt.instance.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: NubiaTheme.light,
          home: BlocProvider<ProAuthCubit>.value(
            value: mockAuthCubit,
            child: const AgendaPage(),
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('agenda_create_series')), findsOneWidget);

      await tester.tap(find.byKey(const Key('agenda_create_series')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('patient_picker_title')), findsOneWidget);

      await tester.tap(find.byKey(const Key('patient_pick_pat-1')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('create_series_dialog')), findsOneWidget);
      expect(find.text('Série de RDV — Marc Dubois'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // DateFilter widget tests
  // ---------------------------------------------------------------------------

  group('AgendaBody — filtre par date (widget)', () {
    late MockAgendaBloc bloc;

    final entryJuly = AgendaEntry(
      id: 'ag-2',
      cabinetId: 'cab-1',
      practitionerId: 'prac-1',
      practitionerName: 'Dr. Dupont',
      startsAt: DateTime(2026, 7, 1, 10, 0),
      endsAt: DateTime(2026, 7, 1, 10, 30),
      patientId: 'pat-2',
      patientName: 'Paul Bernard',
      motif: 'Examen',
      isFree: false,
    );

    setUp(() {
      bloc = MockAgendaBloc();
    });

    Widget buildBody() => MaterialApp(
          theme: NubiaTheme.light,
          home: BlocProvider<AgendaBloc>.value(
            value: bloc,
            child: const Scaffold(body: AgendaBody()),
          ),
        );

    testWidgets('affiche le bouton filtre date en état chargé', (tester) async {
      when(() => bloc.state).thenReturn(
        AgendaLoaded(entries: [_entry], weekStart: _weekStart),
      );
      await tester.pumpWidget(buildBody());
      await tester.pumpAndSettle();
      expect(
          find.byKey(const Key('agenda_date_filter_button')), findsOneWidget);
    });

    testWidgets('filtre par date range — exclut les RDV hors range',
        (tester) async {
      when(() => bloc.state).thenReturn(
        AgendaLoaded(
          entries: [_entry, entryJuly],
          weekStart: _weekStart,
        ),
      );
      await tester.pumpWidget(buildBody());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('entry_ag-1')), findsOneWidget);
      expect(find.byKey(const Key('entry_ag-2')), findsOneWidget);

      await tester.tap(find.byKey(const Key('agenda_date_filter_button')));
      await tester.pumpAndSettle();

      // Sélectionne juin 16 → juin 16 (range d'un seul jour) dans le calendrier
      await tester.tap(find.text('16').first);
      await tester.pump();
      await tester.tap(find.text('16').first);
      await tester.pump();

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      // Seul le RDV du 16 juin est visible ; le RDV du 1er juillet est masqué
      expect(find.byKey(const Key('entry_ag-1')), findsOneWidget);
      expect(find.byKey(const Key('entry_ag-2')), findsNothing);
    });
  });

  // ---------------------------------------------------------------------------
  // Groupement par jour en heure locale, pas UTC (#6755)
  // ---------------------------------------------------------------------------

  group('AgendaBody — groupement par jour en heure locale (#6755)', () {
    const days = [
      'Lundi',
      'Mardi',
      'Mercredi',
      'Jeudi',
      'Vendredi',
      'Samedi',
      'Dimanche',
    ];
    const months = [
      'janvier',
      'février',
      'mars',
      'avril',
      'mai',
      'juin',
      'juillet',
      'août',
      'septembre',
      'octobre',
      'novembre',
      'décembre',
    ];
    String dayLabel(DateTime d) =>
        '${days[d.weekday - 1]} ${d.day} ${months[d.month - 1]}';

    testWidgets(
        'un RDV à 00:30 heure locale est groupé sous son jour local, '
        'pas sous la veille UTC', (tester) async {
      final nowLocal = DateTime.now();
      // "Aujourd'hui, 00:30 locale", peu importe le fuseau réel de la
      // machine de test ; converti en UTC pour simuler le contrat API
      // (cf. régression #3856). Si `_groupByDay` lit les champs UTC bruts
      // sans `.toLocal()`, le groupe affiché est celui de la veille.
      final localMidnight =
          DateTime(nowLocal.year, nowLocal.month, nowLocal.day, 0, 30);
      final entryMidnight = AgendaEntry(
        id: 'ag-midnight',
        cabinetId: 'cab-1',
        practitionerId: 'prac-1',
        practitionerName: 'Dr. Dupont',
        startsAt: localMidnight.toUtc(),
        endsAt: localMidnight.add(const Duration(minutes: 20)).toUtc(),
        patientId: 'pat-1',
        patientName: 'Marc Dubois',
        motif: 'Suivi',
        isFree: false,
      );

      final expectedLabel = dayLabel(localMidnight);
      final wrongLabel =
          dayLabel(localMidnight.subtract(const Duration(days: 1)));

      final bloc = MockAgendaBloc();
      when(() => bloc.state).thenReturn(
        AgendaLoaded(entries: [entryMidnight], weekStart: localMidnight),
      );

      await tester.pumpWidget(MaterialApp(
        theme: NubiaTheme.light,
        home: BlocProvider<AgendaBloc>.value(
          value: bloc,
          child: const Scaffold(body: AgendaBody()),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text(expectedLabel), findsOneWidget);
      expect(find.text(wrongLabel), findsNothing);
    });
  });

  // ---------------------------------------------------------------------------
  // « Démarrer » respecte la fenêtre starts_at ± 60min (#6951)
  // ---------------------------------------------------------------------------

  group('AgendaBody — bouton Démarrer hors fenêtre (#6951)', () {
    Widget buildBody(AgendaBloc bloc, ProAuthCubit authCubit) => MaterialApp(
          theme: NubiaTheme.light,
          home: BlocProvider<ProAuthCubit>.value(
            value: authCubit,
            child: BlocProvider<AgendaBloc>.value(
              value: bloc,
              child: const Scaffold(body: AgendaBody()),
            ),
          ),
        );

    testWidgets(
        'un RDV confirmé vieux de 7 jours n\'offre pas « Démarrer », '
        'un RDV confirmé dans la fenêtre l\'offre', (tester) async {
      final now = DateTime.now();
      final oldConfirmed = AgendaEntry(
        id: 'ag-old',
        cabinetId: 'cab-1',
        practitionerId: 'prac-1',
        practitionerName: 'Dr. Dupont',
        startsAt: now.subtract(const Duration(days: 7)),
        endsAt: now
            .subtract(const Duration(days: 7))
            .add(const Duration(minutes: 20)),
        patientId: 'pat-1',
        patientName: 'Marc Dubois',
        isFree: false,
        status: 'confirmed',
      );
      final withinWindow = AgendaEntry(
        id: 'ag-window',
        cabinetId: 'cab-1',
        practitionerId: 'prac-1',
        practitionerName: 'Dr. Dupont',
        startsAt: now.subtract(const Duration(minutes: 30)),
        endsAt: now.add(const Duration(minutes: 10)),
        patientId: 'pat-2',
        patientName: 'Karim Saïdi',
        isFree: false,
        status: 'confirmed',
      );

      final bloc = MockAgendaBloc();
      when(() => bloc.state).thenReturn(
        AgendaLoaded(entries: [oldConfirmed, withinWindow], weekStart: now),
      );

      final authCubit = MockProAuthCubit();
      when(() => authCubit.state).thenReturn(
        const AuthAuthenticated(
          AuthSession(
            kind: UserKind.pro,
            userId: 'user-1',
            role: ProRole.practitioner,
            practitionerId: 'prac-1',
          ),
        ),
      );

      await tester.pumpWidget(buildBody(bloc, authCubit));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('start_ag-old')), findsNothing);
      expect(find.byKey(const Key('start_ag-window')), findsOneWidget);
    });
  });

  group('AgendaBody — bouton Annuler (#6699)', () {
    Widget buildBody(AgendaBloc bloc, ProAuthCubit authCubit) => MaterialApp(
          theme: NubiaTheme.light,
          home: BlocProvider<ProAuthCubit>.value(
            value: authCubit,
            child: BlocProvider<AgendaBloc>.value(
              value: bloc,
              child: const Scaffold(body: AgendaBody()),
            ),
          ),
        );

    testWidgets(
        'tap sur Annuler puis confirmation dispatche '
        'AgendaAppointmentCancelRequested', (tester) async {
      final confirmedEntry = AgendaEntry(
        id: 'ag-1',
        cabinetId: 'cab-1',
        practitionerId: 'prac-1',
        practitionerName: 'Dr. Dupont',
        startsAt: _weekStart,
        endsAt: _weekStart.add(const Duration(minutes: 30)),
        patientId: 'pat-1',
        patientName: 'Marie Martin',
        motif: 'Détartrage',
        isFree: false,
        status: 'confirmed',
      );
      final bloc = MockAgendaBloc();
      when(() => bloc.state).thenReturn(
        AgendaLoaded(entries: [confirmedEntry], weekStart: _weekStart),
      );
      final authCubit = MockProAuthCubit();
      when(() => authCubit.state).thenReturn(
        const AuthAuthenticated(
          AuthSession(
            kind: UserKind.pro,
            userId: 'user-1',
            role: ProRole.practitioner,
            practitionerId: 'prac-1',
          ),
        ),
      );

      await tester.pumpWidget(buildBody(bloc, authCubit));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('cancel_ag-1')), findsOneWidget);

      await tester.tap(find.byKey(const Key('cancel_ag-1')));
      await tester.pumpAndSettle();

      expect(
          find.byKey(const Key('confirm_cancel_appointment_button')),
          findsOneWidget);

      await tester.tap(find.byKey(const Key('confirm_cancel_appointment_button')));
      await tester.pumpAndSettle();

      verify(() => bloc.add(
            const AgendaAppointmentCancelRequested(appointmentId: 'ag-1'),
          )).called(1);
    });
  });

  // ---------------------------------------------------------------------------
  // Navigation de semaine à travers le changement d'heure (#8425)
  // ---------------------------------------------------------------------------

  group('AgendaBody — navigation de semaine à travers le changement d\'heure '
      '(#8425)', () {
    late MockAgendaBloc bloc;

    setUp(() {
      bloc = MockAgendaBloc();
      registerFallbackValue(
        AgendaLoadRequested(weekStart: DateTime(2026, 1, 1)) as AgendaEvent,
      );
    });

    Widget buildBody() => MaterialApp(
          theme: NubiaTheme.light,
          home: BlocProvider<AgendaBloc>.value(
            value: bloc,
            child: const Scaffold(body: AgendaBody()),
          ),
        );

    testWidgets(
        '« Semaine suivante » avance d\'exactement 7 jours calendaires, '
        'même en traversant le passage à l\'heure d\'hiver', (tester) async {
      // Lundi 19 octobre 2026 — la semaine qui suit traverse le 25 octobre
      // (passage à l'heure d'hiver en Europe). On attend le lundi 26, pas
      // le dimanche 25 (régression #8425).
      final weekStart = DateTime(2026, 10, 19);
      when(() => bloc.state).thenReturn(
        AgendaLoaded(entries: const [], weekStart: weekStart),
      );

      await tester.pumpWidget(buildBody());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('agenda_next_week')));
      await tester.pumpAndSettle();

      final captured =
          verify(() => bloc.add(captureAny())).captured.single as AgendaEvent;
      final newWeekStart = (captured as AgendaWeekChanged).weekStart;
      expect(
        DateTime(newWeekStart.year, newWeekStart.month, newWeekStart.day),
        DateTime(2026, 10, 26),
      );
    });

    testWidgets(
        '« Semaine précédente » recule d\'exactement 7 jours calendaires, '
        'même en traversant le passage à l\'heure d\'hiver', (tester) async {
      // Lundi 26 octobre 2026 — la semaine précédente traverse le 25 octobre.
      // On attend le lundi 19, pas le dimanche 18.
      final weekStart = DateTime(2026, 10, 26);
      when(() => bloc.state).thenReturn(
        AgendaLoaded(entries: const [], weekStart: weekStart),
      );

      await tester.pumpWidget(buildBody());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('agenda_prev_week')));
      await tester.pumpAndSettle();

      final captured =
          verify(() => bloc.add(captureAny())).captured.single as AgendaEvent;
      final newWeekStart = (captured as AgendaWeekChanged).weekStart;
      expect(
        DateTime(newWeekStart.year, newWeekStart.month, newWeekStart.day),
        DateTime(2026, 10, 19),
      );
    });
  });
}
