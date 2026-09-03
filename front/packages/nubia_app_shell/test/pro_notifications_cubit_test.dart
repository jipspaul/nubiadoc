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

  // Le constructeur poll immédiatement le total serveur (#6279) — stub
  // systématique pour tous les tests, sauf ceux qui vérifient explicitement
  // ce comptage.
  void stubUnreadCount(int count) {
    when(() => repo.getUnreadCount()).thenAnswer((_) async => Right(count));
  }

  group('refreshUnreadCount', () {
    blocTest<ProNotificationsCubit, ProNotificationsState>(
      'poll initial (constructeur) : unreadCount reflète le total serveur',
      setUp: () => stubUnreadCount(2),
      build: () => ProNotificationsCubit(repository: repo),
      expect: () => [
        const ProNotificationsState(unreadCount: 2),
      ],
      verify: (_) => verify(() => repo.getUnreadCount()).called(1),
    );

    blocTest<ProNotificationsCubit, ProNotificationsState>(
      'échec silencieux : le compteur précédent est conservé',
      setUp: () => when(() => repo.getUnreadCount())
          .thenAnswer((_) async => const Left(_serverFailure)),
      build: () => ProNotificationsCubit(repository: repo),
      expect: () => <ProNotificationsState>[],
    );
  });

  group('loadList', () {
    blocTest<ProNotificationsCubit, ProNotificationsState>(
      'charge la liste et rafraîchit unreadCount depuis le total serveur, '
      'pas depuis la page chargée (#6279)',
      setUp: () {
        // Les 2 items de la page chargée sont déjà lus, mais le total
        // serveur (5) reste le total réel : avant #6279, unreadCount aurait
        // été recalculé à 0 depuis cette page.
        stubUnreadCount(5);
        when(() => repo.getNotifications()).thenAnswer((_) async =>
            Right([_notif('1', read: true), _notif('2', read: true)]));
      },
      build: () => ProNotificationsCubit(repository: repo),
      // Laisse le poll initial du constructeur se résoudre avant d'agir,
      // sinon sa résolution tardive pourrait s'intercaler entre les états
      // attendus ci-dessous.
      act: (cubit) async {
        await Future<void>.delayed(Duration.zero);
        await cubit.loadList();
      },
      expect: () => [
        const ProNotificationsState(unreadCount: 5),
        const ProNotificationsState(unreadCount: 5, isLoadingList: true),
        ProNotificationsState(
          unreadCount: 5,
          notifications: [_notif('1', read: true), _notif('2', read: true)],
        ),
        // refreshUnreadCount() re-appelé en fin de loadList : même total
        // (5) → Bloc dédoublonne, aucun état supplémentaire émis.
      ],
    );

    blocTest<ProNotificationsCubit, ProNotificationsState>(
      'émet une erreur exploitable par le panneau en cas de Left(Failure)',
      setUp: () {
        stubUnreadCount(0);
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
        stubUnreadCount(2);
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
        stubUnreadCount(2);
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
