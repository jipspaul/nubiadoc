import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'pro_notifications_cubit.dart';
import 'pro_notifications_state.dart';
import 'pro_notifications_panel.dart';

/// Cloche de notifications de la topbar [ProShell] (#6263) — badge non-lus
/// + ouverture du [ProNotificationsPanel] en dropdown ancré sous la cloche.
class ProNotificationsBell extends StatelessWidget {
  const ProNotificationsBell({
    super.key,
    required this.cubit,
    this.onNotificationTap,
  });

  final ProNotificationsCubit cubit;

  /// Transmis tel quel à [ProNotificationsPanel] (voir [ProShell.onNotificationTap]).
  final void Function(BuildContext context, AppNotification notification)?
      onNotificationTap;

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: cubit,
      // Bandeau temps réel : chaque notification poussée sur le canal WS
      // `notifications` (incomingSeq bump) s'affiche en SnackBar cliquable —
      // titre générique sans PII par construction (notify.rs côté API).
      child: BlocListener<ProNotificationsCubit, ProNotificationsState>(
        listenWhen: (prev, next) =>
            next.incomingSeq != prev.incomingSeq && next.lastIncoming != null,
        listener: (context, state) {
          final incoming = state.lastIncoming!;
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            SnackBar(
              key: const Key('pro_notifications_toast'),
              content: Text(incoming.title),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 4),
              action: SnackBarAction(
                label: 'Voir',
                onPressed: () => _openPanel(context),
              ),
            ),
          );
        },
        child: Builder(
        builder: (context) {
          final unreadCount =
              context.select((ProNotificationsCubit c) => c.state.unreadCount);
          return IconButton(
            key: const Key('pro_notifications_bell'),
            tooltip: 'Notifications',
            onPressed: () => _openPanel(context),
            icon: Badge(
              key: const Key('pro_notifications_badge'),
              label: Text('$unreadCount'),
              isLabelVisible: unreadCount > 0,
              child: const Icon(Icons.notifications_outlined),
            ),
          );
        },
        ),
      ),
    );
  }

  void _openPanel(BuildContext context) {
    cubit.loadList();
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Notifications',
      barrierColor: Colors.transparent,
      transitionDuration: Duration.zero,
      pageBuilder: (dialogContext, _, __) => Align(
        alignment: Alignment.topRight,
        child: Padding(
          padding: const EdgeInsets.only(top: 64, right: 16),
          child: ProNotificationsPanel(
            cubit: cubit,
            onNotificationTap: onNotificationTap,
          ),
        ),
      ),
    );
  }
}
