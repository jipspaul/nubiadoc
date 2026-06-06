import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_demo/features/appointments/bloc/appointment_bloc.dart';
import 'package:flutter_demo/features/appointments/bloc/appointment_event.dart';
import 'package:flutter_demo/features/appointments/bloc/appointment_state.dart';
import 'package:flutter_demo/features/dashboard/bloc/dashboard_bloc.dart';
import 'package:flutter_demo/features/dashboard/bloc/dashboard_event.dart';
import 'package:flutter_demo/features/dashboard/bloc/dashboard_state.dart';
import 'package:flutter_demo/features/dashboard/dashboard_screen.dart';
import 'package:flutter_demo/features/dashboard/models/dashboard_summary.dart';
import 'package:flutter_demo/features/dashboard/widgets/dashboard_tile.dart';
import 'package:flutter_demo/widgets/nubia_avatar.dart';
import 'package:flutter_demo/widgets/nubia_badge.dart';
import 'package:flutter_demo/theme/nubia_theme.dart';

class MockDashboardBloc
    extends MockBloc<DashboardEvent, DashboardState>
    implements DashboardBloc {}

class MockAppointmentBloc
    extends MockBloc<AppointmentEvent, AppointmentState>
    implements AppointmentBloc {}

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
  unreadMessages: 3,
  questionnairesTodo: const [
    QuestionnaireTodo(id: 'qs-001', title: 'Questionnaire médical'),
    QuestionnaireTodo(id: 'qs-002', title: 'Questionnaire douleur'),
  ],
  reminders: const [ReminderItem(id: 'r-001', label: 'Apporter carte Vitale')],
);

Widget _wrap(DashboardBloc bloc, AppointmentBloc aptBloc) {
  return MaterialApp(
    theme: NubiaTheme.light,
    home: MultiBlocProvider(
      providers: [
        BlocProvider<DashboardBloc>.value(value: bloc),
        BlocProvider<AppointmentBloc>.value(value: aptBloc),
      ],
      child: const DashboardScreen(),
    ),
  );
}

void main() {
  late MockDashboardBloc mockBloc;
  late MockAppointmentBloc mockAptBloc;

  setUp(() {
    mockBloc = MockDashboardBloc();
    mockAptBloc = MockAppointmentBloc();
  });

  group('DashboardScreen (screens path)', () {
    testWidgets('renders without throwing', (tester) async {
      when(() => mockBloc.state).thenReturn(DashboardLoaded(_mockSummary));
      await tester.pumpWidget(_wrap(mockBloc, mockAptBloc));
      expect(find.byType(DashboardScreen), findsOneWidget);
    });

    testWidgets('shows 6 tiles when loaded', (tester) async {
      when(() => mockBloc.state).thenReturn(DashboardLoaded(_mockSummary));
      await tester.pumpWidget(_wrap(mockBloc, mockAptBloc));
      expect(find.byType(DashboardTile), findsNWidgets(6));
    });

    testWidgets('NubiaAvatar with initials MD is visible in AppBar',
        (tester) async {
      when(() => mockBloc.state).thenReturn(DashboardLoaded(_mockSummary));
      await tester.pumpWidget(_wrap(mockBloc, mockAptBloc));
      expect(find.byType(NubiaAvatar), findsOneWidget);
      expect(find.text('MD'), findsOneWidget);
    });

    testWidgets('NubiaBadge counter visible on messages tile (count=3)',
        (tester) async {
      when(() => mockBloc.state).thenReturn(DashboardLoaded(_mockSummary));
      await tester.pumpWidget(_wrap(mockBloc, mockAptBloc));
      expect(find.byType(NubiaBadge), isNot(findsNothing));
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('NubiaBadge counter visible on questionnaires tile (count=2)',
        (tester) async {
      when(() => mockBloc.state).thenReturn(DashboardLoaded(_mockSummary));
      await tester.pumpWidget(_wrap(mockBloc, mockAptBloc));
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('tap on Questionnaires tile does not throw', (tester) async {
      when(() => mockBloc.state).thenReturn(DashboardLoaded(_mockSummary));
      await tester.pumpWidget(_wrap(mockBloc, mockAptBloc));
      await tester.tap(find.byKey(const Key('dashboard_tile_Questionnaires')));
      await tester.pump();
      // Navigation via SnackBar placeholder — no exception expected
    });

    testWidgets('tap on À signer tile does not throw', (tester) async {
      when(() => mockBloc.state).thenReturn(DashboardLoaded(_mockSummary));
      await tester.pumpWidget(_wrap(mockBloc, mockAptBloc));
      await tester.tap(find.byKey(const Key('dashboard_tile_À signer')));
      await tester.pump();
    });
  });
}
