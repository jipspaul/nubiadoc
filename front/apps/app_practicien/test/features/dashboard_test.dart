import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_practicien/features/dashboard/dashboard_bloc.dart';
import 'package:app_practicien/features/dashboard/dashboard_event.dart';
import 'package:app_practicien/features/dashboard/dashboard_state.dart';
import 'package:app_practicien/features/dashboard/today_notes_bloc.dart';
import 'package:app_practicien/features/dashboard/today_notes_card.dart';
import 'package:app_practicien/features/dashboard/week_summary_card.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockGetProDashboardSummaryUseCase extends Mock
    implements GetProDashboardSummaryUseCase {}

class MockTodayNotesBloc extends MockBloc<TodayNotesEvent, TodayNotesState>
    implements TodayNotesBloc {}

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
        ),
        ClinicalNoteSummary(
          id: 'n2',
          timestamp: DateTime(2026, 6, 3, 10, 30),
          patientInitials: 'CR',
          status: ClinicalNoteStatus.draft,
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
}
