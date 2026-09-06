import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_patient/features/notifications/notifications_bloc.dart';
import 'package:app_patient/features/notifications/notifications_event.dart';
import 'package:app_patient/features/notifications/notifications_state.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockNotificationRepository extends Mock
    implements NotificationRepository {}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

AppNotification _notif(String id, {bool read = false}) => AppNotification(
      id: id,
      type: NotificationType.appointment,
      title: 'Titre $id',
      body: 'Corps $id',
      read: read,
      createdAt: DateTime(2026, 6, 25),
    );

const _serverFailure = ServerFailure(message: 'Erreur serveur');

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late MockNotificationRepository repo;

  setUp(() {
    repo = MockNotificationRepository();
  });

  NotificationsBloc makeBloc() => NotificationsBloc(repository: repo);

  // ── État initial ──────────────────────────────────────────────────────────

  test('état initial est NotificationsInitial', () {
    expect(makeBloc().state, const NotificationsInitial());
  });

  // ── NotificationsLoadRequested ────────────────────────────────────────────

  group('NotificationsLoadRequested', () {
    blocTest<NotificationsBloc, NotificationsState>(
      'émet [Loading, Empty] quand le repo retourne une liste vide',
      build: makeBloc,
      setUp: () => when(() => repo.getNotifications())
          .thenAnswer((_) async => const Right([])),
      act: (bloc) => bloc.add(const NotificationsLoadRequested()),
      expect: () => const [NotificationsLoading(), NotificationsEmpty()],
    );

    blocTest<NotificationsBloc, NotificationsState>(
      'émet [Loading, Loaded] quand le repo retourne des notifications',
      build: makeBloc,
      setUp: () => when(() => repo.getNotifications()).thenAnswer(
        (_) async => Right([_notif('1'), _notif('2')]),
      ),
      act: (bloc) => bloc.add(const NotificationsLoadRequested()),
      expect: () => [
        const NotificationsLoading(),
        NotificationsLoaded([_notif('1'), _notif('2')]),
      ],
    );

    blocTest<NotificationsBloc, NotificationsState>(
      'émet [Loading, Error] quand le repo retourne un Left(Failure)',
      build: makeBloc,
      setUp: () => when(() => repo.getNotifications())
          .thenAnswer((_) async => const Left(_serverFailure)),
      act: (bloc) => bloc.add(const NotificationsLoadRequested()),
      expect: () => [
        const NotificationsLoading(),
        const NotificationsError('Erreur serveur'),
      ],
    );

    blocTest<NotificationsBloc, NotificationsState>(
      'émet [Loading, Error] quand le repo lève une exception',
      build: makeBloc,
      setUp: () => when(() => repo.getNotifications())
          .thenThrow(Exception('réseau indisponible')),
      act: (bloc) => bloc.add(const NotificationsLoadRequested()),
      expect: () => [
        const NotificationsLoading(),
        isA<NotificationsError>(),
      ],
    );
  });

  // ── NotificationMarkReadRequested ─────────────────────────────────────────

  group('NotificationMarkReadRequested', () {
    blocTest<NotificationsBloc, NotificationsState>(
      'est ignoré si le state courant n\'est pas Loaded',
      build: makeBloc,
      // état initial = NotificationsInitial
      act: (bloc) => bloc.add(const NotificationMarkReadRequested('1')),
      expect: () => <NotificationsState>[],
    );

    blocTest<NotificationsBloc, NotificationsState>(
      'émet Loaded avec la notification marquée lue (optimiste)',
      build: makeBloc,
      seed: () => NotificationsLoaded([_notif('1'), _notif('2')]),
      setUp: () => when(() => repo.markRead('1'))
          .thenAnswer((_) async => const Right(null)),
      act: (bloc) => bloc.add(const NotificationMarkReadRequested('1')),
      expect: () => [
        NotificationsLoaded([_notif('1', read: true), _notif('2')]),
      ],
    );

    blocTest<NotificationsBloc, NotificationsState>(
      'émet Loaded avec actionError et rollback si repo.markRead retourne '
      'un Left(Failure) — la liste reste affichée (pas de NotificationsError)',
      build: makeBloc,
      seed: () => NotificationsLoaded([_notif('1')]),
      setUp: () => when(() => repo.markRead('1'))
          .thenAnswer((_) async => const Left(_serverFailure)),
      act: (bloc) => bloc.add(const NotificationMarkReadRequested('1')),
      expect: () => [
        NotificationsLoaded([_notif('1', read: true)]),
        NotificationsLoaded(
          [_notif('1')],
          actionError: 'Erreur serveur',
        ),
      ],
    );
  });

  // ── NotificationMarkAllReadRequested ──────────────────────────────────────

  group('NotificationMarkAllReadRequested', () {
    blocTest<NotificationsBloc, NotificationsState>(
      'est ignoré si le state courant n\'est pas Loaded',
      build: makeBloc,
      act: (bloc) => bloc.add(const NotificationMarkAllReadRequested()),
      expect: () => <NotificationsState>[],
    );

    blocTest<NotificationsBloc, NotificationsState>(
      'émet Loaded avec toutes les notifications marquées lues',
      build: makeBloc,
      seed: () => NotificationsLoaded([_notif('1'), _notif('2')]),
      setUp: () => when(() => repo.markAllRead())
          .thenAnswer((_) async => const Right(null)),
      act: (bloc) => bloc.add(const NotificationMarkAllReadRequested()),
      expect: () => [
        NotificationsLoaded([_notif('1', read: true), _notif('2', read: true)]),
      ],
    );

    blocTest<NotificationsBloc, NotificationsState>(
      'émet Loaded avec actionError et rollback si repo.markAllRead retourne '
      'un Left(Failure) — la liste reste affichée (pas de NotificationsError)',
      build: makeBloc,
      seed: () => NotificationsLoaded([_notif('1')]),
      setUp: () => when(() => repo.markAllRead())
          .thenAnswer((_) async => const Left(_serverFailure)),
      act: (bloc) => bloc.add(const NotificationMarkAllReadRequested()),
      expect: () => [
        NotificationsLoaded([_notif('1', read: true)]),
        NotificationsLoaded(
          [_notif('1')],
          actionError: 'Erreur serveur',
        ),
      ],
    );
  });
}
