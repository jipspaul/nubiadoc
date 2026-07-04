import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_core/nubia_core.dart';

import '../features/home/pharma_home_page.dart';
import '../features/login/login_page.dart';
import '../features/order_detail/order_detail_page.dart';

class AppRouter {
  AppRouter._();

  static const splash = '/splash';
  static const login = '/login';
  static const orders = '/';
  static const stock = '/stock';
  static const messages = '/messages';
  static const devis = '/devis';

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
        GoRoute(path: stock, builder: (_, __) => const PharmaHomePage()),
        GoRoute(path: messages, builder: (_, __) => const PharmaHomePage()),
        GoRoute(path: devis, builder: (_, __) => const PharmaHomePage()),
      ],
    );
  }
}
