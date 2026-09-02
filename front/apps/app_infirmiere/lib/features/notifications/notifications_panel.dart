import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'notifications_bloc.dart';
import 'notifications_event.dart';
import 'notifications_state.dart';

/// Panneau de notifications infirmière, ouvert depuis la cloche du header
/// ([InfirmiereHomePage]).
///
/// Seul kind émis à l'infirmière côté backend aujourd'hui : `visit_offer`
/// (fan-out des offres de visite, cf. `api/src/nurse/requests.rs` et
/// `api/src/visit_offer_expiry.rs`) — toute notification listée ici est donc
/// une offre, d'où le tap qui bascule systématiquement vers l'onglet Offres.
///
/// Doit être placé dans un [BlocProvider<NotificationsBloc>].
class NurseNotificationsPanel extends StatelessWidget {
  const NurseNotificationsPanel({super.key, required this.onNotificationTap});

  /// Appelé après le marquage "lu" d'une notification tapée — le shell
  /// parent ferme le panneau et bascule sur l'onglet Offres.
  final VoidCallback onNotificationTap;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _PanelHeader(),
            const Divider(height: 1),
            Flexible(
              child: BlocBuilder<NotificationsBloc, NotificationsState>(
                builder: (context, state) => switch (state) {
                  NotificationsInitial() || NotificationsLoading() => const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(
                        key: Key('nurse_notifications_loading'),
                        child: CircularProgressIndicator(),
                      ),
                    ),
                  NotificationsError(:final message) => Padding(
                      padding: const EdgeInsets.all(24),
                      child: NubiaErrorWidget(
                        key: const Key('nurse_notifications_error'),
                        message: message,
                        onRetry: () => context.read<NotificationsBloc>().add(
                              const NotificationsLoadRequested(),
                            ),
                      ),
                    ),
                  NotificationsEmpty() => const Padding(
                      padding: EdgeInsets.all(24),
                      child: NubiaEmptyState(
                        key: Key('nurse_notifications_empty'),
                        icon: Icons.notifications_off,
                        title: 'Aucune notification',
                        subtitle: 'Les nouvelles offres apparaîtront ici.',
                      ),
                    ),
                  NotificationsLoaded loaded => _NotificationsList(
                      notifications: loaded.notifications,
                      onNotificationTap: onNotificationTap,
                    ),
                },
              ),
            ),
          ],
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
      padding: const EdgeInsets.fromLTRB(20, 4, 8, 8),
      child: Row(
        children: [
          Text(
            'Notifications',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const Spacer(),
          BlocSelector<NotificationsBloc, NotificationsState, bool>(
            selector: (s) => s is NotificationsLoaded && s.unreadCount > 0,
            builder: (context, hasUnread) => hasUnread
                ? TextButton(
                    key: const Key('nurse_notifications_mark_all_read'),
                    onPressed: () => context.read<NotificationsBloc>().add(
                          const NotificationMarkAllReadRequested(),
                        ),
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

class _NotificationsList extends StatelessWidget {
  const _NotificationsList({
    required this.notifications,
    required this.onNotificationTap,
  });

  final List<AppNotification> notifications;
  final VoidCallback onNotificationTap;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      key: const Key('nurse_notifications_list'),
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: notifications.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final notification = notifications[i];
        return ListTile(
          key: Key('nurse_notif_${notification.id}'),
          title: Text(
            notification.title,
            style: TextStyle(
              fontWeight:
                  notification.read ? FontWeight.normal : FontWeight.bold,
            ),
          ),
          subtitle: Text(notification.body),
          trailing: Text(
            NubiaDate.relative(notification.createdAt),
            style: const TextStyle(fontSize: 11.5, color: NubiaColors.n500),
          ),
          onTap: () {
            context.read<NotificationsBloc>().add(
                  NotificationMarkReadRequested(notification.id),
                );
            onNotificationTap();
          },
        );
      },
    );
  }
}
