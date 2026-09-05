import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import '../features/a2ui_demo/a2ui_demo_page.dart';
import '../features/cabinet_team_messages/cabinet_team_messages_page.dart';
import '../features/agenda/agenda_page.dart';
import '../features/cabinet_messaging/cabinet_messaging_page.dart';
import '../features/consultation_clinique/consultation_clinique_page.dart';
import '../features/dashboard/dashboard_page.dart';
import '../features/dental_chart/dental_chart_page.dart';
import '../features/periodontal_chart/periodontal_chart_page.dart';
import '../features/treatment_plans/treatment_plans_page.dart';
import '../features/devis/devis_page.dart';
import '../features/ordonnances/ordonnance_new_page.dart';
import '../features/ordonnances/ordonnances_page.dart';
import '../features/login/login_page.dart';
import '../features/notification_prefs/notification_prefs_page.dart';
import '../features/patients/patients_page.dart';
import '../features/cabinet/cabinet_info_cubit.dart';
import '../features/cabinet/cabinet_info_page.dart';
import '../features/register/pro_register_cubit.dart';
import '../features/register/pro_register_page.dart';
import '../features/consultation_clinique/consultation_clinique_bloc.dart';
import '../features/lab_work/lab_work_orders_bloc.dart';
import '../features/lab_work/lab_work_orders_page.dart';
import '../features/shell/practicien_shell.dart';
import '../features/stock/stock_bloc.dart';
import '../features/stock/stock_inventory_bloc.dart';
import '../features/stock/stock_inventory_page.dart';
import '../features/stock/stock_page.dart';
import '../features/waiting_room/waiting_room_bloc.dart';
import '../features/waiting_room/waiting_room_page.dart';
import '../pro_config.dart';

class AppRouter {
  AppRouter._();

  static const splash = '/splash';
  static const login = '/login';
  static const home = '/';
  static const agenda = '/agenda';
  static const waitingRoom = '/waiting-room';
  static const patients = '/patients';
  static const messages = '/messages';
  static const teamMessages = '/team-messages';
  static const consultation = '/consultation';
  static const ordonnances = '/ordonnances';
  static const devis = '/devis';
  static const stock = '/stock';
  static const stockInventory = '/stock-inventory';
  static const labWorkOrders = '/lab-work-orders';
  static const a2uiDemo = '/a2ui-demo';
  static const registerPro = '/register-pro';
  static const cabinetSetup = '/cabinet-setup';
  static const notificationPreferences = '/notification-preferences';

  static GoRouter create(RouterNotifier notifier) {
    return GoRouter(
      initialLocation: splash,
      refreshListenable: notifier,
      // PostHog: capture les events $screen à chaque navigation.
      observers: [PosthogObserver()],
      redirect: buildAuthGuard(
        notifier,
        loginRoute: login,
        homeRoute: home,
        splashRoute: splash,
        authRoutes: const {login, splash, registerPro},
        // registerPro authentifie l'utilisateur en cours de flow (pour que
        // /cabinet-setup ne soit pas lui-même bloqué par le guard) puis
        // navigue explicitement vers cabinet-setup : ne pas le renvoyer vers
        // home entre-temps (course avec le listener du RouterNotifier).
        guestOnlyRoutes: const {login, splash},
      ),
      // Route inconnue (deep-link périmé, bookmark cassé) : sans errorBuilder,
      // go_router affiche son écran par défaut avec l'exception brute
      // (« GoException: no routes for location: … ») — #3894.
      errorBuilder: (context, state) => Scaffold(
        body: NubiaEmptyState(
          icon: Icons.search_off,
          title: 'Page introuvable',
          subtitle: 'Le lien que vous avez suivi n\'existe plus ou a changé.',
          action: FilledButton(
            onPressed: () => context.go(home),
            child: const Text('Retour à l\'accueil'),
          ),
        ),
      ),
      routes: [
        GoRoute(
          path: splash,
          builder: (_, __) =>
              const Scaffold(body: Center(child: CircularProgressIndicator())),
        ),
        GoRoute(path: login, builder: (_, __) => const LoginPage()),
        // #6286 — reste un `GoRoute` autonome hors du `StatefulShellRoute`
        // ci-dessous : construit déjà son propre `ProShell` (deep-link
        // `?id=` géré indépendamment, cf. `PracticienShell._branchRoutes`).
        GoRoute(
          path: consultation,
          redirect: (_, __) => ProConfig.includeClinical ? null : home,
          builder: (_, state) => BlocProvider(
            create: (_) => GetIt.instance<ConsultationCliniqueBloc>(),
            child: ConsultationCliniquePage(
              consultationId: state.uri.queryParameters['id'],
            ),
          ),
        ),
        if (kDebugMode)
          GoRoute(path: a2uiDemo, builder: (_, __) => const A2uiDemoPage()),
        GoRoute(
          path: registerPro,
          builder: (_, __) => BlocProvider(
            create: (_) => GetIt.instance<ProRegisterCubit>(),
            child: const ProRegisterPage(),
          ),
        ),
        GoRoute(
          path: cabinetSetup,
          builder: (_, __) => BlocProvider(
            create: (_) => GetIt.instance<CabinetInfoCubit>(),
            child: const CabinetInfoPage(),
          ),
        ),
        GoRoute(
          path: notificationPreferences,
          builder: (_, __) => const NotificationPrefsPage(),
        ),
        // #6286 — le `ProShell` enveloppe désormais TOUTES les autres
        // destinations de nav via `StatefulShellRoute.indexedStack` (une
        // branche par entrée de `PracticienShell._branchRoutes`, même
        // ordre) : la barre latérale et la cloche de notifications restent
        // visibles quelle que soit la route. Chaque branche réutilise
        // directement l'écran « page complète » existant (son propre
        // `Scaffold`/`AppBar` le cas échéant) — `ProShell` ne fournit son
        // propre `AppBar` générique que pour les destinations qui n'en ont
        // pas (aucune ici), afin de ne jamais dupliquer de barre de titre.
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) =>
              PracticienShell(navigationShell: navigationShell),
          branches: [
            StatefulShellBranch(routes: [
              GoRoute(path: home, builder: (_, __) => const DashboardBody()),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(path: agenda, builder: (_, __) => const AgendaPage()),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                path: waitingRoom,
                redirect: (_, __) => ProConfig.includeClinical ? null : home,
                builder: (_, __) => BlocProvider(
                  create: (_) => GetIt.instance<WaitingRoomBloc>(),
                  child: const WaitingRoomPage(),
                ),
              ),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                path: patients,
                builder: (_, __) => const Scaffold(body: PatientsPage()),
                routes: [
                  GoRoute(
                    path: ':id',
                    builder: (_, state) => Scaffold(
                      appBar: AppBar(title: const Text('Fiche patient')),
                      body: PatientDetailPage(
                        patientId: state.pathParameters['id']!,
                      ),
                    ),
                    routes: [
                      GoRoute(
                        path: 'dental-chart',
                        builder: (_, state) => DentalChartPage(
                          patientId: state.pathParameters['id']!,
                        ),
                      ),
                      GoRoute(
                        path: 'periodontal-chart',
                        builder: (_, state) => PeriodontalChartPage(
                          patientId: state.pathParameters['id']!,
                        ),
                      ),
                      GoRoute(
                        path: 'treatment-plans',
                        builder: (_, state) => TreatmentPlansPage(
                          patientId: state.pathParameters['id']!,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                path: ordonnances,
                redirect: (_, __) => ProConfig.includeClinical ? null : home,
                builder: (_, state) => Scaffold(
                  appBar: AppBar(title: const Text('Ordonnances')),
                  body: OrdonnancesPage(
                    patientId: state.uri.queryParameters['patientId'],
                  ),
                ),
                routes: [
                  GoRoute(
                    path: 'new',
                    builder: (_, state) => Scaffold(
                      key: const Key('ordonnances_new_scaffold'),
                      appBar: AppBar(title: const Text('Nouvelle ordonnance')),
                      body: OrdonnanceNewPage(
                        patientId: state.uri.queryParameters['patientId'],
                      ),
                    ),
                  ),
                ],
              ),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                path: devis,
                builder: (_, __) => const Scaffold(
                  body: DevisPage(),
                ),
              ),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                path: stock,
                builder: (_, __) => BlocProvider(
                  create: (_) => GetIt.instance<StockBloc>(),
                  child: const StockPage(),
                ),
              ),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                path: stockInventory,
                builder: (_, __) => BlocProvider(
                  create: (_) => GetIt.instance<StockInventoryBloc>(),
                  child: const StockInventoryPage(),
                ),
              ),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                path: labWorkOrders,
                builder: (_, __) => BlocProvider(
                  create: (_) => GetIt.instance<LabWorkOrdersBloc>(),
                  child: const LabWorkOrdersPage(),
                ),
              ),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                path: messages,
                builder: (_, __) =>
                    const Scaffold(body: CabinetMessagingPage()),
              ),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                path: teamMessages,
                builder: (_, __) => const CabinetTeamMessagesPage(),
              ),
            ]),
          ],
        ),
      ],
    );
  }
}
