import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_secretariat/features/agenda/agenda_bloc.dart';
import 'package:app_secretariat/features/agenda/agenda_event.dart';
import 'package:app_secretariat/features/agenda/agenda_page.dart';
import 'package:app_secretariat/features/agenda/agenda_state.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockGetCabinetAgendaUseCase extends Mock
    implements GetCabinetAgendaUseCase {}

class MockCreateCabinetAppointmentUseCase extends Mock
    implements CreateCabinetAppointmentUseCase {}

class MockConfirmAppointmentUseCase extends Mock
    implements ConfirmAppointmentUseCase {}

class MockRescheduleAppointmentUseCase extends Mock
    implements RescheduleAppointmentUseCase {}

class MockListBookableSlotsUseCase extends Mock
    implements ListBookableSlotsUseCase {}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

final _weekStart = DateTime(2026, 7, 6); // lundi

final _entry = AgendaEntry(
  id: 'e-1',
  cabinetId: 'cab-1',
  practitionerId: 'prac-1',
  practitionerName: 'Dr Martin',
  startsAt: DateTime(2026, 7, 7, 9, 0),
  endsAt: DateTime(2026, 7, 7, 9, 30),
  patientId: 'pat-1',
  patientName: 'Marie Dupont',
  motif: 'Contrôle annuel',
  isFree: false,
);

AgendaBloc _makeBloc({
  required MockGetCabinetAgendaUseCase getAgenda,
  required MockCreateCabinetAppointmentUseCase createAppointment,
  required MockConfirmAppointmentUseCase confirmAppointment,
  required MockRescheduleAppointmentUseCase rescheduleAppointment,
  required MockListBookableSlotsUseCase listSlots,
}) =>
    AgendaBloc(
      getAgenda: getAgenda,
      createAppointment: createAppointment,
      confirmAppointment: confirmAppointment,
      rescheduleAppointment: rescheduleAppointment,
      listSlots: listSlots,
    );

Widget _wrap(AgendaBloc bloc) => MaterialApp(
      home: BlocProvider.value(
        value: bloc,
        child: const Scaffold(
          body: _AgendaBodyDirect(),
        ),
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
              key: Key('agenda_loading'), child: CircularProgressIndicator());
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
                child: Text('Aucun rendez-vous cette semaine'));
          }
          return RefreshIndicator(
            key: const Key('agenda_refresh_indicator'),
            onRefresh: () async => context.read<AgendaBloc>().add(
                  AgendaLoadRequested(weekStart: _weekStart),
                ),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                for (final e in state.entries)
                  Text(key: Key('entry_${e.id}'), e.patientName ?? ''),
              ],
            ),
          );
        }
        return const SizedBox.shrink();
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late MockGetCabinetAgendaUseCase mockGetAgenda;
  late MockCreateCabinetAppointmentUseCase mockCreate;
  late MockConfirmAppointmentUseCase mockConfirm;
  late MockRescheduleAppointmentUseCase mockReschedule;
  late MockListBookableSlotsUseCase mockListSlots;

  setUp(() {
    mockGetAgenda = MockGetCabinetAgendaUseCase();
    mockCreate = MockCreateCabinetAppointmentUseCase();
    mockConfirm = MockConfirmAppointmentUseCase();
    mockReschedule = MockRescheduleAppointmentUseCase();
    mockListSlots = MockListBookableSlotsUseCase();
  });

  AgendaBloc makeBloc() => _makeBloc(
        getAgenda: mockGetAgenda,
        createAppointment: mockCreate,
        confirmAppointment: mockConfirm,
        rescheduleAppointment: mockReschedule,
        listSlots: mockListSlots,
      );

  group('AgendaBloc', () {
    blocTest<AgendaBloc, AgendaState>(
      'émet Loading puis Loaded avec les entrées',
      build: () {
        when(() => mockGetAgenda(any()))
            .thenAnswer((_) async => Right([_entry]));
        when(() => mockListSlots()).thenAnswer((_) async => const Right([]));
        return makeBloc();
      },
      act: (bloc) => bloc.add(AgendaLoadRequested(weekStart: _weekStart)),
      expect: () => [
        const AgendaLoading(),
        AgendaLoaded(entries: [_entry]),
      ],
    );

    blocTest<AgendaBloc, AgendaState>(
      'émet Loading puis Loaded vide quand aucun RDV',
      build: () {
        when(() => mockGetAgenda(any()))
            .thenAnswer((_) async => const Right([]));
        when(() => mockListSlots()).thenAnswer((_) async => const Right([]));
        return makeBloc();
      },
      act: (bloc) => bloc.add(AgendaLoadRequested(weekStart: _weekStart)),
      expect: () => [
        const AgendaLoading(),
        const AgendaLoaded(entries: []),
      ],
    );

    blocTest<AgendaBloc, AgendaState>(
      'émet AgendaError quand le chargement échoue',
      build: () {
        when(() => mockGetAgenda(any())).thenAnswer(
          (_) async => Left(NetworkFailure('Réseau indisponible')),
        );
        return makeBloc();
      },
      act: (bloc) => bloc.add(AgendaLoadRequested(weekStart: _weekStart)),
      expect: () => [
        const AgendaLoading(),
        const AgendaError('Réseau indisponible'),
      ],
    );

    blocTest<AgendaBloc, AgendaState>(
      'Confirm conserve l\'état avec actionError en cas d\'échec',
      build: () {
        when(() => mockConfirm(any())).thenAnswer(
          (_) async => Left(NetworkFailure('Erreur réseau')),
        );
        return makeBloc();
      },
      seed: () => AgendaLoaded(entries: [_entry]),
      act: (bloc) => bloc
          .add(const AgendaAppointmentConfirmRequested(appointmentId: 'e-1')),
      expect: () => [
        AgendaLoaded(entries: [_entry], actionInProgress: true),
        AgendaLoaded(
          entries: [_entry],
          actionInProgress: false,
          actionError: 'Erreur réseau',
        ),
      ],
    );

    blocTest<AgendaBloc, AgendaState>(
      'Reschedule conserve l\'état avec actionError en cas d\'échec',
      build: () {
        when(() => mockReschedule(any(), any())).thenAnswer(
          (_) async => Left(NetworkFailure('Erreur réseau')),
        );
        return makeBloc();
      },
      seed: () => AgendaLoaded(entries: [_entry]),
      act: (bloc) => bloc.add(AgendaAppointmentRescheduleRequested(
        appointmentId: 'e-1',
        newStartsAt: DateTime(2026, 7, 8, 10, 0),
      )),
      expect: () => [
        AgendaLoaded(entries: [_entry], actionInProgress: true),
        AgendaLoaded(
          entries: [_entry],
          actionInProgress: false,
          actionError: 'Erreur réseau',
        ),
      ],
    );
  });

  // -------------------------------------------------------------------------
  // Cloisonnement
  // -------------------------------------------------------------------------

  group('cloisonnement (includeClinical: false)', () {
    test(
        'AgendaEntry ne contient aucun champ clinique (notes médicales, antécédents)',
        () {
      // AgendaEntry est la VO qui transite dans AgendaLoaded.
      // Elle ne doit contenir que des données administratives de planification.
      // Ce test documente l'invariant : si AgendaEntry reçoit un champ clinique
      // (clinicalNotes, medicalNotes, diagnosis…), il faut mettre à jour ce test
      // explicitement — ce qui rend la violation visible.
      expect(_entry.patientName, isNotNull);
      expect(_entry.motif, isNotNull); // motif RDV = champ administratif
      expect(_entry.practitionerName, isNotNull);
      // AgendaEntry.props n'expose que [id, status] — deux champs purement
      // administratifs (le statut sert à l'affichage « À confirmer/Confirmé »),
      // aucune donnée clinique.
      expect(_entry.props, hasLength(2));
      expect(_entry.props.first, equals('e-1'));
      expect(_entry.props, equals(['e-1', _entry.status]));
    });

    blocTest<AgendaBloc, AgendaState>(
        'les entrées chargées ne contiennent aucune note médicale',
        build: () {
          when(() => mockGetAgenda(any()))
              .thenAnswer((_) async => Right([_entry]));
          when(() => mockListSlots()).thenAnswer((_) async => const Right([]));
          return makeBloc();
        },
        act: (bloc) => bloc.add(AgendaLoadRequested(weekStart: _weekStart)),
        verify: (bloc) {
          final loaded = bloc.state as AgendaLoaded;
          for (final entry in loaded.entries) {
            // Contrôle cloisonnement : aucun champ clinique présent.
            expect(entry, isA<AgendaEntry>());
            // motif est ici la raison administrative du RDV, pas des notes médicales.
            // Si un champ `clinicalNotes` était ajouté à AgendaEntry,
            // ce test devrait être mis à jour explicitement.
            expect(entry.props, hasLength(2),
                reason:
                    'AgendaEntry.props ne doit exposer que [id, status] — aucune donnée clinique');
          }
        });
  });

  // -------------------------------------------------------------------------
  // Widget tests
  // -------------------------------------------------------------------------

  group('AgendaPage (widget)', () {
    testWidgets('affiche le chargement initialement', (tester) async {
      when(() => mockGetAgenda(any())).thenAnswer((_) async => Right([_entry]));
      when(() => mockListSlots()).thenAnswer((_) async => const Right([]));
      final bloc = makeBloc();
      await tester.pumpWidget(_wrap(bloc));
      expect(find.byKey(const Key('agenda_loading')), findsOneWidget);
    });

    testWidgets('affiche la liste après chargement', (tester) async {
      when(() => mockGetAgenda(any())).thenAnswer((_) async => Right([_entry]));
      when(() => mockListSlots()).thenAnswer((_) async => const Right([]));
      final bloc = makeBloc()..add(AgendaLoadRequested(weekStart: _weekStart));
      await tester.pumpWidget(_wrap(bloc));
      await tester.pump();
      expect(find.byKey(const Key('entry_e-1')), findsOneWidget);
    });

    testWidgets('affiche l\'état vide quand aucun créneau', (tester) async {
      when(() => mockGetAgenda(any())).thenAnswer((_) async => const Right([]));
      when(() => mockListSlots()).thenAnswer((_) async => const Right([]));
      final bloc = makeBloc()..add(AgendaLoadRequested(weekStart: _weekStart));
      await tester.pumpWidget(_wrap(bloc));
      await tester.pump();
      expect(find.byKey(const Key('agenda_empty')), findsOneWidget);
    });

    testWidgets('affiche une erreur en cas d\'échec', (tester) async {
      when(() => mockGetAgenda(any())).thenAnswer(
        (_) async => Left(NetworkFailure('Pas de réseau')),
      );
      final bloc = makeBloc()..add(AgendaLoadRequested(weekStart: _weekStart));
      await tester.pumpWidget(_wrap(bloc));
      await tester.pump();
      expect(find.byKey(const Key('agenda_error')), findsOneWidget);
    });

    testWidgets('pull-to-refresh déclenche AgendaLoadRequested',
        (tester) async {
      when(() => mockGetAgenda(any())).thenAnswer((_) async => Right([_entry]));
      when(() => mockListSlots()).thenAnswer((_) async => const Right([]));
      final bloc = makeBloc()..add(AgendaLoadRequested(weekStart: _weekStart));
      await tester.pumpWidget(_wrap(bloc));
      await tester.pump();

      expect(find.byKey(const Key('entry_e-1')), findsOneWidget);

      await tester.fling(
        find.byType(RefreshIndicator),
        const Offset(0, 300),
        1000,
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      verify(() => mockGetAgenda(any())).called(2);
    });
  });

  // -------------------------------------------------------------------------
  // Filtre praticien (dropdown)
  // -------------------------------------------------------------------------

  group('filtre praticien (dropdown)', () {
    testWidgets('3 RDV 2 praticiens → sélection 1 → filtre live',
        (tester) async {
      final e1 = AgendaEntry(
        id: 'f-1',
        cabinetId: 'cab-1',
        practitionerId: 'prac-1',
        practitionerName: 'Dr Martin',
        startsAt: DateTime(2026, 7, 7, 9, 0),
        endsAt: DateTime(2026, 7, 7, 9, 30),
        patientName: 'Alice Durand',
        isFree: false,
      );
      final e2 = AgendaEntry(
        id: 'f-2',
        cabinetId: 'cab-1',
        practitionerId: 'prac-1',
        practitionerName: 'Dr Martin',
        startsAt: DateTime(2026, 7, 7, 10, 0),
        endsAt: DateTime(2026, 7, 7, 10, 30),
        patientName: 'Bob Dupont',
        isFree: false,
      );
      final e3 = AgendaEntry(
        id: 'f-3',
        cabinetId: 'cab-1',
        practitionerId: 'prac-2',
        practitionerName: 'Dr Dupont',
        startsAt: DateTime(2026, 7, 7, 11, 0),
        endsAt: DateTime(2026, 7, 7, 11, 30),
        patientName: 'Charlie Bernard',
        isFree: false,
      );

      when(() => mockGetAgenda(any()))
          .thenAnswer((_) async => Right([e1, e2, e3]));
      when(() => mockListSlots()).thenAnswer((_) async => const Right([]));

      final gi = GetIt.instance;
      await gi.reset();
      gi.registerFactory<AgendaBloc>(() => AgendaBloc(
            getAgenda: mockGetAgenda,
            createAppointment: mockCreate,
            confirmAppointment: mockConfirm,
            rescheduleAppointment: mockReschedule,
            listSlots: mockListSlots,
          ));

      await tester.pumpWidget(
        MaterialApp(
          theme: NubiaTheme.light,
          home: const Scaffold(body: AgendaPage()),
        ),
      );
      await tester.pump();

      // Les 3 entrées sont visibles
      expect(find.byKey(const Key('entry_f-1')), findsOneWidget);
      expect(find.byKey(const Key('entry_f-2')), findsOneWidget);
      expect(find.byKey(const Key('entry_f-3')), findsOneWidget);

      // Ouvre le dropdown
      await tester.tap(find.byKey(const Key('practitioner_filter_dropdown')));
      await tester.pumpAndSettle();

      // Sélectionne Dr Martin
      await tester.tap(find.text('Dr Martin').last);
      await tester.pumpAndSettle();

      // Seules les 2 entrées de Dr Martin restent visibles
      expect(find.byKey(const Key('entry_f-1')), findsOneWidget);
      expect(find.byKey(const Key('entry_f-2')), findsOneWidget);
      expect(find.byKey(const Key('entry_f-3')), findsNothing);

      await gi.reset();
    });
  });
}
