import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_patient/core/router/main_shell.dart';
import 'package:nubia_patient/core/router/route_names.dart';
import 'package:nubia_patient/core/router/router_notifier.dart';
import 'package:nubia_patient/presentation/features/appointments/pages/appointment_detail_screen.dart';
import 'package:nubia_patient/presentation/features/appointments/pages/appointments_screen.dart';
import 'package:nubia_patient/presentation/features/auth/pages/login_screen.dart';
import 'package:nubia_patient/presentation/features/auth/pages/register_screen.dart';
import 'package:nubia_patient/presentation/features/documents/pages/document_sign_screen.dart';
import 'package:nubia_patient/presentation/features/documents/pages/documents_screen.dart';
import 'package:nubia_patient/presentation/features/home/pages/home_screen.dart';
import 'package:nubia_patient/presentation/features/messaging/pages/messages_screen.dart';
import 'package:nubia_patient/presentation/features/profile/pages/profile_screen.dart';

/// Top-level router.
///
/// Wires [ShellRoute] (5-tab bottom nav), auth redirect guard, and
/// deep-link routes together into a single [GoRouter] instance.
///
/// Obtain the singleton via [AppRouter.create].
class AppRouter {
  AppRouter._();

  /// Creates and configures the [GoRouter].
  ///
  /// [notifier] must be refreshed after every login/logout so that the
  /// redirect guard is re-evaluated.
  static GoRouter create(RouterNotifier notifier) {
    return GoRouter(
      initialLocation: RouteNames.home,
      refreshListenable: notifier,
      redirect: _authGuard(notifier),
      routes: [
        // ----------------------------------------------------------------
        // Auth routes (outside the shell — no bottom nav)
        // ----------------------------------------------------------------
        GoRoute(
          path: RouteNames.login,
          name: 'login',
          builder: (_, __) => const LoginScreen(),
        ),
        GoRoute(
          path: RouteNames.register,
          name: 'register',
          builder: (_, __) => const RegisterScreen(),
        ),

        // ----------------------------------------------------------------
        // Main shell — 5 tab branches with persistent state
        // ----------------------------------------------------------------
        StatefulShellRoute.indexedStack(
          builder: (_, __, shell) => MainShell(navigationShell: shell),
          branches: [
            // Branch 0 — Accueil
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: RouteNames.home,
                  name: 'home',
                  builder: (_, __) => const HomeScreen(),
                ),
              ],
            ),

            // Branch 1 — RDV
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: RouteNames.appointments,
                  name: 'appointments',
                  builder: (_, __) => const AppointmentsScreen(),
                ),
              ],
            ),

            // Branch 2 — Messages
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: RouteNames.messages,
                  name: 'messages',
                  builder: (_, __) => const MessagesScreen(),
                ),
              ],
            ),

            // Branch 3 — Documents
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: RouteNames.documents,
                  name: 'documents',
                  builder: (_, __) => const DocumentsScreen(),
                ),
              ],
            ),

            // Branch 4 — Profil
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: RouteNames.profile,
                  name: 'profile',
                  builder: (_, __) => const ProfileScreen(),
                ),
              ],
            ),
          ],
        ),

        // ----------------------------------------------------------------
        // Deep-link targets (outside shell to avoid showing bottom nav in
        // a modal-like detail pushed directly from a notification/link)
        // ----------------------------------------------------------------
        GoRoute(
          path: RouteNames.appointmentDetail,
          name: 'appointment-detail',
          builder: (_, state) => AppointmentDetailScreen(
            id: state.pathParameters['id']!,
          ),
        ),
        GoRoute(
          path: RouteNames.signatureFlow,
          name: 'document-sign',
          builder: (_, state) => DocumentSignScreen(
            id: state.pathParameters['id']!,
          ),
        ),
      ],
    );
  }

  // -------------------------------------------------------------------------
  // Auth redirect guard
  // -------------------------------------------------------------------------

  static GoRouterRedirect _authGuard(RouterNotifier notifier) {
    return (BuildContext context, GoRouterState state) {
      final authenticated = notifier.isAuthenticated;
      final onLogin = state.matchedLocation == RouteNames.login;
      final onRegister = state.matchedLocation == RouteNames.register;
      final onAuthRoute = onLogin || onRegister;

      if (!authenticated && !onAuthRoute) {
        // Not logged in and not on an auth page → redirect to /login.
        return RouteNames.login;
      }

      if (authenticated && onAuthRoute) {
        // Already logged in but trying to visit an auth page → send home.
        return RouteNames.home;
      }

      // No redirect needed.
      return null;
    };
  }
}


