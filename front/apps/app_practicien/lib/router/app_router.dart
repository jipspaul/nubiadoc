import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import '../features/a2ui_demo/a2ui_demo_page.dart';
import '../features/agenda/agenda_page.dart';
import '../features/cabinet_messaging/cabinet_messaging_page.dart';
import '../features/consultation_clinique/consultation_clinique_page.dart';
import '../features/dashboard/dashboard_page.dart';
import '../features/ordonnances/ordonnances_page.dart';
import '../features/login/login_page.dart';
import '../features/patients/patients_page.dart';
import '../features/cabinet/cabinet_info_cubit.dart';
import '../features/cabinet/cabinet_info_page.dart';
import '../features/register/pro_register_cubit.dart';
import '../features/register/pro_register_page.dart';
import '../features/consultation_clinique/consultation_clinique_bloc.dart';
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
  static const consultation = '/consultation';
  static const ordonnances = '/ordonnances';
  static const a2uiDemo = '/a2ui-demo';
  static const registerPro = '/register-pro';
  static const cabinetSetup = '/cabinet-setup';

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
      ),
      routes: [
        GoRoute(
          path: splash,
          builder: (_, __) =>
              const Scaffold(body: Center(child: CircularProgressIndicator())),
        ),
        GoRoute(path: login, builder: (_, __) => const LoginPage()),
        GoRoute(path: home, builder: (_, __) => const DashboardPage()),
        GoRoute(
          path: agenda,
          builder: (_, __) => const AgendaPage(),
        ),
        GoRoute(
          path: waitingRoom,
          redirect: (_, __) => ProConfig.includeClinical ? null : home,
          builder: (_, __) => BlocProvider(
            create: (_) => GetIt.instance<WaitingRoomBloc>(),
            child: const WaitingRoomPage(),
          ),
        ),
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
            ),
          ],
        ),
        GoRoute(
          path: messages,
          builder: (_, __) => const Scaffold(body: CabinetMessagingPage()),
        ),
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
                body: NubiaEmptyState(
                  key: const Key('ordonnances_new'),
                  icon: Icons.medication_outlined,
                  title: 'Nouvelle ordonnance',
                  subtitle:
                      'Saisissez les médicaments à prescrire pour ce patient.',
                ),
              ),
            ),
          ],
        ),
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
      ],
    );
  }
}
