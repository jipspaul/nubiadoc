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
      'émet [Loading, Empty] quand le repo retourne une page vide',
      build: makeBloc,
      setUp: () => when(() => repo.getPage(limit: 20)).thenAnswer(
        (_) async => const Right((notifications: [], nextCursor: null)),
      ),
      act: (bloc) => bloc.add(const NotificationsLoadRequested()),
      expect: () => const [NotificationsLoading(), NotificationsEmpty()],
    );

    blocTest<NotificationsBloc, NotificationsState>(
      'émet [Loading, Loaded] quand le repo retourne une page de '
      'notifications — une seule requête, bornée à `_pageSize` (#8323)',
      build: makeBloc,
      setUp: () => when(() => repo.getPage(limit: 20)).thenAnswer(
        (_) async => Right((
          notifications: [_notif('1'), _notif('2')],
          nextCursor: null,
        )),
      ),
      act: (bloc) => bloc.add(const NotificationsLoadRequested()),
      expect: () => [
        const NotificationsLoading(),
        NotificationsLoaded([_notif('1'), _notif('2')]),
      ],
      verify: (_) => verify(() => repo.getPage(limit: 20)).called(1),
    );

    blocTest<NotificationsBloc, NotificationsState>(
      'émet un Loaded avec hasMore=true quand la page renvoie un '
      'nextCursor (#8323)',
      build: makeBloc,
      setUp: () => when(() => repo.getPage(limit: 20)).thenAnswer(
        (_) async => Right((
          notifications: [_notif('1')],
          nextCursor: 'cursor-1',
        )),
      ),
      act: (bloc) => bloc.add(const NotificationsLoadRequested()),
      expect: () => [
        const NotificationsLoading(),
        NotificationsLoaded([_notif('1')], hasMore: true),
      ],
    );

    blocTest<NotificationsBloc, NotificationsState>(
      'émet [Loading, Error] quand le repo retourne un Left(Failure)',
      build: makeBloc,
      setUp: () => when(() => repo.getPage(limit: 20))
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
      setUp: () => when(() => repo.getPage(limit: 20))
          .thenThrow(Exception('réseau indisponible')),
      act: (bloc) => bloc.add(const NotificationsLoadRequested()),
      expect: () => [
        const NotificationsLoading(),
        isA<NotificationsError>(),
      ],
    );
  });

  // ── NotificationsLoadMoreRequested ────────────────────────────────────────

  group('NotificationsLoadMoreRequested', () {
    blocTest<NotificationsBloc, NotificationsState>(
      'est ignoré si le state courant n\'est pas Loaded',
      build: makeBloc,
      act: (bloc) => bloc.add(const NotificationsLoadMoreRequested()),
      expect: () => <NotificationsState>[],
    );

    blocTest<NotificationsBloc, NotificationsState>(
      'est ignoré si hasMore est false (dernière page déjà chargée)',
      build: makeBloc,
      seed: () => NotificationsLoaded([_notif('1')], hasMore: false),
      act: (bloc) => bloc.add(const NotificationsLoadMoreRequested()),
      expect: () => <NotificationsState>[],
      verify: (_) => verifyNever(() => repo.getPage(
            limit: any(named: 'limit'),
            cursor: any(named: 'cursor'),
          )),
    );

    blocTest<NotificationsBloc, NotificationsState>(
      'charge la page suivante et l\'ajoute à la liste existante (#8323)',
      build: makeBloc,
      setUp: () {
        // `_cursor` est un champ interne du bloc, amorcé par le premier
        // NotificationsLoadRequested — un seed ne le renseignerait pas, donc
        // le test enchaîne un chargement réel avant le `LoadMoreRequested`.
        when(() => repo.getPage(limit: 20)).thenAnswer(
          (_) async => Right((
            notifications: [_notif('1')],
            nextCursor: 'cursor-1',
          )),
        );
        when(() => repo.getPage(limit: 20, cursor: 'cursor-1')).thenAnswer(
          (_) async => Right((
            notifications: [_notif('2')],
            nextCursor: null,
          )),
        );
      },
      act: (bloc) async {
        bloc.add(const NotificationsLoadRequested());
        await Future<void>.delayed(Duration.zero);
        bloc.add(const NotificationsLoadMoreRequested());
      },
      expect: () => [
        const NotificationsLoading(),
        NotificationsLoaded([_notif('1')], hasMore: true),
        NotificationsLoaded([_notif('1')], hasMore: true, isLoadingMore: true),
        NotificationsLoaded([_notif('1'), _notif('2')], hasMore: false),
      ],
    );
  });

  // ── NotificationsUnreadCountRequested ─────────────────────────────────────

  group('NotificationsUnreadCountRequested', () {
    blocTest<NotificationsBloc, NotificationsState>(
      'émet [Loading, UnreadCountLoaded] sans paginer la liste complète',
      build: makeBloc,
      setUp: () => when(() => repo.getUnreadCount())
          .thenAnswer((_) async => const Right(3)),
      act: (bloc) => bloc.add(const NotificationsUnreadCountRequested()),
      expect: () => [
        const NotificationsLoading(),
        const NotificationsUnreadCountLoaded(3),
      ],
      verify: (_) => verifyNever(() => repo.getNotifications()),
    );

    blocTest<NotificationsBloc, NotificationsState>(
      'émet [Loading, Error] quand le repo retourne un Left(Failure)',
      build: makeBloc,
      setUp: () => when(() => repo.getUnreadCount())
          .thenAnswer((_) async => const Left(_serverFailure)),
      act: (bloc) => bloc.add(const NotificationsUnreadCountRequested()),
      expect: () => [
        const NotificationsLoading(),
        const NotificationsError('Erreur serveur'),
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
