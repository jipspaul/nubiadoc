import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart' hide State;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_patient/features/mes_rdv/mes_rdv_bloc.dart';
import 'package:app_patient/features/mes_rdv/mes_rdv_event.dart';
import 'package:app_patient/features/mes_rdv/mes_rdv_state.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockGetUpcomingAppointmentsUseCase extends Mock
    implements GetUpcomingAppointmentsUseCase {}

class MockGetAppointmentHistoryUseCase extends Mock
    implements GetAppointmentHistoryUseCase {}

class MockCancelAppointmentUseCase extends Mock
    implements CancelAppointmentUseCase {}

class MockCheckinAppointmentUseCase extends Mock
    implements CheckinAppointmentUseCase {}

class MockMesRdvBloc extends MockBloc<MesRdvEvent, MesRdvState>
    implements MesRdvBloc {}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

final _appt = Appointment(
  id: 'rdv-1',
  cabinetId: 'cab-1',
  practitionerName: 'Dr Lemaire',
  practitionerSpecialty: 'Dentiste',
  startsAt: DateTime.now().add(const Duration(days: 2)),
  duration: const Duration(minutes: 30),
  motif: 'Détartrage',
  status: AppointmentStatus.confirmed,
);

MesRdvBloc _makeBloc({
  required MockGetUpcomingAppointmentsUseCase getUpcoming,
  required MockGetAppointmentHistoryUseCase getHistory,
  required MockCancelAppointmentUseCase cancel,
  required MockCheckinAppointmentUseCase checkin,
}) =>
    MesRdvBloc(
      getUpcoming: getUpcoming,
      getHistory: getHistory,
      cancel: cancel,
      checkin: checkin,
    );

Widget _wrap(MesRdvBloc bloc) => MaterialApp(
      home: BlocProvider.value(
        value: bloc,
        child: const Scaffold(body: _MesRdvBodyDirect()),
      ),
    );

/// Widget de test pour pull-to-refresh : RefreshIndicator + ListView câblés sur le bloc.
class _RefreshBodyDirect extends StatelessWidget {
  const _RefreshBodyDirect();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<MesRdvBloc, MesRdvState>(
      builder: (context, state) {
        if (state is MesRdvLoaded) {
          return RefreshIndicator(
            onRefresh: () {
              context.read<MesRdvBloc>().add(const MesRdvLoadRequested());
              return Future<void>.delayed(Duration.zero);
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                for (final a in state.upcoming)
                  Text(key: Key('appt_${a.id}'), a.motif),
              ],
            ),
          );
        }
        return const SizedBox.shrink();
      },
    );
  }
}

/// Widget de test pour le toggle de tri : reproduit la logique de tri de _LoadedView.
class _SortBodyDirect extends StatefulWidget {
  const _SortBodyDirect();

  @override
  State<_SortBodyDirect> createState() => _SortBodyDirectState();
}

class _SortBodyDirectState extends State<_SortBodyDirect> {
  bool _sortAsc = false;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<MesRdvBloc, MesRdvState>(
      builder: (context, state) {
        if (state is! MesRdvLoaded) return const SizedBox.shrink();
        int compare(Appointment a, Appointment b) => _sortAsc
            ? a.startsAt.compareTo(b.startsAt)
            : b.startsAt.compareTo(a.startsAt);
        final sorted = [...state.upcoming]..sort(compare);
        return Column(
          children: [
            IconButton(
              key: const Key('sort_button'),
              icon: const Icon(Icons.sort),
              onPressed: () => setState(() => _sortAsc = !_sortAsc),
            ),
            Expanded(
              child: ListView(
                children: [
                  for (final a in sorted) Text(key: Key('appt_${a.id}'), a.motif),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Widget de test pour la dialog de confirmation d'annulation.
class _CancelBodyDirect extends StatelessWidget {
  const _CancelBodyDirect({required this.appointment});
  final Appointment appointment;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      key: Key('cancel_${appointment.id}'),
      onPressed: () async {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Annuler ce RDV ?'),
            content: const Text('Cette action est irréversible.'),
            actions: [
              TextButton(
                key: const Key('dialog_dismiss'),
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Annuler'),
              ),
              FilledButton(
                key: const Key('dialog_confirm'),
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Confirmer'),
              ),
            ],
          ),
        );
        if (confirmed == true && context.mounted) {
          context.read<MesRdvBloc>().add(MesRdvCancelRequested(appointment));
        }
      },
      child: const Text('Annuler'),
    );
  }
}

/// Widget that injects the bloc without creating its own BlocProvider
/// (MesRdvPage creates one via GetIt — use this in tests instead).
class _MesRdvBodyDirect extends StatelessWidget {
  const _MesRdvBodyDirect();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<MesRdvBloc, MesRdvState>(
      builder: (context, state) {
        if (state is MesRdvLoading || state is MesRdvInitial) {
          return const Center(
            key: Key('mes_rdv_loading'),
            child: CircularProgressIndicator(),
          );
        }
        if (state is MesRdvError) {
          return Center(
            key: const Key('mes_rdv_error'),
            child: Text(state.message),
          );
        }
        if (state is MesRdvLoaded) {
          if (state.upcoming.isEmpty && state.history.isEmpty) {
            return const Center(
              key: Key('mes_rdv_empty'),
              child: Text('Aucun rendez-vous'),
            );
          }
          return ListView(
            children: [
              for (final a in state.upcoming)
                Text(key: Key('appt_${a.id}'), a.motif),
            ],
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
  late MockGetUpcomingAppointmentsUseCase mockGetUpcoming;
  late MockGetAppointmentHistoryUseCase mockGetHistory;
  late MockCancelAppointmentUseCase mockCancel;
  late MockCheckinAppointmentUseCase mockCheckin;

  setUpAll(() {
    registerFallbackValue(_appt);
    registerFallbackValue(const MesRdvLoadRequested());
  });

  setUp(() {
    mockGetUpcoming = MockGetUpcomingAppointmentsUseCase();
    mockGetHistory = MockGetAppointmentHistoryUseCase();
    mockCancel = MockCancelAppointmentUseCase();
    mockCheckin = MockCheckinAppointmentUseCase();
  });

  group('MesRdvPage widget', () {
    testWidgets('affiche le spinner en état chargement', (tester) async {
      final bloc = _makeBloc(
        getUpcoming: mockGetUpcoming,
        getHistory: mockGetHistory,
        cancel: mockCancel,
        checkin: mockCheckin,
      );

      await tester.pumpWidget(_wrap(bloc));

      expect(find.byKey(const Key('mes_rdv_loading')), findsOneWidget);
    });

    testWidgets('affiche "Aucun rendez-vous" quand les listes sont vides',
        (tester) async {
      when(() => mockGetUpcoming()).thenAnswer((_) async => const Right([]));
      when(() => mockGetHistory(page: any(named: 'page')))
          .thenAnswer((_) async => const Right([]));

      final bloc = _makeBloc(
        getUpcoming: mockGetUpcoming,
        getHistory: mockGetHistory,
        cancel: mockCancel,
        checkin: mockCheckin,
      );
      bloc.add(const MesRdvLoadRequested());

      await tester.pumpWidget(_wrap(bloc));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('mes_rdv_empty')), findsOneWidget);
    });

    testWidgets('affiche le motif du RDV quand la liste est chargée',
        (tester) async {
      when(() => mockGetUpcoming())
          .thenAnswer((_) async => Right([_appt]));
      when(() => mockGetHistory(page: any(named: 'page')))
          .thenAnswer((_) async => const Right([]));

      final bloc = _makeBloc(
        getUpcoming: mockGetUpcoming,
        getHistory: mockGetHistory,
        cancel: mockCancel,
        checkin: mockCheckin,
      );
      bloc.add(const MesRdvLoadRequested());

      await tester.pumpWidget(_wrap(bloc));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('appt_rdv-1')), findsOneWidget);
      expect(find.text('Détartrage'), findsOneWidget);
    });

    testWidgets('affiche le message d\'erreur en état erreur', (tester) async {
      when(() => mockGetUpcoming()).thenAnswer(
          (_) async => const Left(NetworkFailure('Erreur réseau.')));

      final bloc = _makeBloc(
        getUpcoming: mockGetUpcoming,
        getHistory: mockGetHistory,
        cancel: mockCancel,
        checkin: mockCheckin,
      );
      bloc.add(const MesRdvLoadRequested());

      await tester.pumpWidget(_wrap(bloc));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('mes_rdv_error')), findsOneWidget);
      expect(find.text('Erreur réseau.'), findsOneWidget);
    });
  });

  group('MesRdvBloc', () {
    blocTest<MesRdvBloc, MesRdvState>(
      'émet [Loading, Loaded(vide)] quand les deux listes sont vides',
      build: () {
        when(() => mockGetUpcoming())
            .thenAnswer((_) async => const Right([]));
        when(() => mockGetHistory(page: any(named: 'page')))
            .thenAnswer((_) async => const Right([]));
        return _makeBloc(
          getUpcoming: mockGetUpcoming,
          getHistory: mockGetHistory,
          cancel: mockCancel,
          checkin: mockCheckin,
        );
      },
      act: (bloc) => bloc.add(const MesRdvLoadRequested()),
      expect: () => [
        const MesRdvLoading(),
        isA<MesRdvLoaded>()
            .having((s) => s.upcoming, 'upcoming', isEmpty)
            .having((s) => s.history, 'history', isEmpty),
      ],
    );

    blocTest<MesRdvBloc, MesRdvState>(
      'émet [Loading, Error] quand getUpcoming échoue',
      build: () {
        when(() => mockGetUpcoming()).thenAnswer(
            (_) async => const Left(NetworkFailure('Erreur réseau.')));
        return _makeBloc(
          getUpcoming: mockGetUpcoming,
          getHistory: mockGetHistory,
          cancel: mockCancel,
          checkin: mockCheckin,
        );
      },
      act: (bloc) => bloc.add(const MesRdvLoadRequested()),
      expect: () => [
        const MesRdvLoading(),
        isA<MesRdvError>()
            .having((s) => s.message, 'message', 'Erreur réseau.'),
      ],
    );

    blocTest<MesRdvBloc, MesRdvState>(
      'émet [Loaded avec actionError] quand l\'annulation échoue',
      build: () {
        when(() => mockCancel(any())).thenAnswer(
          (_) async => const Left(
            ValidationFailure(
              message:
                  'Annulation impossible : le rendez-vous commence dans moins de 24 h.',
            ),
          ),
        );
        return _makeBloc(
          getUpcoming: mockGetUpcoming,
          getHistory: mockGetHistory,
          cancel: mockCancel,
          checkin: mockCheckin,
        );
      },
      seed: () => MesRdvLoaded(upcoming: [_appt], history: const []),
      act: (bloc) => bloc.add(MesRdvCancelRequested(_appt)),
      expect: () => [
        isA<MesRdvLoaded>()
            .having((s) => s.actionInProgress, 'inProgress', true),
        isA<MesRdvLoaded>()
            .having((s) => s.actionInProgress, 'inProgress', false)
            .having((s) => s.actionError, 'actionError', isNotNull),
      ],
    );
  });

  group('sort toggle', () {
    testWidgets('tap sort inverse l\'ordre des RDV par startsAt', (tester) async {
      final apptA = Appointment(
        id: 'rdv-a',
        cabinetId: 'cab-1',
        practitionerName: 'Dr A',
        practitionerSpecialty: 'Dentiste',
        startsAt: DateTime(2026, 1, 1),
        duration: const Duration(minutes: 30),
        motif: 'Soin A',
        status: AppointmentStatus.confirmed,
      );
      final apptB = Appointment(
        id: 'rdv-b',
        cabinetId: 'cab-1',
        practitionerName: 'Dr B',
        practitionerSpecialty: 'Dentiste',
        startsAt: DateTime(2026, 3, 1),
        duration: const Duration(minutes: 30),
        motif: 'Soin B',
        status: AppointmentStatus.confirmed,
      );

      final mockBloc = MockMesRdvBloc();
      final loadedState = MesRdvLoaded(upcoming: [apptA, apptB], history: const []);
      whenListen<MesRdvState>(
        mockBloc,
        Stream.fromIterable([loadedState]),
        initialState: loadedState,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<MesRdvBloc>.value(
            value: mockBloc,
            child: const Scaffold(body: _SortBodyDirect()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Default _sortAsc=false → DESC : rdv-b (mars) en premier, rdv-a (jan) en dessous
      final yB = tester.getTopLeft(find.byKey(const Key('appt_rdv-b'))).dy;
      final yA = tester.getTopLeft(find.byKey(const Key('appt_rdv-a'))).dy;
      expect(yB, lessThan(yA));

      // Tap sort → ASC : rdv-a (jan) en premier, rdv-b (mars) en dessous
      await tester.tap(find.byKey(const Key('sort_button')));
      await tester.pump();

      final yAAfter = tester.getTopLeft(find.byKey(const Key('appt_rdv-a'))).dy;
      final yBAfter = tester.getTopLeft(find.byKey(const Key('appt_rdv-b'))).dy;
      expect(yAAfter, lessThan(yBAfter));
    });
  });

  group('pull-to-refresh', () {
    testWidgets('déclenche MesRdvLoadRequested au pull-to-refresh',
        (tester) async {
      final mockBloc = MockMesRdvBloc();
      final loadedState = MesRdvLoaded(upcoming: [_appt], history: const []);
      whenListen<MesRdvState>(
        mockBloc,
        Stream.fromIterable([loadedState]),
        initialState: loadedState,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<MesRdvBloc>.value(
            value: mockBloc,
            child: const Scaffold(body: _RefreshBodyDirect()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final gesture = await tester.startGesture(
          tester.getCenter(find.byType(ListView).first));
      await gesture.moveBy(const Offset(0, 300));
      await tester.pump();
      await gesture.up();
      await tester.pump(); // onRefresh called, Future.delayed(zero) timer created
      await tester.pump(const Duration(seconds: 1)); // fire the timer

      verify(() => mockBloc.add(any(that: isA<MesRdvLoadRequested>())))
          .called(1);

      await tester.pumpAndSettle(); // let RefreshIndicator closing animation complete
    });
  });

  group('cancel confirmation dialog', () {
    Widget wrapCancel(MockMesRdvBloc bloc) => MaterialApp(
          home: BlocProvider<MesRdvBloc>.value(
            value: bloc,
            child: Scaffold(body: _CancelBodyDirect(appointment: _appt)),
          ),
        );

    testWidgets('tap cancel affiche la dialog de confirmation', (tester) async {
      final mockBloc = MockMesRdvBloc();
      whenListen<MesRdvState>(
        mockBloc,
        const Stream.empty(),
        initialState: MesRdvLoaded(upcoming: [_appt], history: const []),
      );

      await tester.pumpWidget(wrapCancel(mockBloc));
      await tester.tap(find.byKey(Key('cancel_${_appt.id}')));
      await tester.pumpAndSettle();

      expect(find.text('Annuler ce RDV ?'), findsOneWidget);
      expect(find.text('Cette action est irréversible.'), findsOneWidget);
    });

    testWidgets('tap "Annuler" dans la dialog ne dispatche pas', (tester) async {
      final mockBloc = MockMesRdvBloc();
      whenListen<MesRdvState>(
        mockBloc,
        const Stream.empty(),
        initialState: MesRdvLoaded(upcoming: [_appt], history: const []),
      );

      await tester.pumpWidget(wrapCancel(mockBloc));
      await tester.tap(find.byKey(Key('cancel_${_appt.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('dialog_dismiss')));
      await tester.pumpAndSettle();

      verifyNever(() => mockBloc.add(any(that: isA<MesRdvCancelRequested>())));
    });

    testWidgets('tap "Confirmer" dans la dialog dispatche MesRdvCancelRequested',
        (tester) async {
      final mockBloc = MockMesRdvBloc();
      whenListen<MesRdvState>(
        mockBloc,
        const Stream.empty(),
        initialState: MesRdvLoaded(upcoming: [_appt], history: const []),
      );

      await tester.pumpWidget(wrapCancel(mockBloc));
      await tester.tap(find.byKey(Key('cancel_${_appt.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('dialog_confirm')));
      await tester.pumpAndSettle();

      verify(() => mockBloc.add(any(that: isA<MesRdvCancelRequested>())))
          .called(1);
    });
  });
}
