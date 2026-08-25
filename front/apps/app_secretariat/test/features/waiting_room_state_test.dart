import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_secretariat/features/waiting_room/waiting_room_state.dart';

void main() {
  final entries = [
    WaitingRoomEntry(
      id: 'w1',
      cabinetId: 'c1',
      patientId: 'p1',
      patientName: 'Alice',
      arrivedAt: DateTime(2026, 1, 1, 9),
    ),
  ];

  // #5157 : WaitingRoomLoaded gagne actionError/actionInProgress, calqués
  // sur AgendaLoaded.
  group('WaitingRoomLoaded — actionError / actionInProgress (#5157)', () {
    test('compile sans actionError/actionInProgress (défauts null/false)',
        () {
      final loaded = WaitingRoomLoaded(entries);

      expect(loaded.actionInProgress, isFalse);
      expect(loaded.actionError, isNull);
    });

    test('copyWith(actionError: ...) conserve entries et fixe actionError',
        () {
      final loaded = WaitingRoomLoaded(entries);

      final withError = loaded.copyWith(actionError: 'x');

      expect(withError.entries, loaded.entries);
      expect(withError.actionError, 'x');
    });

    test('copyWith(clearActionError: true) remet actionError à null', () {
      final loaded = WaitingRoomLoaded(entries, actionError: 'x');

      final cleared = loaded.copyWith(clearActionError: true);

      expect(cleared.actionError, isNull);
    });

    test(
        'deux WaitingRoomLoaded mêmes entries mais actionError différents '
        'ne sont pas égaux', () {
      final a = WaitingRoomLoaded(entries, actionError: 'x');
      final b = WaitingRoomLoaded(entries, actionError: 'y');

      expect(a == b, isFalse);
    });
  });
}
