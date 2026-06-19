import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_a2ui/nubia_a2ui.dart';
import 'package:nubia_core/nubia_core.dart';

import '../features/admin_membres/admin_membres_bloc.dart';
import '../features/admin_membres/admin_membres_page.dart';
import '../features/dashboard/dashboard_page.dart';
import '../features/devis/devis_bloc.dart';
import '../features/devis/devis_page.dart';
import '../features/login/login_page.dart';
import '../features/patients/patients_bloc.dart';
import '../features/patients/patients_page.dart';
import '../features/waiting_list/waiting_list_bloc.dart';
import '../features/waiting_list/waiting_list_page.dart';
import '../features/waiting_room/waiting_room_bloc.dart';
import '../features/waiting_room/waiting_room_page.dart';

class AppRouter {
  AppRouter._();

  static const splash = '/splash';
  static const login = '/login';
  static const home = '/';
  static const a2uiDemo = '/a2ui-demo';
  static const salleAttente = '/salle-attente';
  static const patients = '/patients';
  static const listeAttente = '/liste-attente';
  static const devis = '/devis';
  static const adminMembres = '/admin-membres';

  static GoRouter create(RouterNotifier notifier) {
    return GoRouter(
      initialLocation: splash,
      refreshListenable: notifier,
      redirect: buildAuthGuard(
        notifier,
        loginRoute: login,
        homeRoute: home,
        splashRoute: splash,
        authRoutes: const {login, splash},
      ),
      routes: [
        GoRoute(
          path: splash,
          builder: (_, __) =>
              const Scaffold(body: Center(child: CircularProgressIndicator())),
        ),
        GoRoute(path: login, builder: (_, __) => const LoginPage()),
        GoRoute(path: home, builder: (_, __) => const DashboardPage()),
        GoRoute(path: a2uiDemo, builder: (_, __) => const A2uiDemoPage()),
        GoRoute(
          path: salleAttente,
          builder: (_, __) => BlocProvider(
            create: (_) => GetIt.instance<WaitingRoomBloc>(),
            child: const WaitingRoomPage(),
          ),
        ),
        GoRoute(
          path: patients,
          builder: (_, __) => BlocProvider(
            create: (_) => GetIt.instance<PatientsBloc>(),
            child: const PatientsPage(),
          ),
        ),
        GoRoute(
          path: listeAttente,
          builder: (_, __) => BlocProvider(
            create: (_) => GetIt.instance<WaitingListBloc>(),
            child: const WaitingListPage(),
          ),
        ),
        GoRoute(
          path: devis,
          builder: (_, __) => BlocProvider(
            create: (_) => GetIt.instance<DevisBloc>(),
            child: const DevisPage(),
          ),
        ),
        GoRoute(
          path: adminMembres,
          builder: (_, __) => BlocProvider(
            create: (_) => GetIt.instance<AdminMembresBloc>(),
            child: const AdminMembresPage(),
          ),
        ),
      ],
    );
  }
}
