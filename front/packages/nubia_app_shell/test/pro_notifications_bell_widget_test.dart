import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_app_shell/nubia_app_shell.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

class MockNotificationRepository extends Mock
    implements NotificationRepository {}

AppNotification _notif(String id, {bool read = false, String? title}) =>
    AppNotification(
      id: id,
      type: NotificationType.appointment,
      title: title ?? 'Titre $id',
      body: 'Corps $id',
      read: read,
      createdAt: DateTime(2026, 6, 25),
    );

const _config = ProConfig(
  appTitle: 'Nubia Pro',
  spaceLabel: 'Cabinet Test',
  destinations: [
    ProNavDestination(
        label: 'Agenda', icon: Icons.calendar_today, route: '/agenda'),
  ],
);

const _session = AuthSession(
  kind: UserKind.pro,
  userId: 'user-1',
  role: ProRole.practitioner,
);

void main() {
  late MockNotificationRepository repo;

  setUp(() {
    repo = MockNotificationRepository();
    when(() => repo.getUnreadCount()).thenAnswer((_) async => const Right(0));
  });

  Widget buildShell() => MaterialApp(
        theme: NubiaTheme.light,
        home: ProShell(
          config: _config,
          session: _session,
          notificationRepository: repo,
        ),
      );

  testWidgets('no notificationRepository → no bell rendered', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: NubiaTheme.light,
        home: ProShell(config: _config, session: _session),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('pro_notifications_bell')), findsNothing);
  });

  testWidgets('badge affiche le compteur non-lus (poll initial)',
      (tester) async {
    when(() => repo.getUnreadCount()).thenAnswer((_) async => const Right(2));

    await tester.pumpWidget(buildShell());
    await tester.pumpAndSettle();

    final badge = tester.widget<Badge>(
      find.byKey(const Key('pro_notifications_badge')),
    );
    expect(badge.isLabelVisible, isTrue);
    expect((badge.label as Text).data, '2');
  });

  testWidgets('badge masqué quand aucune notification non-lue', (tester) async {
    await tester.pumpWidget(buildShell());
    await tester.pumpAndSettle();

    final badge = tester.widget<Badge>(
      find.byKey(const Key('pro_notifications_badge')),
    );
    expect(badge.isLabelVisible, isFalse);
  });

  testWidgets(
    'clic sur la cloche charge et affiche le panneau liste',
    (tester) async {
      when(() => repo.getNotifications()).thenAnswer(
        (_) async => Right([_notif('1', title: 'RDV confirmé')]),
      );

      await tester.pumpWidget(buildShell());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('pro_notifications_bell')));
      await tester.pumpAndSettle();

      expect(find.text('Notifications'), findsOneWidget);
      expect(find.text('RDV confirmé'), findsOneWidget);
    },
  );

  testWidgets(
    'clic sur une notification appelle markRead (#/:id/read)',
    (tester) async {
      when(() => repo.getNotifications()).thenAnswer(
        (_) async => Right([_notif('1', title: 'RDV confirmé')]),
      );
      when(() => repo.markRead('1')).thenAnswer((_) async => const Right(null));

      await tester.pumpWidget(buildShell());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('pro_notifications_bell')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('RDV confirmé'));
      await tester.pumpAndSettle();

      verify(() => repo.markRead('1')).called(1);
    },
  );

  testWidgets(
    '« Tout marquer lu » appelle repo.markAllRead',
    (tester) async {
      when(() => repo.getNotifications()).thenAnswer(
        (_) async => Right([_notif('1'), _notif('2')]),
      );
      when(() => repo.getUnreadCount())
          .thenAnswer((_) async => const Right(2));
      when(() => repo.markAllRead()).thenAnswer((_) async => const Right(null));

      await tester.pumpWidget(buildShell());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('pro_notifications_bell')));
      await tester.pumpAndSettle();

      await tester
          .tap(find.byKey(const Key('pro_notifications_mark_all_read')));
      await tester.pumpAndSettle();

      verify(() => repo.markAllRead()).called(1);
    },
  );
}
