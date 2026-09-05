import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_practicien/features/agenda/agenda_bloc.dart';
import 'package:app_practicien/features/agenda/agenda_event.dart';
import 'package:app_practicien/features/agenda/agenda_state.dart';
import 'package:app_practicien/features/dashboard/dashboard_bloc.dart';
import 'package:app_practicien/features/dashboard/dashboard_event.dart';
import 'package:app_practicien/features/dashboard/dashboard_page.dart';
import 'package:app_practicien/features/dashboard/dashboard_state.dart';
import 'package:app_practicien/features/dashboard/next_patient_hero.dart';
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

class MockStartConsultationUseCase extends Mock
    implements StartConsultationUseCase {}

class MockTodayNotesBloc extends MockBloc<TodayNotesEvent, TodayNotesState>
    implements TodayNotesBloc {}

class MockAgendaBloc extends MockBloc<AgendaEvent, AgendaState>
    implements AgendaBloc {}

class MockDashboardBloc extends MockBloc<DashboardEvent, DashboardState>
    implements DashboardBloc {}

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

final _nextPatientSummary = ProDashboardSummary(
  todayAppointments: 9,
  waitingRoomCount: 1,
  unreadMessages: 0,
  pendingConfirmations: 0,
  weeklyCompletedActs: 0,
  weeklyFeesCents: 0,
  weeklyNoShowCount: 0,
  nextPatientName: 'Camille Moreau',
  nextPatientReason: 'Pose de couronne',
  nextPatientAppointmentTime: DateTime(2026, 8, 26, 14, 30),
  nextPatientDurationMinutes: 30,
  nextPatientWaitingMinutes: 12,
  nextPatientAppointmentId: 'appt-1',
  nextPatientPatientId: 'pat-1',
  nextPatientAllergyLabel: 'Allergie pénicilline',
  nextPatientTreatmentPlanCents: 163592,
  nextPatientLastVisitAt: DateTime(2026, 7, 22),
);

const _session = ClinicalSession(
  id: 'sess-1',
  appointmentId: 'appt-1',
  status: 'in_progress',
  acts: [],
);

DashboardBloc _makeBloc(
  MockGetProDashboardSummaryUseCase uc, {
  MockStartConsultationUseCase? startConsultation,
}) =>
    DashboardBloc(
      getSummary: uc,
      startConsultation: startConsultation ?? MockStartConsultationUseCase(),
    );

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

    group('DashboardConsultationStartRequested (#6241)', () {
      late MockStartConsultationUseCase mockStart;

      setUp(() {
        mockStart = MockStartConsultationUseCase();
      });

      blocTest<DashboardBloc, DashboardState>(
        'démarre la séance du RDV ciblé et propage startedConsultationId',
        build: () {
          when(() => mockUc())
              .thenAnswer((_) async => Right(_nextPatientSummary));
          when(() => mockStart('appt-1'))
              .thenAnswer((_) async => const Right(_session));
          return _makeBloc(mockUc, startConsultation: mockStart);
        },
        act: (bloc) async {
          bloc.add(const DashboardLoadRequested());
          await Future<void>.delayed(Duration.zero);
          bloc.add(const DashboardConsultationStartRequested(
              appointmentId: 'appt-1'));
        },
        skip: 2, // Loading puis Loaded(summary) déjà couverts ci-dessus.
        expect: () => [
          DashboardLoaded(_nextPatientSummary, actionInProgress: true),
          DashboardLoaded(_nextPatientSummary, startedConsultationId: 'sess-1'),
        ],
        verify: (_) => verify(() => mockStart('appt-1')).called(1),
      );

      blocTest<DashboardBloc, DashboardState>(
        'expose actionError quand le démarrage échoue',
        build: () {
          when(() => mockUc())
              .thenAnswer((_) async => Right(_nextPatientSummary));
          when(() => mockStart('appt-1')).thenAnswer(
            (_) async =>
                const Left(ServerFailure(message: 'RDV déjà démarré')),
          );
          return _makeBloc(mockUc, startConsultation: mockStart);
        },
        act: (bloc) async {
          bloc.add(const DashboardLoadRequested());
          await Future<void>.delayed(Duration.zero);
          bloc.add(const DashboardConsultationStartRequested(
              appointmentId: 'appt-1'));
        },
        skip: 2,
        expect: () => [
          DashboardLoaded(_nextPatientSummary, actionInProgress: true),
          DashboardLoaded(_nextPatientSummary, actionError: 'RDV déjà démarré'),
        ],
      );

      blocTest<DashboardBloc, DashboardState>(
        'DashboardStartedConsultationConsumed remet startedConsultationId à '
        'null',
        build: () => _makeBloc(mockUc, startConsultation: mockStart),
        seed: () => DashboardLoaded(
          _nextPatientSummary,
          startedConsultationId: 'sess-1',
        ),
        act: (bloc) =>
            bloc.add(const DashboardStartedConsultationConsumed()),
        expect: () => [
          DashboardLoaded(_nextPatientSummary),
        ],
      );
    });
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

    // Instant ÉPINGLÉ. Ces tests construisent leurs RDV en décalage relatif
    // (-90 min … +120 min) et la carte filtre « aujourd'hui » sur la DATE de
    // calendrier : ancrés sur DateTime.now(), les RDV à +90/+120 min basculaient
    // sur le lendemain dès que la suite tournait à moins de deux heures de
    // minuit, et le badge affichait « 3 RDV » au lieu de « 4 RDV ». La CI virait
    // au rouge entre ~23h30 et ~01h30 selon l'heure de passage, sur des PR qui
    // ne touchaient pas le tableau de bord. Un midi fixe garde toutes les
    // entrées dans la même journée, quelle que soit l'heure d'exécution.
    final pinnedNow = DateTime(2026, 3, 17, 12, 0);

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
              child: TodayScheduleCard(
                summary: summary,
                clock: () => pinnedNow,
              ),
            ),
          ),
        );

    testWidgets(
        'déroule les RDV du jour triés par heure avec le badge total/restants',
        (tester) async {
      final now = pinnedNow;
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
      expect(find.byKey(const Key('today_schedule_row_soon')), findsOneWidget);
      expect(find.byKey(const Key('today_schedule_row_later')), findsOneWidget);
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
      final now = pinnedNow;
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

    testWidgets(
        'dérive le pill de statut depuis AgendaEntry, pas une chaîne libre',
        (tester) async {
      final now = pinnedNow;
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

    testWidgets(
        'exclut un RDV annulé (ou absent) du compteur restants et de la liste (#6040)',
        (tester) async {
      final now = pinnedNow;
      final entries = [
        entry(
          id: 'confirmed',
          startsAt: now.add(const Duration(minutes: 30)),
          endsAt: now.add(const Duration(minutes: 60)),
          status: 'confirmed',
        ),
        entry(
          id: 'cancelled',
          startsAt: now.add(const Duration(minutes: 90)),
          endsAt: now.add(const Duration(minutes: 120)),
          status: 'cancelled',
        ),
        entry(
          id: 'no-show',
          startsAt: now.add(const Duration(minutes: 150)),
          endsAt: now.add(const Duration(minutes: 180)),
          status: 'no_show',
        ),
      ];
      when(() => mockBloc.state)
          .thenReturn(AgendaLoaded(entries: entries, weekStart: now));

      const summary = ProDashboardSummary(
        todayAppointments: 3,
        waitingRoomCount: 0,
        unreadMessages: 0,
        pendingConfirmations: 0,
        weeklyCompletedActs: 0,
        weeklyFeesCents: 0,
        weeklyNoShowCount: 0,
      );
      await tester.pumpWidget(wrapCard(summary));

      expect(find.text('3 RDV · 1 restants'), findsOneWidget);
      expect(
          find.byKey(const Key('today_schedule_row_confirmed')),
          findsOneWidget);
      expect(
          find.byKey(const Key('today_schedule_row_cancelled')), findsNothing);
      expect(
          find.byKey(const Key('today_schedule_row_no-show')), findsNothing);
    });

    testWidgets('affiche un état vide DS quand aucun RDV aujourd\'hui',
        (tester) async {
      when(() => mockBloc.state).thenReturn(
        AgendaLoaded(entries: const [], weekStart: pinnedNow),
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

  // ---------------------------------------------------------------------------
  // NextPatientHero widget (#5045 — le patient suivant devient le héros)
  // ---------------------------------------------------------------------------

  group('NextPatientHero widget', () {
    Widget wrapCard(ProDashboardSummary summary) => MaterialApp(
          theme: NubiaTheme.light,
          home: Scaffold(body: NextPatientHero(summary: summary)),
        );

    testWidgets('masque le hero quand personne n\'attend', (tester) async {
      await tester.pumpWidget(wrapCard(_summary));

      expect(find.byKey(const Key('next_patient_hero')), findsNothing);
      expect(find.byKey(const Key('next_patient_hero_empty')), findsOneWidget);
    });

    testWidgets(
        'affiche nom, motif, heure, durée et temps d\'attente du prochain '
        'patient', (tester) async {
      await tester.pumpWidget(wrapCard(_nextPatientSummary));

      expect(find.byKey(const Key('next_patient_hero')), findsOneWidget);
      expect(find.text('Camille Moreau'), findsOneWidget);
      expect(find.text('Pose de couronne'), findsOneWidget);
      expect(find.text('14:30'), findsOneWidget);
      expect(find.text('30 min prévues'), findsOneWidget);
      expect(
        find.text('Patient suivant · en salle d\'attente depuis 12 min'),
        findsOneWidget,
      );
    });

    testWidgets(
        'le tag allergie utilise la variante danger et le plan un montant '
        'formaté', (tester) async {
      await tester.pumpWidget(wrapCard(_nextPatientSummary));

      final allergyPill = tester.widget<StatusPill>(
        find.byKey(const Key('next_patient_hero_allergy_tag')),
      );
      expect(allergyPill.variant, StatusPillVariant.error);
      expect(allergyPill.label, 'Allergie pénicilline');

      expect(find.text('Plan en cours · 1 635,92 €'), findsOneWidget);
      expect(find.text('Dernière visite 22/07'), findsOneWidget);
    });

    testWidgets('masque les tags absents sans planter sur des champs nuls',
        (tester) async {
      const partial = ProDashboardSummary(
        todayAppointments: 0,
        waitingRoomCount: 1,
        unreadMessages: 0,
        pendingConfirmations: 0,
        weeklyCompletedActs: 0,
        weeklyFeesCents: 0,
        weeklyNoShowCount: 0,
        nextPatientName: 'Camille Moreau',
      );
      await tester.pumpWidget(wrapCard(partial));

      expect(find.byKey(const Key('next_patient_hero')), findsOneWidget);
      expect(find.byType(StatusPill), findsNothing);
    });

    testWidgets(
        'démarrer la consultation envoie DashboardConsultationStartRequested '
        'avec l\'id du RDV en attente, pas une navigation à l\'aveugle '
        '(#6241)', (tester) async {
      final mockBloc = MockDashboardBloc();
      when(() => mockBloc.state)
          .thenReturn(DashboardLoaded(_nextPatientSummary));

      await tester.pumpWidget(
        MaterialApp(
          theme: NubiaTheme.light,
          home: Scaffold(
            body: BlocProvider<DashboardBloc>.value(
              value: mockBloc,
              child: NextPatientHero(summary: _nextPatientSummary),
            ),
          ),
        ),
      );

      await tester
          .tap(find.byKey(const Key('next_patient_hero_start_consultation')));

      verify(
        () => mockBloc.add(
          const DashboardConsultationStartRequested(appointmentId: 'appt-1'),
        ),
      ).called(1);
    });

    testWidgets(
        'ouvrir le dossier navigue vers la fiche du patient en attente, pas '
        'l\'annuaire complet (#6241)', (tester) async {
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, __) => Scaffold(
              body: NextPatientHero(summary: _nextPatientSummary),
            ),
          ),
          GoRoute(
            path: '/patients/:id',
            builder: (_, state) => Scaffold(
              body: Text('fiche patient ${state.pathParameters['id']}'),
            ),
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp.router(theme: NubiaTheme.light, routerConfig: router),
      );

      await tester.tap(find.byKey(const Key('next_patient_hero_open_file')));
      await tester.pumpAndSettle();

      expect(find.text('fiche patient pat-1'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // DashboardBody — bout-en-bout hero -> start -> navigation (#6241)
  // ---------------------------------------------------------------------------

  group('DashboardBody — démarrer la consultation depuis le hero (#6241)', () {
    late MockGetProDashboardSummaryUseCase mockUc;
    late MockStartConsultationUseCase mockStart;

    setUp(() {
      mockUc = MockGetProDashboardSummaryUseCase();
      mockStart = MockStartConsultationUseCase();
      GetIt.instance.registerFactory<DashboardBloc>(
        () => DashboardBloc(getSummary: mockUc, startConsultation: mockStart),
      );
      // DashboardBody rend aussi TodayScheduleCard/TodayNotesCard, qui
      // résolvent leur propre bloc via GetIt — sans stub, GetIt lève faute
      // d'enregistrement dès que ces cartes se construisent.
      final agendaBloc = MockAgendaBloc();
      when(() => agendaBloc.state).thenReturn(
        AgendaLoaded(entries: const [], weekStart: DateTime.now()),
      );
      GetIt.instance.registerFactory<AgendaBloc>(() => agendaBloc);
      final notesBloc = MockTodayNotesBloc();
      when(() => notesBloc.state).thenReturn(const TodayNotesLoaded([]));
      GetIt.instance.registerFactory<TodayNotesBloc>(() => notesBloc);
      addTearDown(GetIt.instance.reset);
    });

    testWidgets(
        'ouvre la séance réellement démarrée au fauteuil, au lieu de la '
        'liste historique des consultations', (tester) async {
      when(() => mockUc())
          .thenAnswer((_) async => Right(_nextPatientSummary));
      when(() => mockStart('appt-1'))
          .thenAnswer((_) async => const Right(_session));

      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(path: '/', builder: (_, __) => const DashboardBody()),
          GoRoute(
            path: '/consultation',
            builder: (_, state) => Scaffold(
              body: Text(
                'consultation démarrée id=${state.uri.queryParameters['id']}',
              ),
            ),
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp.router(theme: NubiaTheme.light, routerConfig: router),
      );
      await tester.pumpAndSettle();

      await tester
          .tap(find.byKey(const Key('next_patient_hero_start_consultation')));
      await tester.pumpAndSettle();

      expect(find.text('consultation démarrée id=sess-1'), findsOneWidget);
    });
  });
}
