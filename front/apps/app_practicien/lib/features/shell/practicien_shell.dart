import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_app_shell/nubia_app_shell.dart' hide ProConfig;
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

import '../../pro_config.dart';
import '../../router/app_router.dart';
import '../../session/pro_auth_cubit.dart';
import '../notifications/notification_route_resolver.dart';

/// Shell scaffold shared by every branch of the `StatefulShellRoute` declared
/// in `app_router.dart` — wraps [navigationShell] in [ProShell] so the barre
/// latérale et la cloche de notifications persistent sur toutes les
/// destinations (`/patients`, `/devis`, `/lab-work-orders`, …), pas
/// seulement `/` (#6286 : jusqu'ici chaque route hors `/`/`/consultation`
/// était un `GoRoute` frère, hors shell).
///
/// [navigationShell] already resolves the active branch's content —
/// [ProShell] is given it as `body`, so it only owns the rail/drawer here
/// (même approche que `SecretariatShell`, app_secretariat).
class PracticienShell extends StatelessWidget {
  const PracticienShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  /// Ordre des branches du `StatefulShellRoute` (`app_router.dart`) —
  /// `/consultation` n'y figure pas : sa page construit déjà son propre
  /// `ProShell` (deep-link `?id=` géré indépendamment côté
  /// `consultation_clinique_page.dart`) et reste un `GoRoute` autonome, hors
  /// shell, à l'image de `patientNew`/`a2ui-demo` côté app_secretariat.
  static const _branchRoutes = [
    AppRouter.home,
    AppRouter.agenda,
    AppRouter.waitingRoom,
    AppRouter.patients,
    AppRouter.ordonnances,
    AppRouter.devis,
    AppRouter.stock,
    AppRouter.stockInventory,
    AppRouter.labWorkOrders,
    AppRouter.messages,
    AppRouter.teamMessages,
  ];

  @override
  Widget build(BuildContext context) {
    final session = switch (context.watch<ProAuthCubit>().state) {
      AuthAuthenticated(:final session) => session,
      _ => const AuthSession(
          kind: UserKind.pro,
          userId: 'me',
          role: ProConfig.role,
        ),
    };

    return ProShell(
      config: ProConfig.shellConfig,
      session: session,
      currentRoute: _branchRoutes[navigationShell.currentIndex],
      onNavigate: (destination) {
        final index = _branchRoutes.indexOf(destination.route);
        if (index == -1) {
          // `/consultation` : pas une branche du `StatefulShellRoute` (voir
          // doc de [_branchRoutes]) — navigation classique vers son propre
          // `GoRoute`/`ProShell`.
          context.go(destination.route);
          return;
        }
        navigationShell.goBranch(
          index,
          initialLocation: index == navigationShell.currentIndex,
        );
      },
      notificationRepository: GetIt.instance<NotificationRepository>(),
      notificationEvents: GetIt.instance<NotificationEventsPort>(),
      // #6280 — le panneau partagé (nubia_app_shell) ne connaît ni les kinds
      // praticien ni son AppRouter : c'est ici qu'on résout la route et
      // navigue, en refermant d'abord le panneau (même geste que le bouton
      // « Fermer »).
      onNotificationTap: (context, notification) {
        final route = NotificationRouteResolver.resolve(
          kind: notification.kind,
        );
        if (route == null) return;
        Navigator.of(context).pop();
        context.go(route);
      },
      body: navigationShell,
      trailingActions: [
        // #4539 : banc de test du framework A2UI, jamais eu sa place dans
        // la nav en production. Réservé aux builds debug.
        if (kDebugMode)
          IconButton(
            tooltip: 'Démo A2UI',
            icon: const Icon(Icons.auto_awesome_outlined),
            onPressed: () => context.push(AppRouter.a2uiDemo),
          ),
      ],
      onSignOut: () => context.read<ProAuthCubit>().signOut(),
    );
  }
}
