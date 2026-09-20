import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_app_shell/nubia_app_shell.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_secretariat/features/dashboard/cash_collection_cubit.dart';
import 'package:app_secretariat/features/dashboard/compliance_alerts_summary_cubit.dart';
import 'package:app_secretariat/features/dashboard/dashboard_bloc.dart';
import 'package:app_secretariat/features/dashboard/dashboard_content.dart';
import 'package:app_secretariat/features/dashboard/dashboard_event.dart';
import 'package:app_secretariat/features/dashboard/dashboard_state.dart';
import 'package:app_secretariat/features/dashboard/expiring_quotes_summary_cubit.dart';
import 'package:app_secretariat/features/dashboard/patient_messages_summary_cubit.dart';
import 'package:app_secretariat/features/dashboard/waiting_room_summary_cubit.dart';
import 'package:app_secretariat/features/tasks/tasks_bloc.dart';
import 'package:app_secretariat/features/tasks/tasks_event.dart';
import 'package:app_secretariat/features/tasks/tasks_state.dart';
import 'package:app_secretariat/router/app_router.dart';

class _MockDashboardBloc extends MockBloc<DashboardEvent, DashboardState>
    implements DashboardBloc {}

class _MockCashCollectionCubit extends MockCubit<CashCollectionState>
    implements CashCollectionCubit {}

class _MockWaitingRoomSummaryCubit extends MockCubit<WaitingRoomSummaryState>
    implements WaitingRoomSummaryCubit {}

class _MockPatientMessagesSummaryCubit
    extends MockCubit<PatientMessagesSummaryState>
    implements PatientMessagesSummaryCubit {}

class _MockExpiringQuotesSummaryCubit
    extends MockCubit<ExpiringQuotesSummaryState>
    implements ExpiringQuotesSummaryCubit {}

class _MockOpportunitiesCubit extends MockCubit<OpportunitiesState>
    implements OpportunitiesCubit {}

class _MockComplianceAlertsSummaryCubit
    extends MockCubit<ComplianceAlertsSummaryState>
    implements ComplianceAlertsSummaryCubit {}

class _MockTasksBloc extends MockBloc<TasksEvent, TasksState>
    implements TasksBloc {}

const _session = AuthSession(
  kind: UserKind.pro,
  userId: 'user-1',
  role: ProRole.secretary,
);

void main() {
  late _MockDashboardBloc dashboardBloc;
  late _MockCashCollectionCubit cashCollectionCubit;
  late _MockWaitingRoomSummaryCubit waitingRoomSummaryCubit;
  late _MockPatientMessagesSummaryCubit patientMessagesSummaryCubit;
  late _MockExpiringQuotesSummaryCubit expiringQuotesSummaryCubit;
  late _MockOpportunitiesCubit opportunitiesCubit;
  late _MockComplianceAlertsSummaryCubit complianceAlertsSummaryCubit;
  late _MockTasksBloc tasksBloc;

  setUp(() {
    dashboardBloc = _MockDashboardBloc();
    when(() => dashboardBloc.state).thenReturn(
      const DashboardLoaded(todayCount: 0, pendingCount: 0, waitingCount: 0),
    );
    // États `Loaded` plutôt que `Loading` : les squelettes `Loading`
    // utilisent un shimmer en boucle infinie qui empêche `pumpAndSettle` de
    // jamais se stabiliser — hors de propos pour ce test de navigation.
    cashCollectionCubit = _MockCashCollectionCubit();
    when(() => cashCollectionCubit.state).thenReturn(
      const CashCollectionLoaded(
        summary: CashCollectionSummary(
          collectedTodayCents: 0,
          collectedTodayPaymentCount: 0,
          remainingTodayCents: 0,
          remainingTodayPatientCount: 0,
          closingHour: 19,
          unpaidCents: 0,
          unpaidPatientCount: 0,
        ),
      ),
    );
    waitingRoomSummaryCubit = _MockWaitingRoomSummaryCubit();
    when(() => waitingRoomSummaryCubit.state).thenReturn(
      const WaitingRoomSummaryLoaded(
        presentCount: 0,
        averageWaitMinutes: 0,
        longestWaitMinutes: 0,
      ),
    );
    patientMessagesSummaryCubit = _MockPatientMessagesSummaryCubit();
    when(() => patientMessagesSummaryCubit.state).thenReturn(
      const PatientMessagesSummaryLoaded(unreadCount: 0, urgentUnreadCount: 0),
    );
    expiringQuotesSummaryCubit = _MockExpiringQuotesSummaryCubit();
    when(() => expiringQuotesSummaryCubit.state)
        .thenReturn(const ExpiringQuotesSummaryLoaded(quotes: []));
    opportunitiesCubit = _MockOpportunitiesCubit();
    complianceAlertsSummaryCubit = _MockComplianceAlertsSummaryCubit();
    when(() => complianceAlertsSummaryCubit.state).thenReturn(
      const ComplianceAlertsSummaryLoaded(alertingItems: []),
    );
    // `TasksCard` (#7210) résout son propre `TasksBloc` via GetIt (il ouvre
    // sa propre `BlocProvider`, comme `WorkQueueCard`/`OpportunitiesCard` ne
    // le font pas mais `todayScheduleCard` côté app_practicien le fait déjà).
    tasksBloc = _MockTasksBloc();
    when(() => tasksBloc.state).thenReturn(const TasksLoaded(tasks: []));
    GetIt.instance.registerFactory<TasksBloc>(() => tasksBloc);
  });

  tearDown(() => GetIt.instance.reset());

  Widget wrap(GoRouter router) => MultiBlocProvider(
        providers: [
          BlocProvider<DashboardBloc>.value(value: dashboardBloc),
          BlocProvider<CashCollectionCubit>.value(value: cashCollectionCubit),
          BlocProvider<WaitingRoomSummaryCubit>.value(
              value: waitingRoomSummaryCubit),
          BlocProvider<PatientMessagesSummaryCubit>.value(
              value: patientMessagesSummaryCubit),
          BlocProvider<ExpiringQuotesSummaryCubit>.value(
              value: expiringQuotesSummaryCubit),
          BlocProvider<OpportunitiesCubit>.value(value: opportunitiesCubit),
          BlocProvider<ComplianceAlertsSummaryCubit>.value(
              value: complianceAlertsSummaryCubit),
        ],
        child:
            MaterialApp.router(theme: NubiaTheme.light, routerConfig: router),
      );

  GoRouter makeRouter() => GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, __) => const DashboardContent(session: _session),
          ),
          GoRoute(
            path: AppRouter.devis,
            builder: (_, state) =>
                Scaffold(body: Text('devis extra=${state.extra}')),
          ),
          GoRoute(
            path: AppRouter.patients,
            builder: (_, state) =>
                Scaffold(body: Text('patients extra=${state.extra}')),
          ),
        ],
      );

  testWidgets(
    'devis expirant sans réponse → volet devis du patient (#7213)',
    (tester) async {
      // Surface large (desktop) : les autres cartes du tableau de bord
      // (cash collection, occupation, praticiens) débordent sur la surface
      // de test 800×600 par défaut, hors de propos pour ce test de
      // navigation (#7213).
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      when(() => opportunitiesCubit.state).thenReturn(
        const OpportunitiesLoaded(categories: [
          OpportunityCategory(
            kind: 'quote_sent_no_response',
            count: 1,
            totalAmountCents: 15000,
            items: [
              OpportunityItem(
                kind: 'quote_sent_no_response',
                patientId: 'pat-1',
                quoteId: 'quote-9',
                amountCents: 15000,
              ),
            ],
          ),
        ]),
      );

      await tester.pumpWidget(wrap(makeRouter()));
      await tester.pumpAndSettle();

      await tester
          .tap(find.byKey(const Key('opportunity_row_quote_sent_no_response')));
      await tester.pumpAndSettle();

      expect(find.text('devis extra=quote-9'), findsOneWidget);
    },
  );

  testWidgets(
    'patient sans prochain RDV → fiche patient (#7213)',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      when(() => opportunitiesCubit.state).thenReturn(
        const OpportunitiesLoaded(categories: [
          OpportunityCategory(
            kind: 'patient_no_next_appointment',
            count: 1,
            totalAmountCents: 0,
            items: [
              OpportunityItem(
                kind: 'patient_no_next_appointment',
                patientId: 'pat-5',
                sinceDays: 12,
              ),
            ],
          ),
        ]),
      );

      await tester.pumpWidget(wrap(makeRouter()));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('opportunity_row_patient_no_next_appointment')),
      );
      await tester.pumpAndSettle();

      expect(find.text('patients extra=pat-5'), findsOneWidget);
    },
  );
}
