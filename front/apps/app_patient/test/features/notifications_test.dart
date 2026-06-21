import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_patient/features/notifications/notifications_bloc.dart';
import 'package:app_patient/features/notifications/notifications_event.dart';
import 'package:app_patient/features/notifications/notifications_page.dart';
import 'package:app_patient/features/notifications/notifications_state.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockNotificationsBloc
    extends MockBloc<NotificationsEvent, NotificationsState>
    implements NotificationsBloc {}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

AppNotification _notif(String id) => AppNotification(
      id: id,
      type: NotificationType.appointment,
      title: 'Titre $id',
      body: 'Corps $id',
      read: false,
      createdAt: DateTime(2026, 6, 21),
    );

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Widget _wrap(NotificationsBloc bloc) => MaterialApp(
      home: BlocProvider<NotificationsBloc>.value(
        value: bloc,
        child: const Scaffold(body: NotificationsPage()),
      ),
    );

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUpAll(() {
    registerFallbackValue(const NotificationMarkReadRequested('_'));
  });

  group('NotificationsPage — état Initial', () {
    testWidgets('affiche le spinner en état Initial', (tester) async {
      final bloc = MockNotificationsBloc();
      when(() => bloc.state).thenReturn(const NotificationsInitial());

      await tester.pumpWidget(_wrap(bloc));
      await tester.pump();

      expect(find.byKey(const Key('notifications_loading')), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });

  group('NotificationsPage — empty state', () {
    testWidgets('affiche NubiaEmptyState quand Loaded([]) est émis',
        (tester) async {
      final bloc = MockNotificationsBloc();
      when(() => bloc.state).thenReturn(const NotificationsLoaded([]));

      await tester.pumpWidget(_wrap(bloc));
      await tester.pump();

      expect(find.byKey(const Key('notifications_empty')), findsOneWidget);
      expect(find.byType(NubiaEmptyState), findsOneWidget);
    });
  });

  group('NotificationsPage — Loaded(2 notifs)', () {
    testWidgets('affiche 2 ListTile quand 2 notifications sont chargées',
        (tester) async {
      final bloc = MockNotificationsBloc();
      when(() => bloc.state)
          .thenReturn(NotificationsLoaded([_notif('1'), _notif('2')]));

      await tester.pumpWidget(_wrap(bloc));
      await tester.pump();

      expect(find.byKey(const Key('notif_1')), findsOneWidget);
      expect(find.byKey(const Key('notif_2')), findsOneWidget);
      expect(find.byType(ListTile), findsNWidgets(2));
    });
  });

  group('NotificationsPage — tap → mark-as-read', () {
    testWidgets(
        'un tap sur une notification dispatche NotificationMarkReadRequested',
        (tester) async {
      final bloc = MockNotificationsBloc();
      when(() => bloc.state)
          .thenReturn(NotificationsLoaded([_notif('1'), _notif('2')]));

      await tester.pumpWidget(_wrap(bloc));
      await tester.pump();

      await tester.tap(find.byKey(const Key('notif_1')));
      await tester.pump();

      verify(() => bloc.add(const NotificationMarkReadRequested('1'))).called(1);
    });
  });
}
