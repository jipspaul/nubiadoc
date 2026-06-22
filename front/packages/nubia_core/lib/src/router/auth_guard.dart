import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'router_notifier.dart';

/// Builds a [GoRouter] redirect guard shared by every Nubia app.
///
/// - Unauthenticated users on a non-auth route → redirected to [loginRoute].
/// - Authenticated users on an auth route (other than [splashRoute]) →
///   redirected to [homeRoute].
///
/// [authRoutes] is the set of locations that are reachable while logged out
/// (login, register, onboarding, splash…). Each app passes its own set.
GoRouterRedirect buildAuthGuard(
  RouterNotifier notifier, {
  required String loginRoute,
  required String homeRoute,
  required String splashRoute,
  required Set<String> authRoutes,
}) {
  return (BuildContext context, GoRouterState state) {
    final authenticated = notifier.isAuthenticated;
    final location = state.matchedLocation;
    final onAuthRoute = authRoutes.contains(location);

    // Splash is a transient boot screen: stay until the auth state is resolved,
    // then leave for home (authenticated) or login (not). Without this the app
    // is stuck on the splash spinner forever.
    if (location == splashRoute) {
      if (!notifier.isResolved) return null;
      return authenticated ? homeRoute : loginRoute;
    }

    if (!authenticated && !onAuthRoute) return loginRoute;
    if (authenticated && onAuthRoute) return homeRoute;
    return null;
  };
}
