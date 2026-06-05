import 'package:go_router/go_router.dart';
import 'package:nubia_patient/core/router/route_names.dart';

/// Top-level router — will be wired with auth guard once AuthBloc is in place.
class AppRouter {
  AppRouter._();

  static final router = GoRouter(
    initialLocation: RouteNames.home,
    routes: [
      // TODO: ShellRoute with bottom nav (5 tabs)
      // TODO: auth redirect guard
    ],
  );
}
