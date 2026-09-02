import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'pro_notifications_cubit.dart';
import 'pro_notifications_panel.dart';

/// Cloche de notifications de la topbar [ProShell] (#6263) — badge non-lus
/// + ouverture du [ProNotificationsPanel] en dropdown ancré sous la cloche.
class ProNotificationsBell extends StatelessWidget {
  const ProNotificationsBell({super.key, required this.cubit});

  final ProNotificationsCubit cubit;

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: cubit,
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
          child: ProNotificationsPanel(cubit: cubit),
        ),
      ),
    );
  }
}
