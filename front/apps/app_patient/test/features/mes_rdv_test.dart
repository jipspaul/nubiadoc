import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
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
}
