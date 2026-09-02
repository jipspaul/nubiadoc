import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_app_shell/nubia_app_shell.dart';
import 'package:nubia_domain/nubia_domain.dart';

class MockNotificationRepository extends Mock
    implements NotificationRepository {}

AppNotification _notif(String id, {bool read = false}) => AppNotification(
      id: id,
      type: NotificationType.appointment,
      title: 'Titre $id',
      body: 'Corps $id',
      read: read,
      createdAt: DateTime(2026, 6, 25),
    );

const _serverFailure = ServerFailure(message: 'Erreur serveur');

void main() {
  late MockNotificationRepository repo;

  setUp(() {
    repo = MockNotificationRepository();
  });

  // Le constructeur poll immédiatement (unreadOnly: true) — stub systématique
  // pour tous les tests, sauf ceux qui vérifient explicitement ce comptage.
  void stubUnreadPoll(List<AppNotification> unread) {
    when(() => repo.getNotifications(unreadOnly: true))
        .thenAnswer((_) async => Right(unread));
  }

  group('refreshUnreadCount', () {
    blocTest<ProNotificationsCubit, ProNotificationsState>(
      'poll initial (constructeur) : unreadCount reflète unread_only=true',
      setUp: () => stubUnreadPoll([_notif('1'), _notif('2')]),
      build: () => ProNotificationsCubit(repository: repo),
      expect: () => [
        const ProNotificationsState(unreadCount: 2),
      ],
      verify: (_) =>
          verify(() => repo.getNotifications(unreadOnly: true)).called(1),
    );

    blocTest<ProNotificationsCubit, ProNotificationsState>(
      'échec silencieux : le compteur précédent est conservé',
      setUp: () => when(() => repo.getNotifications(unreadOnly: true))
          .thenAnswer((_) async => const Left(_serverFailure)),
      build: () => ProNotificationsCubit(repository: repo),
      expect: () => <ProNotificationsState>[],
    );
  });

  group('loadList', () {
    blocTest<ProNotificationsCubit, ProNotificationsState>(
      'charge la liste complète et recalcule unreadCount depuis les items',
      setUp: () {
        stubUnreadPoll([]);
        when(() => repo.getNotifications()).thenAnswer(
            (_) async => Right([_notif('1'), _notif('2', read: true)]));
      },
      build: () => ProNotificationsCubit(repository: repo),
      // Le poll initial du constructeur (`unread_only=true` → []) ne change
      // pas unreadCount (déjà 0) : Bloc dédoublonne, aucun état émis pour
      // lui — pas de `skip` à prévoir ici.
      act: (cubit) => cubit.loadList(),
      expect: () => [
        const ProNotificationsState(isLoadingList: true),
        ProNotificationsState(
          notifications: [_notif('1'), _notif('2', read: true)],
          unreadCount: 1,
        ),
      ],
    );

    blocTest<ProNotificationsCubit, ProNotificationsState>(
      'émet une erreur exploitable par le panneau en cas de Left(Failure)',
      setUp: () {
        stubUnreadPoll([]);
        when(() => repo.getNotifications())
            .thenAnswer((_) async => const Left(_serverFailure));
      },
      build: () => ProNotificationsCubit(repository: repo),
      act: (cubit) => cubit.loadList(),
      expect: () => [
        const ProNotificationsState(isLoadingList: true),
        const ProNotificationsState(error: 'Erreur serveur'),
      ],
    );
  });

  group('markRead', () {
    blocTest<ProNotificationsCubit, ProNotificationsState>(
      'marque la notification lue (optimiste) et appelle le repo',
      setUp: () {
        // Aligné sur le unreadCount du `seed` : que le poll initial du
        // constructeur se résolve avant ou après `act`, il reste un
        // no-op (même valeur) et ne pollue pas les états attendus.
        stubUnreadPoll([_notif('1'), _notif('2')]);
        when(() => repo.markRead('1'))
            .thenAnswer((_) async => const Right(null));
      },
      build: () => ProNotificationsCubit(repository: repo),
      seed: () => ProNotificationsState(
        notifications: [_notif('1'), _notif('2')],
        unreadCount: 2,
      ),
      // Laisse le poll initial du constructeur se résoudre avant d'agir : il
      // matche le `seed` ci-dessus (no-op), sinon sa résolution tardive
      // pourrait retomber après l'action et écraser son effet optimiste.
      act: (cubit) async {
        await Future<void>.delayed(Duration.zero);
        await cubit.markRead('1');
      },
      expect: () => [
        ProNotificationsState(
          notifications: [_notif('1', read: true), _notif('2')],
          unreadCount: 1,
        ),
      ],
      verify: (_) => verify(() => repo.markRead('1')).called(1),
    );
  });

  group('markAllRead', () {
    blocTest<ProNotificationsCubit, ProNotificationsState>(
      'marque toutes les notifications lues et remet unreadCount à zéro',
      setUp: () {
        // Même alignement que markRead ci-dessus — évite la course avec le
        // poll initial du constructeur.
        stubUnreadPoll([_notif('1'), _notif('2')]);
        when(() => repo.markAllRead())
            .thenAnswer((_) async => const Right(null));
      },
      build: () => ProNotificationsCubit(repository: repo),
      seed: () => ProNotificationsState(
        notifications: [_notif('1'), _notif('2')],
        unreadCount: 2,
      ),
      // Même précaution que markRead ci-dessus.
      act: (cubit) async {
        await Future<void>.delayed(Duration.zero);
        await cubit.markAllRead();
      },
      expect: () => [
        ProNotificationsState(
          notifications: [_notif('1', read: true), _notif('2', read: true)],
          unreadCount: 0,
        ),
      ],
      verify: (_) => verify(() => repo.markAllRead()).called(1),
    );
  });
}
