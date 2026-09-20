//! Tests bloc : `TreatmentSessionsCubit` (#7172) — proposition de séances,
//! réordonnancement local, chargement des créneaux et prise de RDV.

import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_practicien/features/treatment_plans/treatment_sessions_cubit.dart';

class MockTreatmentSessionsRepository extends Mock
    implements TreatmentSessionsRepository {}

const _sessionA = TreatmentSession(
  id: 'sess-a',
  position: 1,
  durationMin: 30,
  quoteItemIds: ['qi-1'],
);

const _sessionB = TreatmentSession(
  id: 'sess-b',
  position: 2,
  durationMin: 45,
  quoteItemIds: ['qi-2', 'qi-3'],
);

final _slot = ProposedSlot(
  id: 'slot-1',
  practitionerId: 'prac-1',
  startsAt: DateTime(2026, 10, 5, 9),
  endsAt: DateTime(2026, 10, 5, 9, 30),
);

void main() {
  late MockTreatmentSessionsRepository repository;

  setUp(() {
    repository = MockTreatmentSessionsRepository();
  });

  TreatmentSessionsCubit buildCubit() => TreatmentSessionsCubit(
        planId: 'plan-1',
        proposeSessions: ProposeTreatmentSessionsUseCase(repository),
        proposeSlots: ProposeSessionSlotsUseCase(repository),
        scheduleSession: ScheduleTreatmentSessionUseCase(repository),
      );

  group('propose', () {
    blocTest<TreatmentSessionsCubit, TreatmentSessionsState>(
      'succès → séances proposées ajoutées à la liste',
      build: () {
        when(() => repository.proposeSessions('plan-1',
                defaultDurationMin: 30))
            .thenAnswer((_) async => const Right([_sessionA, _sessionB]));
        return buildCubit();
      },
      act: (cubit) => cubit.propose(defaultDurationMin: 30),
      expect: () => [
        const TreatmentSessionsLoaded(sessions: [], busy: true),
        const TreatmentSessionsLoaded(sessions: [_sessionA, _sessionB]),
      ],
    );

    blocTest<TreatmentSessionsCubit, TreatmentSessionsState>(
      'échec → actionError porté par l\'état, séances existantes conservées',
      build: () {
        when(() => repository.proposeSessions('plan-1',
                defaultDurationMin: 30))
            .thenAnswer((_) async => const Left(
                ValidationFailure(message: 'Aucun acte à répartir.')));
        return buildCubit();
      },
      act: (cubit) => cubit.propose(defaultDurationMin: 30),
      expect: () => [
        const TreatmentSessionsLoaded(sessions: [], busy: true),
        const TreatmentSessionsLoaded(
          sessions: [],
          actionError: 'Aucun acte à répartir.',
        ),
      ],
    );
  });

  blocTest<TreatmentSessionsCubit, TreatmentSessionsState>(
    'reorder → renumérote les positions selon le nouvel ordre visuel',
    build: () {
      when(() => repository.proposeSessions('plan-1',
              defaultDurationMin: null))
          .thenAnswer((_) async => const Right([_sessionA, _sessionB]));
      return buildCubit();
    },
    act: (cubit) async {
      await cubit.propose();
      cubit.reorder(0, 2);
    },
    skip: 2,
    expect: () => [
      TreatmentSessionsLoaded(sessions: [
        _sessionB.copyWith(position: 1),
        _sessionA.copyWith(position: 2),
      ]),
    ],
  );

  group('loadSlots', () {
    blocTest<TreatmentSessionsCubit, TreatmentSessionsState>(
      'succès → créneaux affichés pour la séance dépliée',
      build: () {
        when(() => repository.proposeSessions('plan-1',
                defaultDurationMin: null))
            .thenAnswer((_) async => const Right([_sessionA]));
        when(() => repository.proposeSlots('plan-1', 'sess-a'))
            .thenAnswer((_) async => Right([_slot]));
        return buildCubit();
      },
      act: (cubit) async {
        await cubit.propose();
        await cubit.loadSlots('sess-a');
      },
      skip: 2,
      expect: () => [
        const TreatmentSessionsLoaded(
          sessions: [_sessionA],
          expandedSessionId: 'sess-a',
          slotsLoading: true,
        ),
        TreatmentSessionsLoaded(
          sessions: const [_sessionA],
          expandedSessionId: 'sess-a',
          slots: [_slot],
        ),
      ],
    );
  });

  group('schedule', () {
    blocTest<TreatmentSessionsCubit, TreatmentSessionsState>(
      'succès → séance passe à scheduled avec l\'id du RDV créé',
      build: () {
        when(() => repository.proposeSessions('plan-1',
                defaultDurationMin: null))
            .thenAnswer((_) async => const Right([_sessionA]));
        when(() => repository.scheduleSession('plan-1', 'sess-a', 'slot-1'))
            .thenAnswer((_) async => const Right('appt-1'));
        return buildCubit();
      },
      act: (cubit) async {
        await cubit.propose();
        await cubit.schedule('sess-a', 'slot-1');
      },
      skip: 2,
      expect: () => [
        const TreatmentSessionsLoaded(sessions: [_sessionA], busy: true),
        TreatmentSessionsLoaded(sessions: [
          _sessionA.copyWith(status: 'scheduled', appointmentId: 'appt-1'),
        ]),
      ],
    );

    blocTest<TreatmentSessionsCubit, TreatmentSessionsState>(
      'créneau pris entre-temps (409) → actionError, séance inchangée',
      build: () {
        when(() => repository.proposeSessions('plan-1',
                defaultDurationMin: null))
            .thenAnswer((_) async => const Right([_sessionA]));
        when(() => repository.scheduleSession('plan-1', 'sess-a', 'slot-1'))
            .thenAnswer((_) async => const Left(ServerFailure(
                  message: 'Ce créneau vient d\'être pris, choisissez-en un autre.',
                  statusCode: 409,
                )));
        return buildCubit();
      },
      act: (cubit) async {
        await cubit.propose();
        await cubit.schedule('sess-a', 'slot-1');
      },
      skip: 2,
      expect: () => [
        const TreatmentSessionsLoaded(sessions: [_sessionA], busy: true),
        const TreatmentSessionsLoaded(
          sessions: [_sessionA],
          actionError: 'Ce créneau vient d\'être pris, choisissez-en un autre.',
        ),
      ],
    );
  });
}
