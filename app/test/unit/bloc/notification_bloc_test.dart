import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_patient/core/error/failure.dart';
import 'package:nubia_patient/domain/entities/app_notification.dart';
import 'package:nubia_patient/domain/repositories/notification_repository.dart';
import 'package:nubia_patient/presentation/features/notifications/bloc/notification_bloc.dart';
import 'package:nubia_patient/presentation/features/notifications/bloc/notification_event.dart';
import 'package:nubia_patient/presentation/features/notifications/bloc/notification_state.dart';

class MockNotificationRepository extends Mock
    implements NotificationRepository {}

final _notifications = [
  AppNotification(
    id: 'n1',
    type: NotificationType.appointment,
    title: 'Rappel RDV',
    body: 'Votre RDV est demain à 9h00.',
    read: false,
    createdAt: DateTime(2026, 6, 6, 8, 0),
  ),
  AppNotification(
    id: 'n2',
    type: NotificationType.message,
    title: 'Nouveau message',
    body: 'Cabinet Dupont vous a écrit.',
    read: true,
    createdAt: DateTime(2026, 6, 5, 14, 30),
  ),
];

void main() {
  late MockNotificationRepository repository;

  setUpAll(() {
    registerFallbackValue(const OfflineFailure());
  });

  setUp(() {
    repository = MockNotificationRepository();
  });

  group('NotificationBloc — chargement', () {
    blocTest<NotificationBloc, NotificationState>(
      'émet Loading puis Loaded quand le repo retourne des notifications',
      build: () {
        when(() => repository.getNotifications())
            .thenAnswer((_) async => Right(_notifications));
        return NotificationBloc(repository);
      },
      act: (bloc) => bloc.add(const NotificationsLoadRequested()),
      expect: () => [
        const NotificationLoading(),
        NotificationLoaded(_notifications),
      ],
    );

    blocTest<NotificationBloc, NotificationState>(
      'émet Loading puis Error quand le repo retourne une failure',
      build: () {
        when(() => repository.getNotifications())
            .thenAnswer((_) async => const Left(NetworkFailure()));
        return NotificationBloc(repository);
      },
      act: (bloc) => bloc.add(const NotificationsLoadRequested()),
      expect: () => [
        const NotificationLoading(),
        const NotificationError('Erreur réseau. Vérifiez votre connexion.'),
      ],
    );
  });

  group('NotificationBloc — mark read', () {
    blocTest<NotificationBloc, NotificationState>(
      'marque une notification comme lue (optimiste)',
      build: () {
        when(() => repository.markRead('n1'))
            .thenAnswer((_) async => const Right(null));
        return NotificationBloc(repository);
      },
      seed: () => NotificationLoaded(_notifications),
      act: (bloc) =>
          bloc.add(const NotificationMarkReadRequested('n1')),
      expect: () => [
        NotificationLoaded([
          _notifications[0].copyWith(read: true),
          _notifications[1],
        ]),
      ],
      verify: (_) {
        verify(() => repository.markRead('n1')).called(1);
      },
    );

    blocTest<NotificationBloc, NotificationState>(
      'marque toutes les notifications comme lues',
      build: () {
        when(() => repository.markAllRead())
            .thenAnswer((_) async => const Right(null));
        return NotificationBloc(repository);
      },
      seed: () => NotificationLoaded(_notifications),
      act: (bloc) => bloc.add(const NotificationMarkAllReadRequested()),
      expect: () => [
        NotificationLoaded(
          _notifications.map((n) => n.copyWith(read: true)).toList(),
        ),
      ],
    );
  });

  group('NotificationBloc — réception push', () {
    blocTest<NotificationBloc, NotificationState>(
      'prepend la notification reçue dans la liste',
      build: () => NotificationBloc(repository),
      seed: () => NotificationLoaded(_notifications),
      act: (bloc) => bloc.add(const NotificationReceived(
        title: 'Nouveau push',
        body: 'Corps du message push',
        deepLink: '/appointments/42',
      )),
      expect: () => [
        isA<NotificationLoaded>().having(
          (s) => s.notifications.first.title,
          'titre du premier élément',
          'Nouveau push',
        ),
      ],
    );
  });
}
