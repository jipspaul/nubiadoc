import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_a2ui/nubia_a2ui.dart';
import 'package:nubia_core/nubia_core.dart';

import '../features/appointments/appointments_bloc.dart';
import '../features/appointments/appointments_page.dart';
import '../features/dashboard/dashboard_page.dart';
import '../features/financial/financial_bloc.dart';
import '../features/financial/financial_event.dart';
import '../features/financial/financial_page.dart';
import '../features/documents/documents_page.dart';
import '../features/login/login_page.dart';
import '../features/mes_rdv/mes_rdv_bloc.dart';
import '../features/mes_rdv/mes_rdv_page.dart';
import '../features/profile/profile_bloc.dart';
import '../features/profile/profile_event.dart';
import '../features/profile/profile_page.dart';

/// Patient router. Route names are app-owned; the auth guard is the shared
/// [buildAuthGuard] from nubia_core.
class AppRouter {
  AppRouter._();

  static const splash = '/splash';
  static const login = '/login';
  static const home = '/';
  static const a2uiDemo = '/a2ui-demo';
  static const appointments = '/appointments';
  static const mesRdv = '/mes-rdv';
  static const documents = '/documents';
  static const financial = '/financial';
  static const profile = '/profile';

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
          path: appointments,
          builder: (_, __) => BlocProvider(
            create: (_) => GetIt.instance<AppointmentsBloc>(),
            child: Scaffold(
              appBar: AppBar(title: const Text('Prendre un rendez-vous')),
              body: const AppointmentsPage(),
            ),
          ),
        ),
        GoRoute(
          path: mesRdv,
          builder: (_, __) => BlocProvider(
            create: (_) => GetIt.instance<MesRdvBloc>(),
            child: const Scaffold(
              body: MesRdvPage(),
            ),
          ),
        ),
        GoRoute(
          path: documents,
          builder: (_, __) => Scaffold(
            appBar: AppBar(title: const Text('Mes documents')),
            body: const DocumentsPage(),
          ),
        ),
        GoRoute(
          path: financial,
          builder: (_, __) => BlocProvider(
            create: (_) => GetIt.instance<FinancialBloc>()
              ..add(const FinancialLoadRequested()),
            child: Scaffold(
              appBar: AppBar(title: const Text('Mes devis')),
              body: const FinancialPage(),
            ),
          ),
        ),
        GoRoute(
          path: profile,
          builder: (_, __) => BlocProvider(
            create: (_) => GetIt.instance<ProfileBloc>()
              ..add(const ProfileLoadRequested()),
            child: Scaffold(
              appBar: AppBar(title: const Text('Mon profil')),
              body: const ProfilePage(),
            ),
          ),
        ),
      ],
    );
  }
}
