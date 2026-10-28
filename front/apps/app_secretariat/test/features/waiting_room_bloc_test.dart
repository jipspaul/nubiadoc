//! Tests bloc : `WaitingRoomBloc._onCallNext` (#6707) — aucun test
//! n'exerçait jusqu'ici le fold du bloc lui-même sur un échec de
//! `CallNextUseCase`. Les correctifs #7217/#7320 couvrent l'API, le
//! repository et le rendu du bouton, mais pas le chaînon du bloc qui doit
//! transformer un `Left(NotFoundFailure)` (`{"called": false}`) en
//! `actionError` visible plutôt qu'en rechargement silencieux.

import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_secretariat/features/waiting_room/waiting_room_bloc.dart';
import 'package:app_secretariat/features/waiting_room/waiting_room_event.dart';
import 'package:app_secretariat/features/waiting_room/waiting_room_state.dart';

class _MockWaitingRoomRepository extends Mock
    implements WaitingRoomRepository {}

final _marcDubois = WaitingRoomEntry(
  id: 'appt-1',
  cabinetId: 'c1',
  patientId: 'p1',
  patientName: 'Marc Dubois',
  arrivedAt: DateTime(2026, 9, 7, 0, 5),
  status: 'in_consultation',
);

void main() {
  late _MockWaitingRoomRepository repository;

  setUp(() {
    repository = _MockWaitingRoomRepository();
  });

  WaitingRoomBloc build() => WaitingRoomBloc(
        listWaitingRoom: ListWaitingRoomUseCase(repository),
        callNext: CallNextUseCase(repository),
        notifyPractitioner: NotifyWaitingRoomPractitionerUseCase(repository),
      );

  blocTest<WaitingRoomBloc, WaitingRoomState>(
    "call-next sur {\"called\": false} remonte actionError plutôt que de "
    'recharger la liste comme un succès silencieux (#6707)',
    build: () {
      when(() => repository.list()).thenAnswer(
        (_) async => Right([_marcDubois, _marcDubois]),
      );
      when(() => repository.callNext()).thenAnswer(
        (_) async => const Left(NotFoundFailure('Aucun patient à appeler.')),
      );
      return build();
    },
    act: (b) => b
      ..add(const WaitingRoomLoadRequested())
      ..add(const WaitingRoomCallNextRequested()),
    skip: 2,
    expect: () => [
      isA<WaitingRoomLoaded>()
          .having((s) => s.actionInProgress, 'actionInProgress', true),
      isA<WaitingRoomLoaded>()
          .having((s) => s.actionInProgress, 'actionInProgress', false)
          .having(
            (s) => s.actionError,
            'actionError',
            'Aucun patient à appeler.',
          ),
    ],
    verify: (_) {
      // La liste n'est rechargée qu'une fois (chargement initial) : le
      // chemin d'échec ne doit jamais déclencher de second `list()` comme
      // si l'appel avait réussi.
      verify(() => repository.list()).called(1);
    },
  );
}
