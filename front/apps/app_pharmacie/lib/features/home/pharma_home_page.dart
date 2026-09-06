import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_app_shell/nubia_app_shell.dart' hide ProConfig;
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import '../../pharma_config.dart';
import '../../router/app_router.dart';
import '../../session/pharma_auth_cubit.dart';
import '../notifications/notification_route_resolver.dart';
import '../devis/devis_bloc.dart';
import '../devis/devis_page.dart';
import '../orders/orders_bloc.dart';
import '../orders/orders_event.dart';
import '../orders/orders_page.dart';
import '../pharma_messaging/pharma_messaging_bloc.dart';
import '../pharma_messaging/pharma_messaging_event.dart';
import '../pharma_messaging/pharma_messaging_page.dart';
import '../stock/stock_bloc.dart';
import '../stock/stock_page.dart';

/// Entry point for the authenticated pharmacie home. Delegates layout to
/// [ProShell] (NavigationRail on desktop, Drawer on mobile).
///
/// La destination « Commandes » affiche la file (lot F4) ; les autres
/// destinations gardent le placeholder du shell (lots F5–F6).
class PharmaHomePage extends StatelessWidget {
  const PharmaHomePage({super.key, this.orderId});

  /// Commande ouverte via `/orders/:id` (#6627) — non nul uniquement quand
  /// cette instance vient de cette route. Pilote la sélection dans
  /// [OrdersScreen] tout en gardant le rail sur la destination « Commandes ».
  final String? orderId;

  @override
  Widget build(BuildContext context) {
    final session = switch (context.watch<PharmaAuthCubit>().state) {
      AuthAuthenticated(:final session) => session,
      _ => const AuthSession(
          kind: UserKind.pro,
          userId: 'me',
          role: PharmaConfig.role,
        ),
    };

    return ProShell(
      config: PharmaConfig.shellConfig,
      session: session,
      onSignOut: () => context.read<PharmaAuthCubit>().signOut(),
      // Synchronise l'onglet sélectionné avec l'URL go_router dans les 2
      // sens : `currentRoute` pilote la sélection depuis `state.uri.path`
      // (navigation directe / reload / retour navigateur, #4813), et
      // `onNavigate` pousse l'URL via `context.go` quand l'utilisateur
      // clique une destination dans le rail/drawer.
      // #6627 — `/orders/:id` reste rattachée à la destination « Commandes »
      // (l'URL ne matche `PharmaConfig.ordersRoute` qu'à l'exact), sinon plus
      // aucune entrée du rail ne serait sélectionnée pendant la délivrance.
      currentRoute: orderId != null
          ? PharmaConfig.ordersRoute
          : GoRouterState.of(context).uri.path,
      onNavigate: (destination) => context.go(destination.route),
      notificationRepository: GetIt.instance<NotificationRepository>(),
      // Lookup tolérant : les harnais de test enregistrent le repository
      // sans le port temps réel — la cloche retombe alors sur son polling.
      notificationEvents: GetIt.instance.isRegistered<NotificationEventsPort>()
          ? GetIt.instance<NotificationEventsPort>()
          : null,
      // #6280 — le panneau partagé (nubia_app_shell) ne connaît ni les kinds
      // pharmacie ni son AppRouter : c'est ici qu'on résout la route et
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
      trailingActions: [
        IconButton(
          key: const Key('pharma_notification_prefs_button'),
          tooltip: 'Préférences de notifications',
          icon: const Icon(Icons.settings_outlined),
          onPressed: () => context.go(AppRouter.notificationPreferences),
        ),
      ],
      bodyBuilder: (ctx, destination) {
        if (destination.route == PharmaConfig.ordersRoute) {
          return MultiBlocProvider(
            providers: [
              BlocProvider<OrdersBloc>(
                create: (_) =>
                    GetIt.instance<OrdersBloc>()..add(const OrdersSubscribed()),
              ),
              // L'aside « À traiter » agrège aussi les demandes de stock et
              // les messages du cabinet non lus (#4916) — chargés ici pour
              // rester disponibles sans navigation ni appel réseau depuis
              // l'aside elle-même.
              BlocProvider<StockBloc>(
                create: (_) => GetIt.instance<StockBloc>()
                  ..add(const StockLoadRequested()),
              ),
              BlocProvider<PharmaMessagingBloc>(
                create: (_) => GetIt.instance<PharmaMessagingBloc>()
                  ..add(const PharmaMessagingConversationsLoadRequested()),
              ),
            ],
            child: OrdersScreen(selectedOrderId: orderId),
          );
        }
        if (destination.route == '/stock') {
          return BlocProvider<StockBloc>(
            create: (_) =>
                GetIt.instance<StockBloc>()..add(const StockLoadRequested()),
            child: const StockView(),
          );
        }
        if (destination.route == '/messages') {
          return BlocProvider<PharmaMessagingBloc>(
            create: (_) => GetIt.instance<PharmaMessagingBloc>()
              ..add(const PharmaMessagingConversationsLoadRequested()),
            child: const PharmaMessagingPage(),
          );
        }
        if (destination.route == '/devis') {
          return BlocProvider<PharmacyDevisBloc>(
            create: (_) => GetIt.instance<PharmacyDevisBloc>()
              ..add(const PharmacyDevisLoadRequested()),
            child: const PharmacyDevisView(),
          );
        }
        return NubiaEmptyState(
          icon: destination.icon,
          title: destination.label,
          subtitle: 'Bientôt disponible.',
        );
      },
    );
  }
}
