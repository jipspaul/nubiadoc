import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:nubia_app_shell/nubia_app_shell.dart' hide ProConfig;
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import '../../pharma_config.dart';
import '../../session/pharma_auth_cubit.dart';
import '../orders/orders_bloc.dart';
import '../orders/orders_event.dart';
import '../orders/orders_page.dart';

/// Entry point for the authenticated pharmacie home. Delegates layout to
/// [ProShell] (NavigationRail on desktop, Drawer on mobile).
///
/// La destination « Commandes » affiche la file (lot F4) ; les autres
/// destinations gardent le placeholder du shell (lots F5–F6).
class PharmaHomePage extends StatelessWidget {
  const PharmaHomePage({super.key});

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
      bodyBuilder: (ctx, destination) {
        if (destination.route == PharmaConfig.ordersRoute) {
          return BlocProvider<OrdersBloc>(
            create: (_) =>
                GetIt.instance<OrdersBloc>()..add(const OrdersSubscribed()),
            child: const OrdersView(),
          );
        }
        // Placeholder par défaut du shell pour les destinations à venir.
        return NubiaEmptyState(
          icon: destination.icon,
          title: destination.label,
          subtitle: 'Bientôt disponible.',
        );
      },
    );
  }
}
