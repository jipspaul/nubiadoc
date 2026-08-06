import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_patient/features/dashboard/dashboard_bloc.dart';
import 'package:app_patient/features/dashboard/dashboard_event.dart';
import 'package:app_patient/features/dashboard/dashboard_state.dart';
import 'package:app_patient/features/messaging/messaging_bloc.dart';
import 'package:app_patient/features/messaging/messaging_event.dart';
import 'package:app_patient/features/messaging/messaging_state.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockGetDashboardSummaryUseCase extends Mock
    implements GetDashboardSummaryUseCase {}

class _MockDashboardBloc extends MockBloc<DashboardEvent, DashboardState>
    implements DashboardBloc {}

class _MockMessagingBloc extends MockBloc<MessagingEvent, MessagingState>
    implements MessagingBloc {}

// ---------------------------------------------------------------------------
// Badge test widget — mirrors the BlocSelector + Badge.count from DashboardPage
// ---------------------------------------------------------------------------

class _BadgeOnMessagesTab extends StatelessWidget {
  const _BadgeOnMessagesTab();

  @override
  Widget build(BuildContext context) {
    return BlocSelector<MessagingBloc, MessagingState, int>(
      selector: (s) => s is MessagingConversationsLoaded
          ? s.conversations.fold(0, (acc, c) => acc + c.unreadCount)
          : 0,
      builder: (context, unreadCount) {
        return NavigationBar(
          selectedIndex: 0,
          onDestinationSelected: (_) {},
          destinations: [
            const NavigationDestination(
              icon: Icon(Icons.search),
              label: 'Rechercher',
            ),
            NavigationDestination(
              key: const Key('tab_messages'),
              icon: Badge.count(
                count: unreadCount,
                isLabelVisible: unreadCount > 0,
                child: const Icon(Icons.chat_bubble_outline),
              ),
              label: 'Messages',
            ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const _summary = DashboardSummary(
  upcomingAppointments: 2,
  documentsToSign: 0,
  pendingPaymentsCents: 0,
  unreadMessages: 1,
);

DashboardBloc _makeBloc(MockGetDashboardSummaryUseCase uc) =>
    DashboardBloc(getDashboardSummary: uc);

// ---------------------------------------------------------------------------
// Widget helper — tests the BlocBuilder logic without DashboardPage shell
// ---------------------------------------------------------------------------

class _DashboardBody extends StatelessWidget {
  const _DashboardBody();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DashboardBloc, DashboardState>(
      builder: (context, state) {
        if (state is DashboardError) {
          return NubiaErrorWidget(
            key: const Key('dashboard_error'),
            message: state.message,
            onRetry: () => context
                .read<DashboardBloc>()
                .add(const DashboardLoadRequested()),
          );
        }
        if (state is DashboardLoaded) {
          return Text(
            key: const Key('dashboard_loaded'),
            'RDV: ${state.summary.upcomingAppointments}',
          );
        }
        return const CircularProgressIndicator(key: Key('dashboard_loading'));
      },
    );
  }
}

Widget _wrap(DashboardBloc bloc) => MaterialApp(
      theme: NubiaTheme.light,
      home: BlocProvider<DashboardBloc>.value(
        value: bloc,
        child: const Scaffold(body: _DashboardBody()),
      ),
    );

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUpAll(() {
    registerFallbackValue(const DashboardLoadRequested());
  });

  late MockGetDashboardSummaryUseCase mockUc;

  setUp(() {
    mockUc = MockGetDashboardSummaryUseCase();
  });

  group('DashboardBloc', () {
    blocTest<DashboardBloc, DashboardState>(
      'émet [Loading, Loaded] quand getDashboardSummary réussit',
      build: () {
        when(() => mockUc()).thenAnswer((_) async => const Right(_summary));
        return _makeBloc(mockUc);
      },
      act: (bloc) => bloc.add(const DashboardLoadRequested()),
      expect: () => [
        const DashboardLoading(),
        isA<DashboardLoaded>().having(
          (s) => s.summary.upcomingAppointments,
          'upcomingAppointments',
          2,
        ),
      ],
    );

    blocTest<DashboardBloc, DashboardState>(
      'émet [Loading, Error] quand getDashboardSummary échoue',
      build: () {
        when(() => mockUc()).thenAnswer(
          (_) async => const Left(NetworkFailure('Erreur réseau.')),
        );
        return _makeBloc(mockUc);
      },
      act: (bloc) => bloc.add(const DashboardLoadRequested()),
      expect: () => [
        const DashboardLoading(),
        isA<DashboardError>()
            .having((s) => s.message, 'message', 'Erreur réseau.'),
      ],
    );
  });

  group('DashboardPage widget', () {
    testWidgets('affiche NubiaErrorWidget en état DashboardError',
        (tester) async {
      when(() => mockUc()).thenAnswer(
        (_) async => const Left(NetworkFailure('Erreur réseau.')),
      );
      final bloc = _makeBloc(mockUc)..add(const DashboardLoadRequested());

      await tester.pumpWidget(_wrap(bloc));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('dashboard_error')), findsOneWidget);
      expect(find.text('Erreur réseau.'), findsOneWidget);
      expect(find.text('Réessayer'), findsOneWidget);
    });

    testWidgets('tap Réessayer dispatch DashboardLoadRequested',
        (tester) async {
      final mockBloc = _MockDashboardBloc();
      when(() => mockBloc.state)
          .thenReturn(const DashboardError('Erreur réseau.'));
      when(() => mockBloc.stream).thenAnswer((_) => const Stream.empty());

      await tester.pumpWidget(_wrap(mockBloc));

      await tester.tap(find.text('Réessayer'));

      verify(() => mockBloc.add(const DashboardLoadRequested())).called(1);
    });
  });

  group('badge unread messaging', () {
    testWidgets('badge affiche "3" quand unreadCount total = 3',
        (tester) async {
      final msgBloc = _MockMessagingBloc();
      when(() => msgBloc.state).thenReturn(
        MessagingConversationsLoaded([
          Conversation(
            id: 'c1',
            cabinetId: 'cab-1',
            cabinetName: 'Cabinet',
            unreadCount: 3,
          ),
        ]),
      );
      when(() => msgBloc.stream).thenAnswer((_) => const Stream.empty());

      await tester.pumpWidget(MaterialApp(
        home: BlocProvider<MessagingBloc>.value(
          value: msgBloc,
          child: const Scaffold(body: _BadgeOnMessagesTab()),
        ),
      ));

      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('badge invisible quand unreadCount = 0', (tester) async {
      final msgBloc = _MockMessagingBloc();
      when(() => msgBloc.state)
          .thenReturn(MessagingConversationsLoaded(const []));
      when(() => msgBloc.stream).thenAnswer((_) => const Stream.empty());

      await tester.pumpWidget(MaterialApp(
        home: BlocProvider<MessagingBloc>.value(
          value: msgBloc,
          child: const Scaffold(body: _BadgeOnMessagesTab()),
        ),
      ));

      expect(find.text('0'), findsNothing);
    });
  });
}
