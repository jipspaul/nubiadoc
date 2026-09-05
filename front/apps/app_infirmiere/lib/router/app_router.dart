import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import '../features/home/infirmiere_home_page.dart';
import '../features/login/login_page.dart';
import '../features/notification_prefs/notification_prefs_page.dart';

class AppRouter {
  AppRouter._();

  static const splash = '/splash';
  static const login = '/login';
  static const home = '/';
  static const notificationPreferences = '/notification-preferences';

  static GoRouter create(RouterNotifier notifier) {
    return GoRouter(
      initialLocation: splash,
      refreshListenable: notifier,
      observers: [PosthogObserver()],
      redirect: buildAuthGuard(
        notifier,
        loginRoute: login,
        homeRoute: home,
        splashRoute: splash,
        authRoutes: const {login, splash},
        guestOnlyRoutes: const {login, splash},
      ),
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
        GoRoute(path: home, builder: (_, __) => const InfirmiereHomePage()),
        GoRoute(
          path: notificationPreferences,
          builder: (_, __) => const NotificationPrefsPage(),
        ),
      ],
    );
  }
}
