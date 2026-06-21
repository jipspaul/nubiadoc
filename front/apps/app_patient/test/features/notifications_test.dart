import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

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
  group('NotificationsPage — empty state', () {
    testWidgets(
        'affiche NubiaEmptyState quand Loaded([]) est émis',
        (tester) async {
      final bloc = MockNotificationsBloc();
      when(() => bloc.state)
          .thenReturn(const NotificationsLoaded([]));

      await tester.pumpWidget(_wrap(bloc));
      await tester.pump();

      expect(find.byKey(const Key('notifications_empty')), findsOneWidget);
      expect(find.byType(NubiaEmptyState), findsOneWidget);
    });
  });
}
