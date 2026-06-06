import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_patient/core/router/route_names.dart';
import 'package:nubia_patient/core/router/router_notifier.dart';
import 'package:nubia_patient/core/storage/token_storage.dart';

class _MockTokenStorage extends Mock implements TokenStorage {}

/// Crée un routeur minimal avec la même logique de garde qu'[AppRouter._authGuard].
GoRouter _buildGuardRouter(RouterNotifier notifier) {
  return GoRouter(
    initialLocation: RouteNames.home,
    refreshListenable: notifier,
    redirect: (_, state) {
      final authenticated = notifier.isAuthenticated;
      final onAuthRoute = state.matchedLocation == RouteNames.login ||
          state.matchedLocation == RouteNames.register;
      if (!authenticated && !onAuthRoute) return RouteNames.login;
      if (authenticated && onAuthRoute) return RouteNames.home;
      return null;
    },
    routes: [
      GoRoute(
        path: RouteNames.login,
        builder: (_, __) =>
            const Text('LoginScreen', textDirection: TextDirection.ltr),
      ),
      GoRoute(
        path: RouteNames.home,
        builder: (_, __) =>
            const Text('HomeScreen', textDirection: TextDirection.ltr),
      ),
    ],
  );
}

void main() {
  group('AppRouter — garde d\'authentification', () {
    late _MockTokenStorage mockStorage;

    setUp(() {
      mockStorage = _MockTokenStorage();
    });

    testWidgets('redirige vers /login si non authentifié', (tester) async {
      final notifier = RouterNotifier(mockStorage);
      addTearDown(notifier.dispose);

      await tester.pumpWidget(
        MaterialApp.router(routerConfig: _buildGuardRouter(notifier)),
      );
      await tester.pumpAndSettle();

      expect(find.text('LoginScreen'), findsOneWidget);
      expect(find.text('HomeScreen'), findsNothing);
    });

    testWidgets(
        'redirige vers / si authentifié et tentative d\'accès à /login',
        (tester) async {
      final notifier = RouterNotifier(mockStorage);
      addTearDown(notifier.dispose);
      notifier.markAuthenticated();

      await tester.pumpWidget(
        MaterialApp.router(routerConfig: _buildGuardRouter(notifier)),
      );
      await tester.pumpAndSettle();

      expect(find.text('HomeScreen'), findsOneWidget);
      expect(find.text('LoginScreen'), findsNothing);
    });

    testWidgets('laisse passer vers / quand authentifié', (tester) async {
      final notifier = RouterNotifier(mockStorage);
      addTearDown(notifier.dispose);
      notifier.markAuthenticated();

      await tester.pumpWidget(
        MaterialApp.router(routerConfig: _buildGuardRouter(notifier)),
      );
      await tester.pumpAndSettle();

      expect(find.text('HomeScreen'), findsOneWidget);
    });

    testWidgets('redirige vers /login après déconnexion', (tester) async {
      final notifier = RouterNotifier(mockStorage);
      addTearDown(notifier.dispose);
      notifier.markAuthenticated();

      final router = _buildGuardRouter(notifier);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      expect(find.text('HomeScreen'), findsOneWidget);

      notifier.markUnauthenticated();
      await tester.pumpAndSettle();

      expect(find.text('LoginScreen'), findsOneWidget);
    });
  });
}
