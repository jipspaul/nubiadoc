import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_demo/features/dashboard/bloc/dashboard_bloc.dart';
import 'package:flutter_demo/features/dashboard/bloc/dashboard_event.dart';
import 'package:flutter_demo/features/dashboard/bloc/dashboard_state.dart';
import 'package:flutter_demo/features/dashboard/dashboard_screen.dart';
import 'package:flutter_demo/features/dashboard/models/dashboard_summary.dart';
import 'package:flutter_demo/features/dashboard/widgets/dashboard_body.dart';
import 'package:flutter_demo/features/dashboard/widgets/dashboard_tile.dart';
import 'package:flutter_demo/theme/nubia_theme.dart';

class MockDashboardBloc
    extends MockBloc<DashboardEvent, DashboardState>
    implements DashboardBloc {}

final _mockSummary = DashboardSummary(
  nextAppointment: NextAppointment(
    id: 'apt-001',
    providerName: 'Dr Martin',
    startsAt: DateTime.utc(2026, 7, 10, 9, 30),
    motif: 'Pose prothèse',
  ),
  toSign: const [ToSignItem(quoteId: 'q-001', label: 'Devis implant #1')],
  toPay: const [
    ToPayItem(milestoneId: 'm-002', label: 'Pose prothèse', amountCents: 87500),
  ],
  unreadMessages: 2,
  questionnairesTodo: const [
    QuestionnaireTodo(id: 'qs-001', title: 'Questionnaire médical'),
  ],
  reminders: const [ReminderItem(id: 'r-001', label: 'Apporter carte Vitale')],
);

Widget _wrap(DashboardBloc bloc) {
  return MaterialApp(
    theme: NubiaTheme.light,
    home: BlocProvider<DashboardBloc>.value(
      value: bloc,
      child: const DashboardScreen(),
    ),
  );
}

void main() {
  late MockDashboardBloc mockBloc;

  setUp(() {
    mockBloc = MockDashboardBloc();
  });

  group('DashboardScreen', () {
    testWidgets('renders without throwing', (tester) async {
      when(() => mockBloc.state).thenReturn(DashboardLoaded(_mockSummary));
      await tester.pumpWidget(_wrap(mockBloc));
      expect(find.byType(DashboardScreen), findsOneWidget);
    });

    testWidgets('shows loading indicator on DashboardLoading', (tester) async {
      when(() => mockBloc.state).thenReturn(const DashboardLoading());
      await tester.pumpWidget(_wrap(mockBloc));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows all five tiles when loaded', (tester) async {
      when(() => mockBloc.state).thenReturn(DashboardLoaded(_mockSummary));
      await tester.pumpWidget(_wrap(mockBloc));
      expect(find.byType(DashboardTile), findsNWidgets(5));
    });

    testWidgets('shows unread message count badge', (tester) async {
      when(() => mockBloc.state).thenReturn(DashboardLoaded(_mockSummary));
      await tester.pumpWidget(_wrap(mockBloc));
      // Badge "2" for unread messages
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('shows error view with retry button on DashboardError',
        (tester) async {
      when(() => mockBloc.state)
          .thenReturn(const DashboardError('Erreur réseau'));
      await tester.pumpWidget(_wrap(mockBloc));
      expect(find.text('Erreur réseau'), findsOneWidget);
      expect(find.text('Réessayer'), findsOneWidget);
    });

    testWidgets('retry button dispatches DashboardLoadRequested', (tester) async {
      when(() => mockBloc.state)
          .thenReturn(const DashboardError('Erreur réseau'));
      await tester.pumpWidget(_wrap(mockBloc));
      await tester.tap(find.text('Réessayer'));
      await tester.pump();
      verify(() => mockBloc.add(const DashboardLoadRequested())).called(1);
    });
  });

  group('DashboardBody', () {
    testWidgets('renders without throwing', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: NubiaTheme.light,
          home: Scaffold(
            body: DashboardBody(
              summary: _mockSummary,
              onRefresh: () async {},
              onAppointmentTap: () {},
              onDocumentsTap: () {},
              onPaymentsTap: () {},
              onMessagesTap: () {},
              onRemindersTap: () {},
            ),
          ),
        ),
      );
      expect(find.byType(DashboardBody), findsOneWidget);
    });

    testWidgets('shows provider name in appointment tile', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: NubiaTheme.light,
          home: Scaffold(
            body: DashboardBody(
              summary: _mockSummary,
              onRefresh: () async {},
              onAppointmentTap: () {},
              onDocumentsTap: () {},
              onPaymentsTap: () {},
              onMessagesTap: () {},
              onRemindersTap: () {},
            ),
          ),
        ),
      );
      expect(find.textContaining('Dr Martin'), findsOneWidget);
    });
  });

  group('DashboardTile', () {
    testWidgets('renders without throwing', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: NubiaTheme.light,
          home: Scaffold(
            body: DashboardTile(
              icon: Icons.calendar_today_outlined,
              title: 'Test',
              onTap: () {},
            ),
          ),
        ),
      );
      expect(find.byType(DashboardTile), findsOneWidget);
    });

    testWidgets('shows count badge when count > 0', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: NubiaTheme.light,
          home: Scaffold(
            body: DashboardTile(
              icon: Icons.message_outlined,
              title: 'Messages',
              count: 3,
              onTap: () {},
            ),
          ),
        ),
      );
      expect(find.text('3'), findsOneWidget);
    });
  });
}
