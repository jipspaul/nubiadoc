import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_practicien/features/agenda/agenda_bloc.dart';
import 'package:app_practicien/features/agenda/agenda_event.dart';
import 'package:app_practicien/features/agenda/agenda_page.dart';
import 'package:app_practicien/features/agenda/agenda_state.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockGetCabinetAgendaUseCase extends Mock
    implements GetCabinetAgendaUseCase {}

class MockConfirmAppointmentUseCase extends Mock
    implements ConfirmAppointmentUseCase {}

class MockStartConsultationUseCase extends Mock
    implements StartConsultationUseCase {}

class MockAgendaBloc extends MockBloc<AgendaEvent, AgendaState>
    implements AgendaBloc {}

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

AgendaBloc _makeBloc({
  required MockGetCabinetAgendaUseCase getAgenda,
  required MockConfirmAppointmentUseCase confirm,
  required MockStartConsultationUseCase start,
}) =>
    AgendaBloc(
      getAgenda: getAgenda,
      confirmAppointment: confirm,
      startConsultation: start,
    );

Widget _wrap(AgendaBloc bloc) => MaterialApp(
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

  setUp(() {
    mockGetAgenda = MockGetCabinetAgendaUseCase();
    mockConfirm = MockConfirmAppointmentUseCase();
    mockStart = MockStartConsultationUseCase();
  });

  group('AgendaBloc', () {
    blocTest<AgendaBloc, AgendaState>(
      'émet Loading puis Loaded avec les entrées',
      build: () {
        when(() => mockGetAgenda(any()))
            .thenAnswer((_) async => Right([_entry]));
        return _makeBloc(
            getAgenda: mockGetAgenda,
            confirm: mockConfirm,
            start: mockStart);
      },
      act: (bloc) =>
          bloc.add(AgendaLoadRequested(weekStart: _weekStart)),
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
            getAgenda: mockGetAgenda,
            confirm: mockConfirm,
            start: mockStart);
      },
      act: (bloc) =>
          bloc.add(AgendaLoadRequested(weekStart: _weekStart)),
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
            getAgenda: mockGetAgenda,
            confirm: mockConfirm,
            start: mockStart);
      },
      act: (bloc) =>
          bloc.add(AgendaLoadRequested(weekStart: _weekStart)),
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
            getAgenda: mockGetAgenda,
            confirm: mockConfirm,
            start: mockStart);
      },
      act: (bloc) =>
          bloc.add(AgendaWeekChanged(weekStart: _weekStart)),
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
            getAgenda: mockGetAgenda,
            confirm: mockConfirm,
            start: mockStart);
      },
      seed: () =>
          AgendaLoaded(entries: [_entry], weekStart: _weekStart),
      act: (bloc) => bloc.add(
          const AgendaAppointmentConfirmRequested(appointmentId: 'ag-1')),
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
            getAgenda: mockGetAgenda,
            confirm: mockConfirm,
            start: mockStart);
      },
      seed: () =>
          AgendaLoaded(entries: [_entry], weekStart: _weekStart),
      act: (bloc) => bloc.add(
          const AgendaAppointmentConfirmRequested(appointmentId: 'ag-1')),
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
      'StartConsultation recharge l\'agenda après succès',
      build: () {
        when(() => mockGetAgenda(any()))
            .thenAnswer((_) async => Right([_entry]));
        when(() => mockStart(any()))
            .thenAnswer((_) async => const Right(_session));
        return _makeBloc(
            getAgenda: mockGetAgenda,
            confirm: mockConfirm,
            start: mockStart);
      },
      seed: () =>
          AgendaLoaded(entries: [_entry], weekStart: _weekStart),
      act: (bloc) => bloc.add(
          const AgendaConsultationStartRequested(appointmentId: 'ag-1')),
      expect: () => [
        AgendaLoaded(
            entries: [_entry], weekStart: _weekStart, actionInProgress: true),
        const AgendaLoading(),
        AgendaLoaded(entries: [_entry], weekStart: _weekStart),
      ],
    );
  });

  // ---------------------------------------------------------------------------
  // Widget tests
  // ---------------------------------------------------------------------------

  group('AgendaPage (widget)', () {
    testWidgets('affiche le chargement initialement', (tester) async {
      when(() => mockGetAgenda(any()))
          .thenAnswer((_) async => Right([_entry]));
      final bloc =
          _makeBloc(getAgenda: mockGetAgenda, confirm: mockConfirm, start: mockStart);
      await tester.pumpWidget(_wrap(bloc));
      expect(find.byKey(const Key('agenda_loading')), findsOneWidget);
    });

    testWidgets('affiche la liste après chargement', (tester) async {
      when(() => mockGetAgenda(any()))
          .thenAnswer((_) async => Right([_entry]));
      final bloc =
          _makeBloc(getAgenda: mockGetAgenda, confirm: mockConfirm, start: mockStart)
            ..add(AgendaLoadRequested(weekStart: _weekStart));
      await tester.pumpWidget(_wrap(bloc));
      await tester.pump();
      expect(find.byKey(const Key('entry_ag-1')), findsOneWidget);
    });

    testWidgets('affiche l\'état vide quand aucun rendez-vous', (tester) async {
      when(() => mockGetAgenda(any()))
          .thenAnswer((_) async => const Right([]));
      final bloc =
          _makeBloc(getAgenda: mockGetAgenda, confirm: mockConfirm, start: mockStart)
            ..add(AgendaLoadRequested(weekStart: _weekStart));
      await tester.pumpWidget(_wrap(bloc));
      await tester.pump();
      expect(find.byKey(const Key('agenda_empty')), findsOneWidget);
    });

    testWidgets('affiche une erreur en cas d\'échec', (tester) async {
      when(() => mockGetAgenda(any())).thenAnswer(
        (_) async => Left(NetworkFailure('Pas de réseau')),
      );
      final bloc =
          _makeBloc(getAgenda: mockGetAgenda, confirm: mockConfirm, start: mockStart)
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
    testWidgets('FAB tap ouvre le bottom sheet sélecteur patient', (tester) async {
      final mockBloc = MockAgendaBloc();
      when(() => mockBloc.state).thenReturn(
        AgendaLoaded(entries: const [], weekStart: _weekStart),
      );

      GetIt.instance.registerFactory<AgendaBloc>(() => mockBloc);
      addTearDown(GetIt.instance.reset);

      await tester.pumpWidget(const MaterialApp(home: AgendaPage()));
      await tester.pump();

      expect(find.byKey(const Key('agenda_fab_consultation')), findsOneWidget);

      await tester.tap(find.byKey(const Key('agenda_fab_consultation')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('patient_picker_title')), findsOneWidget);
      expect(find.byKey(const Key('patient_pick_pat-1')), findsOneWidget);
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
      expect(find.byKey(const Key('agenda_date_filter_button')), findsOneWidget);
    });

    testWidgets(
        'filtre par date range — exclut les RDV hors range',
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
}
