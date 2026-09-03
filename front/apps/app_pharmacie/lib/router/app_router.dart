import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import '../features/home/pharma_home_page.dart';
import '../features/login/login_page.dart';
import '../features/notification_prefs/pharma_notification_prefs_page.dart';
import '../features/order_detail/order_detail_page.dart';
import '../features/pickup_scan/pickup_scan_page.dart';

class AppRouter {
  AppRouter._();

  static const splash = '/splash';
  static const login = '/login';
  static const orders = '/';
  static const stock = '/stock';
  static const messages = '/messages';
  static const devis = '/devis';
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
        homeRoute: orders,
        splashRoute: splash,
        authRoutes: const {login, splash},
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
            onPressed: () => context.go(orders),
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
        GoRoute(path: orders, builder: (_, __) => const PharmaHomePage()),
        GoRoute(
          path: '/orders/:id',
          builder: (_, state) =>
              OrderDetailPage(orderId: state.pathParameters['id']!),
        ),
        GoRoute(
          path: '/orders/:id/pickup',
          // `extra` porte le numéro CMD-… de la commande en main quand la
          // navigation vient de la file (#6350) — absent en accès direct
          // par lien, auquel cas l'encart de non-correspondance se replie
          // sur l'UUID du path.
          builder: (_, state) => PickupScanPage(
            orderId: state.pathParameters['id']!,
            orderRef: state.extra as String?,
          ),
        ),
        GoRoute(
          path: notificationPreferences,
          builder: (_, __) => const PharmaNotificationPrefsPage(),
        ),
        GoRoute(path: stock, builder: (_, __) => const PharmaHomePage()),
        GoRoute(path: messages, builder: (_, __) => const PharmaHomePage()),
        GoRoute(path: devis, builder: (_, __) => const PharmaHomePage()),
      ],
    );
  }
}
