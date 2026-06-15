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

    if (!authenticated && !onAuthRoute) return loginRoute;
    if (authenticated && onAuthRoute && location != splashRoute) {
      return homeRoute;
    }
    return null;
  };
}
