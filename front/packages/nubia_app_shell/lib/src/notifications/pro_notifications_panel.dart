import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'pro_notifications_cubit.dart';
import 'pro_notifications_state.dart';

/// Panneau liste ouvert depuis la cloche de [ProShell] (#6263) — même
/// contenu (title, temps relatif, non-lu en gras, « Tout marquer lu ») pour
/// les 3 apps pro, la maquette design-v2 `Patient Notifications v2.html`
/// n'ayant pas de variante par métier.
///
/// [cubit] est fourni directement (plutôt que via un `BlocProvider` ancêtre)
/// car ce panneau est monté dans une route de dialogue séparée
/// (`showGeneralDialog`), hors de l'arbre de [ProShell].
class ProNotificationsPanel extends StatelessWidget {
  const ProNotificationsPanel({super.key, required this.cubit});

  final ProNotificationsCubit cubit;

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: cubit,
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380, maxHeight: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _PanelHeader(),
              const Divider(height: 1),
              Flexible(
                child:
                    BlocBuilder<ProNotificationsCubit, ProNotificationsState>(
                  builder: (context, state) => _PanelBody(state: state),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PanelHeader extends StatelessWidget {
  const _PanelHeader();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Notifications',
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          BlocSelector<ProNotificationsCubit, ProNotificationsState, bool>(
            selector: (s) => s.unreadCount > 0,
            builder: (context, hasUnread) => hasUnread
                ? TextButton(
                    key: const Key('pro_notifications_mark_all_read'),
                    onPressed: () =>
                        context.read<ProNotificationsCubit>().markAllRead(),
                    child: const Text('Tout marquer lu'),
                  )
                : const SizedBox.shrink(),
          ),
          IconButton(
            tooltip: 'Fermer',
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

class _PanelBody extends StatelessWidget {
  const _PanelBody({required this.state});

  final ProNotificationsState state;

  @override
  Widget build(BuildContext context) {
    final notifications = state.notifications;
    if (notifications == null && state.isLoadingList) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(
          key: Key('pro_notifications_loading'),
          child: CircularProgressIndicator(),
        ),
      );
    }
    final error = state.error;
    if (notifications == null && error != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: NubiaErrorWidget(
          key: const Key('pro_notifications_error'),
          message: error,
          onRetry: () => context.read<ProNotificationsCubit>().loadList(),
        ),
      );
    }
    if (notifications == null || notifications.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: NubiaEmptyState(
          key: Key('pro_notifications_empty'),
          icon: Icons.notifications_off_outlined,
          title: 'Aucune notification',
        ),
      );
    }
    return ListView.separated(
      key: const Key('pro_notifications_list'),
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: notifications.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) =>
          _NotificationTile(notification: notifications[i]),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.notification});

  final AppNotification notification;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: Key('pro_notif_${notification.id}'),
      title: Text(
        notification.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: notification.read ? FontWeight.normal : FontWeight.bold,
        ),
      ),
      trailing: Text(
        NubiaDate.relative(notification.createdAt),
        style: const TextStyle(fontSize: 11.5, color: NubiaColors.n500),
      ),
      onTap: () =>
          context.read<ProNotificationsCubit>().markRead(notification.id),
    );
  }
}
