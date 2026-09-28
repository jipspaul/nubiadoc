import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_secretariat/features/dashboard/waiting_room_summary_cubit.dart';

class _MockListWaitingRoom extends Mock implements ListWaitingRoomUseCase {}

WaitingRoomEntry _entry(String id, Duration waitedFor, {String? status}) =>
    WaitingRoomEntry(
      id: id,
      cabinetId: 'cab',
      patientId: 'p-$id',
      patientName: 'Patient $id',
      arrivedAt: DateTime.now().subtract(waitedFor),
      status: status,
    );

void main() {
  group('WaitingRoomSummaryCubit', () {
    late _MockListWaitingRoom listWaitingRoom;

    setUp(() {
      listWaitingRoom = _MockListWaitingRoom();
    });

    blocTest<WaitingRoomSummaryCubit, WaitingRoomSummaryState>(
      '#5381 : effectif présent + attente moyenne/la plus longue',
      build: () {
        when(() => listWaitingRoom()).thenAnswer(
          (_) async => Right([
            _entry('1', const Duration(minutes: 10)),
            _entry('2', const Duration(minutes: 32)),
            _entry('3', const Duration(minutes: 0)),
          ]),
        );
        return WaitingRoomSummaryCubit(listWaitingRoom: listWaitingRoom);
      },
      act: (cubit) => cubit.load(),
      expect: () => [
        const WaitingRoomSummaryLoading(),
        const WaitingRoomSummaryLoaded(
          presentCount: 3,
          averageWaitMinutes: 14,
          longestWaitMinutes: 32,
        ),
      ],
    );

    blocTest<WaitingRoomSummaryCubit, WaitingRoomSummaryState>(
      'salle d\'attente vide → 0 présent, 0 min',
      build: () {
        when(() => listWaitingRoom()).thenAnswer((_) async => const Right([]));
        return WaitingRoomSummaryCubit(listWaitingRoom: listWaitingRoom);
      },
      act: (cubit) => cubit.load(),
      expect: () => [
        const WaitingRoomSummaryLoading(),
        const WaitingRoomSummaryLoaded(
          presentCount: 0,
          averageWaitMinutes: 0,
          longestWaitMinutes: 0,
        ),
      ],
    );

    blocTest<WaitingRoomSummaryCubit, WaitingRoomSummaryState>(
      '#6925 : entrées in_consultation exclues (déjà au fauteuil, plus en salle)',
      build: () {
        when(() => listWaitingRoom()).thenAnswer(
          (_) async => Right([
            _entry('1', const Duration(minutes: 727),
                status: 'in_consultation'),
            _entry('2', const Duration(minutes: 725),
                status: 'in_consultation'),
          ]),
        );
        return WaitingRoomSummaryCubit(listWaitingRoom: listWaitingRoom);
      },
      act: (cubit) => cubit.load(),
      expect: () => [
        const WaitingRoomSummaryLoading(),
        const WaitingRoomSummaryLoaded(
          presentCount: 0,
          averageWaitMinutes: 0,
          longestWaitMinutes: 0,
        ),
      ],
    );

    blocTest<WaitingRoomSummaryCubit, WaitingRoomSummaryState>(
      '#6925 : seules les entrées checked_in comptent dans la moyenne',
      build: () {
        when(() => listWaitingRoom()).thenAnswer(
          (_) async => Right([
            _entry('1', const Duration(minutes: 10), status: 'checked_in'),
            _entry('2', const Duration(minutes: 727),
                status: 'in_consultation'),
          ]),
        );
        return WaitingRoomSummaryCubit(listWaitingRoom: listWaitingRoom);
      },
      act: (cubit) => cubit.load(),
      expect: () => [
        const WaitingRoomSummaryLoading(),
        const WaitingRoomSummaryLoaded(
          presentCount: 1,
          averageWaitMinutes: 10,
          longestWaitMinutes: 10,
        ),
      ],
    );

    blocTest<WaitingRoomSummaryCubit, WaitingRoomSummaryState>(
      'échec réseau → WaitingRoomSummaryError (pas un faux 0)',
      build: () {
        when(() => listWaitingRoom())
            .thenAnswer((_) async => const Left(NetworkFailure()));
        return WaitingRoomSummaryCubit(listWaitingRoom: listWaitingRoom);
      },
      act: (cubit) => cubit.load(),
      expect: () => [
        const WaitingRoomSummaryLoading(),
        isA<WaitingRoomSummaryError>(),
      ],
    );
  });
}
