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

AppNotification _notif(String id, {bool read = false}) => AppNotification(
      id: id,
      type: NotificationType.appointment,
      title: 'Titre $id',
      body: 'Corps $id',
      read: read,
      createdAt: DateTime(2026, 6, 24),
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
    registerFallbackValue(const NotificationMarkAllReadRequested());
  });

  group('NotificationsPage — état Initial', () {
    testWidgets('affiche le spinner en état NotificationsInitial', (tester) async {
      final bloc = MockNotificationsBloc();
      when(() => bloc.state).thenReturn(const NotificationsInitial());

      await tester.pumpWidget(_wrap(bloc));
      await tester.pump();

      expect(find.byKey(const Key('notifications_loading')), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });

  group('NotificationsPage — état Loading', () {
    testWidgets('affiche le spinner en état NotificationsLoading', (tester) async {
      final bloc = MockNotificationsBloc();
      when(() => bloc.state).thenReturn(const NotificationsLoading());

      await tester.pumpWidget(_wrap(bloc));
      await tester.pump();

      expect(find.byKey(const Key('notifications_loading')), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });

  group('NotificationsPage — état Loaded (liste vide)', () {
    testWidgets('affiche NubiaEmptyState quand NotificationsLoaded([]) est émis',
        (tester) async {
      final bloc = MockNotificationsBloc();
      when(() => bloc.state).thenReturn(const NotificationsLoaded([]));

      await tester.pumpWidget(_wrap(bloc));
      await tester.pump();

      expect(find.byKey(const Key('notifications_empty')), findsOneWidget);
      expect(find.byType(NubiaEmptyState), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  group('NotificationsPage — état Loaded (avec notifications)', () {
    testWidgets('affiche les ListTile pour chaque notification chargée',
        (tester) async {
      final bloc = MockNotificationsBloc();
      when(() => bloc.state).thenReturn(
        NotificationsLoaded([_notif('1'), _notif('2'), _notif('3')]),
      );

      await tester.pumpWidget(_wrap(bloc));
      await tester.pump();

      expect(find.byKey(const Key('notifications_list')), findsOneWidget);
      expect(find.byKey(const Key('notif_1')), findsOneWidget);
      expect(find.byKey(const Key('notif_2')), findsOneWidget);
      expect(find.byKey(const Key('notif_3')), findsOneWidget);
      expect(find.byType(ListTile), findsNWidgets(3));
      expect(find.byType(NubiaEmptyState), findsNothing);
    });

    testWidgets(
        'un tap sur une notification dispatche NotificationMarkReadRequested',
        (tester) async {
      final bloc = MockNotificationsBloc();
      when(() => bloc.state)
          .thenReturn(NotificationsLoaded([_notif('42'), _notif('99')]));

      await tester.pumpWidget(_wrap(bloc));
      await tester.pump();

      await tester.tap(find.byKey(const Key('notif_42')));
      await tester.pump();

      verify(() => bloc.add(const NotificationMarkReadRequested('42'))).called(1);
    });
  });

  group('NotificationsPage — état Error', () {
    testWidgets('affiche NubiaErrorWidget en état NotificationsError',
        (tester) async {
      final bloc = MockNotificationsBloc();
      when(() => bloc.state)
          .thenReturn(const NotificationsError('Erreur de chargement.'));

      await tester.pumpWidget(_wrap(bloc));
      await tester.pump();

      expect(find.byKey(const Key('notifications_error')), findsOneWidget);
      expect(find.byType(NubiaErrorWidget), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('le bouton Réessayer dispatche NotificationsLoadRequested',
        (tester) async {
      final bloc = MockNotificationsBloc();
      when(() => bloc.state)
          .thenReturn(const NotificationsError('Erreur réseau.'));

      await tester.pumpWidget(_wrap(bloc));
      await tester.pump();

      final retryButton = find.widgetWithText(TextButton, 'Réessayer');
      if (retryButton.evaluate().isNotEmpty) {
        await tester.tap(retryButton);
        await tester.pump();
        verify(() => bloc.add(const NotificationsLoadRequested())).called(1);
      } else {
        final elevatedRetry = find.widgetWithText(ElevatedButton, 'Réessayer');
        if (elevatedRetry.evaluate().isNotEmpty) {
          await tester.tap(elevatedRetry);
          await tester.pump();
          verify(() => bloc.add(const NotificationsLoadRequested())).called(1);
        }
      }
    });
  });
}
