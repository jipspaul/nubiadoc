import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_practicien/features/agenda/agenda_bloc.dart';
import 'package:app_practicien/features/agenda/agenda_event.dart';
import 'package:app_practicien/features/agenda/agenda_state.dart';
import 'package:app_practicien/features/dashboard/dashboard_bloc.dart';
import 'package:app_practicien/features/dashboard/dashboard_event.dart';
import 'package:app_practicien/features/dashboard/dashboard_state.dart';
import 'package:app_practicien/features/dashboard/pending_actions_card.dart';
import 'package:app_practicien/features/dashboard/today_notes_bloc.dart';
import 'package:app_practicien/features/dashboard/today_notes_card.dart';
import 'package:app_practicien/features/dashboard/today_schedule_card.dart';
import 'package:app_practicien/features/dashboard/week_summary_card.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockGetProDashboardSummaryUseCase extends Mock
    implements GetProDashboardSummaryUseCase {}

class MockTodayNotesBloc extends MockBloc<TodayNotesEvent, TodayNotesState>
    implements TodayNotesBloc {}

class MockAgendaBloc extends MockBloc<AgendaEvent, AgendaState>
    implements AgendaBloc {}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

final _summary = ProDashboardSummary(
  todayAppointments: 5,
  waitingRoomCount: 2,
  unreadMessages: 3,
  pendingConfirmations: 1,
  weeklyCompletedActs: 38,
  weeklyFeesCents: 642000,
  weeklyNoShowCount: 2,
);

DashboardBloc _makeBloc(MockGetProDashboardSummaryUseCase uc) =>
    DashboardBloc(getSummary: uc);

// ---------------------------------------------------------------------------
// Widget helper
// ---------------------------------------------------------------------------

Widget _wrap(DashboardBloc bloc, Widget child) => MaterialApp(
      home: BlocProvider.value(
        value: bloc,
        child: Scaffold(body: child),
      ),
    );

class _DashboardBody extends StatelessWidget {
  const _DashboardBody();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DashboardBloc, DashboardState>(
      builder: (context, state) {
        if (state is DashboardInitial || state is DashboardLoading) {
          return const Center(
            key: Key('dashboard_loading'),
            child: CircularProgressIndicator(),
          );
        }
        if (state is DashboardError) {
          return Center(
            key: const Key('dashboard_error'),
            child: Text(state.message),
          );
        }
        if (state is DashboardLoaded) {
          return Column(
            key: const Key('dashboard_loaded'),
            children: [
              Text('RDV: ${state.summary.todayAppointments}'),
              Text('Attente: ${state.summary.waitingRoomCount}'),
              Text('Messages: ${state.summary.unreadMessages}'),
              Text('Confirmations: ${state.summary.pendingConfirmations}'),
            ],
          );
        }
        return const SizedBox.shrink();
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Bloc tests
// ---------------------------------------------------------------------------

void main() {
  group('DashboardBloc', () {
    late MockGetProDashboardSummaryUseCase mockUc;

    setUp(() {
      mockUc = MockGetProDashboardSummaryUseCase();
    });

    blocTest<DashboardBloc, DashboardState>(
      'émet Loading puis Loaded avec le résumé',
      build: () {
        when(() => mockUc()).thenAnswer((_) async => Right(_summary));
        return _makeBloc(mockUc);
      },
      act: (bloc) => bloc.add(const DashboardLoadRequested()),
      expect: () => [
        const DashboardLoading(),
        DashboardLoaded(_summary),
      ],
    );

    blocTest<DashboardBloc, DashboardState>(
      'émet Loading puis Error en cas d\'échec',
      build: () {
        when(() => mockUc()).thenAnswer(
          (_) async => const Left(ServerFailure(message: 'Erreur réseau')),
        );
        return _makeBloc(mockUc);
      },
      act: (bloc) => bloc.add(const DashboardLoadRequested()),
      expect: () => [
        const DashboardLoading(),
        const DashboardError('Erreur réseau'),
      ],
    );
  });

  // ---------------------------------------------------------------------------
  // Widget tests
  // ---------------------------------------------------------------------------

  group('DashboardPage widget', () {
    late MockGetProDashboardSummaryUseCase mockUc;

    setUp(() {
      mockUc = MockGetProDashboardSummaryUseCase();
    });

    testWidgets('affiche le chargement en état Loading', (tester) async {
      final bloc = _makeBloc(mockUc);
      await tester.pumpWidget(_wrap(bloc, const _DashboardBody()));
      expect(find.byKey(const Key('dashboard_loading')), findsOneWidget);
    });

    testWidgets('affiche les statistiques en état Loaded', (tester) async {
      when(() => mockUc()).thenAnswer((_) async => Right(_summary));
      final bloc = _makeBloc(mockUc)..add(const DashboardLoadRequested());
      await tester.pumpWidget(_wrap(bloc, const _DashboardBody()));
      await tester.pump();
      expect(find.byKey(const Key('dashboard_loaded')), findsOneWidget);
      expect(find.text('RDV: 5'), findsOneWidget);
      expect(find.text('Attente: 2'), findsOneWidget);
      expect(find.text('Messages: 3'), findsOneWidget);
    });

    testWidgets('affiche une erreur en état Error', (tester) async {
      when(() => mockUc()).thenAnswer(
        (_) async => const Left(ServerFailure(message: 'Erreur')),
      );
      final bloc = _makeBloc(mockUc)..add(const DashboardLoadRequested());
      await tester.pumpWidget(_wrap(bloc, const _DashboardBody()));
      await tester.pump();
      expect(find.byKey(const Key('dashboard_error')), findsOneWidget);
      expect(find.text('Erreur'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // TodayNotesCard widget (composants DS)
  // ---------------------------------------------------------------------------

  group('TodayNotesCard widget', () {
    late MockTodayNotesBloc mockBloc;

    setUp(() {
      mockBloc = MockTodayNotesBloc();
    });

    Widget wrapNotes() => MaterialApp(
          theme: NubiaTheme.light,
          home: Scaffold(
            body: BlocProvider<TodayNotesBloc>.value(
              value: mockBloc,
              child: const TodayNotesCard(),
            ),
          ),
        );

    testWidgets('affiche un état vide DS quand aucune note', (tester) async {
      when(() => mockBloc.state).thenReturn(const TodayNotesLoaded([]));
      await tester.pumpWidget(wrapNotes());

      expect(find.byKey(const Key('today_notes_card')), findsOneWidget);
      expect(find.byKey(const Key('today_notes_empty')), findsOneWidget);
      expect(find.byType(NubiaEmptyState), findsOneWidget);
    });

    testWidgets('affiche les notes via ListRow + StatusPill', (tester) async {
      final entries = [
        ClinicalNoteSummary(
          id: 'n1',
          timestamp: DateTime(2026, 6, 3, 9, 5),
          patientInitials: 'MD',
          status: ClinicalNoteStatus.signed,
          patientName: 'MD',
        ),
        ClinicalNoteSummary(
          id: 'n2',
          timestamp: DateTime(2026, 6, 3, 10, 30),
          patientInitials: 'CR',
          status: ClinicalNoteStatus.draft,
          patientName: 'CR',
        ),
      ];
      when(() => mockBloc.state).thenReturn(TodayNotesLoaded(entries));
      await tester.pumpWidget(wrapNotes());

      expect(find.byKey(const Key('today_note_n1')), findsOneWidget);
      expect(find.byKey(const Key('today_note_n2')), findsOneWidget);
      expect(find.byType(ListRow), findsNWidgets(2));
      expect(find.byType(StatusPill), findsNWidgets(2));
      expect(find.byType(NubiaAvatar), findsNWidgets(2));
      expect(find.text('09:05'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // WeekSummaryCard widget (composants DS)
  // ---------------------------------------------------------------------------

  group('WeekSummaryCard widget', () {
    Widget wrapCard(ProDashboardSummary summary) => MaterialApp(
          theme: NubiaTheme.light,
          home: Scaffold(
            body: WeekSummaryCard(summary: summary),
          ),
        );

    testWidgets('affiche les 3 chiffres hebdomadaires via ListRow + StatusPill',
        (tester) async {
      await tester.pumpWidget(wrapCard(_summary));

      expect(find.byKey(const Key('week_summary_card')), findsOneWidget);
      expect(find.text('Cette semaine'), findsOneWidget);
      expect(find.byKey(const Key('week_summary_acts_row')), findsOneWidget);
      expect(find.byKey(const Key('week_summary_fees_row')), findsOneWidget);
      expect(find.byKey(const Key('week_summary_no_show_row')), findsOneWidget);
      expect(find.text('Actes réalisés'), findsOneWidget);
      expect(find.text('38'), findsOneWidget);
      expect(find.text('Rendez-vous non honorés'), findsOneWidget);
      expect(find.text('2 patient(s) concerné(s)'), findsOneWidget);
      expect(find.byType(ListRow), findsNWidgets(3));
      expect(find.byType(StatusPill), findsNWidgets(3));
    });

    testWidgets('formate les honoraires (milliers + €)', (tester) async {
      await tester.pumpWidget(wrapCard(_summary));

      expect(find.text('6 420 €'), findsOneWidget);
    });

    testWidgets('la pastille RDV non honorés utilise la variante warning',
        (tester) async {
      await tester.pumpWidget(wrapCard(_summary));

      final pill = tester.widget<StatusPill>(
        find.descendant(
          of: find.byKey(const Key('week_summary_no_show_row')),
          matching: find.byType(StatusPill),
        ),
      );
      expect(pill.variant, StatusPillVariant.warning);
    });
  });

  // ---------------------------------------------------------------------------
  // TodayScheduleCard widget (#5046 — la journée en clair, pas en compteur)
  // ---------------------------------------------------------------------------

  group('TodayScheduleCard widget', () {
    late MockAgendaBloc mockBloc;

    setUp(() {
      mockBloc = MockAgendaBloc();
    });

    AgendaEntry entry({
      required String id,
      required DateTime startsAt,
      required DateTime endsAt,
      required String status,
    }) =>
        AgendaEntry(
          id: id,
          cabinetId: 'cab-1',
          practitionerId: 'prac-1',
          practitionerName: 'Dr. Dupont',
          startsAt: startsAt,
          endsAt: endsAt,
          patientId: 'pat-$id',
          patientName: 'Louis Mercier',
          motif: 'Détartrage',
          isFree: false,
          status: status,
        );

    Widget wrapCard(ProDashboardSummary summary) => MaterialApp(
          theme: NubiaTheme.light,
          home: Scaffold(
            body: BlocProvider<AgendaBloc>.value(
              value: mockBloc,
              child: TodayScheduleCard(summary: summary),
            ),
          ),
        );

    testWidgets(
        'déroule les RDV du jour triés par heure avec le badge total/restants',
        (tester) async {
      final now = DateTime.now();
      final entries = [
        entry(
          id: 'past',
          startsAt: now.subtract(const Duration(minutes: 90)),
          endsAt: now.subtract(const Duration(minutes: 60)),
          status: 'done',
        ),
        entry(
          id: 'now',
          startsAt: now.subtract(const Duration(minutes: 10)),
          endsAt: now.add(const Duration(minutes: 20)),
          status: 'checked_in',
        ),
        entry(
          id: 'soon',
          startsAt: now.add(const Duration(minutes: 30)),
          endsAt: now.add(const Duration(minutes: 60)),
          status: 'confirmed',
        ),
        entry(
          id: 'later',
          startsAt: now.add(const Duration(minutes: 90)),
          endsAt: now.add(const Duration(minutes: 120)),
          status: 'requested',
        ),
      ];
      final state = AgendaLoaded(entries: entries, weekStart: now);
      when(() => mockBloc.state).thenReturn(state);

      const summary = ProDashboardSummary(
        todayAppointments: 4,
        waitingRoomCount: 0,
        unreadMessages: 0,
        pendingConfirmations: 0,
        weeklyCompletedActs: 0,
        weeklyFeesCents: 0,
        weeklyNoShowCount: 0,
      );
      await tester.pumpWidget(wrapCard(summary));

      expect(find.byKey(const Key('today_schedule_card')), findsOneWidget);
      expect(find.text('Journée'), findsOneWidget);
      expect(find.text('4 RDV · 3 restants'), findsOneWidget);
      expect(find.byKey(const Key('today_schedule_row_past')), findsOneWidget);
      expect(find.byKey(const Key('today_schedule_row_now')), findsOneWidget);
      expect(
          find.byKey(const Key('today_schedule_row_soon')), findsOneWidget);
      expect(
          find.byKey(const Key('today_schedule_row_later')), findsOneWidget);
      expect(find.byType(ListRow), findsNWidgets(4));

      // Ordre : passé, courant, à venir, à venir plus tard.
      final rowFinder = find.byType(ListRow);
      final keys = tester
          .widgetList<ListRow>(rowFinder)
          .map((w) => (w.key as Key))
          .toList();
      expect(keys, [
        const Key('today_schedule_row_past'),
        const Key('today_schedule_row_now'),
        const Key('today_schedule_row_soon'),
        const Key('today_schedule_row_later'),
      ]);
    });

    testWidgets('estompe le RDV passé et teinte le RDV courant',
        (tester) async {
      final now = DateTime.now();
      final entries = [
        entry(
          id: 'past',
          startsAt: now.subtract(const Duration(minutes: 90)),
          endsAt: now.subtract(const Duration(minutes: 60)),
          status: 'done',
        ),
        entry(
          id: 'now',
          startsAt: now.subtract(const Duration(minutes: 10)),
          endsAt: now.add(const Duration(minutes: 20)),
          status: 'checked_in',
        ),
      ];
      when(() => mockBloc.state)
          .thenReturn(AgendaLoaded(entries: entries, weekStart: now));

      const summary = ProDashboardSummary(
        todayAppointments: 2,
        waitingRoomCount: 0,
        unreadMessages: 0,
        pendingConfirmations: 0,
        weeklyCompletedActs: 0,
        weeklyFeesCents: 0,
        weeklyNoShowCount: 0,
      );
      await tester.pumpWidget(wrapCard(summary));

      final pastOpacity = tester.widget<Opacity>(
        find.ancestor(
          of: find.byKey(const Key('today_schedule_row_past')),
          matching: find.byType(Opacity),
        ),
      );
      expect(pastOpacity.opacity, lessThan(1));

      final nowOpacity = tester.widget<Opacity>(
        find.ancestor(
          of: find.byKey(const Key('today_schedule_row_now')),
          matching: find.byType(Opacity),
        ),
      );
      expect(nowOpacity.opacity, 1);

      final nowContainer = tester.widget<Container>(
        find.ancestor(
          of: find.byKey(const Key('today_schedule_row_now')),
          matching: find.byType(Container),
        ),
      );
      expect(nowContainer.color, isNotNull);

      final pastContainer = tester.widget<Container>(
        find.ancestor(
          of: find.byKey(const Key('today_schedule_row_past')),
          matching: find.byType(Container),
        ),
      );
      expect(pastContainer.color, isNull);
    });

    testWidgets('dérive le pill de statut depuis AgendaEntry, pas une chaîne libre',
        (tester) async {
      final now = DateTime.now();
      final entries = [
        entry(
          id: 'done',
          startsAt: now.subtract(const Duration(minutes: 90)),
          endsAt: now.subtract(const Duration(minutes: 60)),
          status: 'done',
        ),
        entry(
          id: 'checked-in',
          startsAt: now.add(const Duration(minutes: 5)),
          endsAt: now.add(const Duration(minutes: 35)),
          status: 'checked_in',
        ),
        entry(
          id: 'confirmed',
          startsAt: now.add(const Duration(minutes: 40)),
          endsAt: now.add(const Duration(minutes: 70)),
          status: 'confirmed',
        ),
        entry(
          id: 'requested',
          startsAt: now.add(const Duration(minutes: 75)),
          endsAt: now.add(const Duration(minutes: 105)),
          status: 'requested',
        ),
      ];
      when(() => mockBloc.state)
          .thenReturn(AgendaLoaded(entries: entries, weekStart: now));

      const summary = ProDashboardSummary(
        todayAppointments: 4,
        waitingRoomCount: 0,
        unreadMessages: 0,
        pendingConfirmations: 0,
        weeklyCompletedActs: 0,
        weeklyFeesCents: 0,
        weeklyNoShowCount: 0,
      );
      await tester.pumpWidget(wrapCard(summary));

      StatusPill pillOf(String id) => tester.widget<StatusPill>(
            find.descendant(
              of: find.byKey(Key('today_schedule_row_$id')),
              matching: find.byType(StatusPill),
            ),
          );

      expect(pillOf('done').label, 'Terminé');
      expect(pillOf('done').variant, StatusPillVariant.success);
      expect(pillOf('checked-in').label, 'En attente');
      expect(pillOf('checked-in').variant, StatusPillVariant.info);
      expect(pillOf('confirmed').label, 'À venir');
      expect(pillOf('confirmed').variant, StatusPillVariant.neutral);
      expect(pillOf('requested').label, 'À confirmer');
      expect(pillOf('requested').variant, StatusPillVariant.warning);
    });

    testWidgets('affiche un état vide DS quand aucun RDV aujourd\'hui',
        (tester) async {
      when(() => mockBloc.state).thenReturn(
        AgendaLoaded(entries: const [], weekStart: DateTime.now()),
      );

      const summary = ProDashboardSummary(
        todayAppointments: 0,
        waitingRoomCount: 0,
        unreadMessages: 0,
        pendingConfirmations: 0,
        weeklyCompletedActs: 0,
        weeklyFeesCents: 0,
        weeklyNoShowCount: 0,
      );
      await tester.pumpWidget(wrapCard(summary));

      expect(find.byKey(const Key('today_schedule_empty')), findsOneWidget);
      expect(find.byType(NubiaEmptyState), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // PendingActionsCard widget (#5049 — file unique « À traiter »)
  // ---------------------------------------------------------------------------

  group('PendingActionsCard widget', () {
    Widget wrapCard(GoRouter router) =>
        MaterialApp.router(theme: NubiaTheme.light, routerConfig: router);

    GoRouter makeRouter(ProDashboardSummary summary) => GoRouter(
          initialLocation: '/',
          routes: [
            GoRoute(
              path: '/',
              builder: (_, __) =>
                  Scaffold(body: PendingActionsCard(summary: summary)),
            ),
            GoRoute(
              path: '/agenda',
              builder: (_, __) => const Scaffold(body: Text('agenda page')),
            ),
            GoRoute(
              path: '/messages',
              builder: (_, __) => const Scaffold(body: Text('messages page')),
            ),
          ],
        );

    testWidgets(
        'remplace les tuiles confirmations/messages par une file unique',
        (tester) async {
      final router = makeRouter(_summary);
      await tester.pumpWidget(wrapCard(router));

      expect(find.byKey(const Key('pending_actions_card')), findsOneWidget);
      expect(find.text('À traiter'), findsOneWidget);
      expect(find.byKey(const Key('metric_confirmations')), findsOneWidget);
      expect(find.byKey(const Key('metric_messages')), findsOneWidget);
      expect(find.text('Confirmations en attente'), findsOneWidget);
      expect(find.text('Messages non lus'), findsOneWidget);
      expect(find.byType(ListRow), findsNWidgets(2));
    });

    testWidgets('confirmations en attente navigue vers /agenda (#3374)',
        (tester) async {
      final router = makeRouter(_summary);
      await tester.pumpWidget(wrapCard(router));

      await tester.tap(find.byKey(const Key('metric_confirmations')));
      await tester.pumpAndSettle();

      expect(find.text('agenda page'), findsOneWidget);
    });

    testWidgets('messages non lus navigue vers /messages (#3374)',
        (tester) async {
      final router = makeRouter(_summary);
      await tester.pumpWidget(wrapCard(router));

      await tester.tap(find.byKey(const Key('metric_messages')));
      await tester.pumpAndSettle();

      expect(find.text('messages page'), findsOneWidget);
    });
  });
}
