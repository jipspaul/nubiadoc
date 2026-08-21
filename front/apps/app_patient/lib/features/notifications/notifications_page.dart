import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'notification_route_resolver.dart';
import 'notifications_bloc.dart';
import 'notifications_event.dart';
import 'notifications_state.dart';

/// En-tête de l'onglet Notifications : titre, sous-titre "N non lues" et
/// action « Tout marquer lu ».
///
/// Doit être placée dans un [BlocProvider<NotificationsBloc>].
class NotificationsAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  const NotificationsAppBar({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<NotificationsBloc, NotificationsState>(
      builder: (context, state) {
        final unreadCount = state is NotificationsLoaded
            ? state.unreadCount
            : null;
        return AppBar(
          title: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Notifications',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
              ),
              if (unreadCount != null)
                Text(
                  '$unreadCount non lues',
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: NubiaColors.n500,
                  ),
                ),
            ],
          ),
          actions: [
            if (unreadCount != null && unreadCount > 0)
              TextButton.icon(
                onPressed: () => context.read<NotificationsBloc>().add(
                  const NotificationMarkAllReadRequested(),
                ),
                icon: const Icon(Icons.done_all, color: NubiaColors.brand700),
                label: const Text(
                  'Tout marquer lu',
                  style: TextStyle(
                    color: NubiaColors.brand700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Page inbox des notifications patient.
///
/// Doit être placée dans un [BlocProvider<NotificationsBloc>].
class NotificationsPage extends StatelessWidget {
  const NotificationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<NotificationsBloc, NotificationsState>(
      builder: (context, state) => switch (state) {
        NotificationsInitial() || NotificationsLoading() => const Center(
          key: Key('notifications_loading'),
          child: CircularProgressIndicator(),
        ),
        NotificationsError(:final message) => NubiaErrorWidget(
          key: const Key('notifications_error'),
          message: message,
          onRetry: () => context.read<NotificationsBloc>().add(
            const NotificationsLoadRequested(),
          ),
        ),
        NotificationsEmpty() => const NubiaEmptyState(
          key: Key('notifications_empty'),
          icon: Icons.notifications_off,
          title: 'Aucune notification',
          subtitle: 'Vous êtes à jour',
        ),
        NotificationsLoaded loaded => _NotificationsContent(state: loaded),
      },
    );
  }
}

// ---------------------------------------------------------------------------

class _NotificationsContent extends StatelessWidget {
  const _NotificationsContent({required this.state});

  final NotificationsLoaded state;

  @override
  Widget build(BuildContext context) {
    if (state.notifications.isEmpty) {
      return const NubiaEmptyState(
        key: Key('notifications_empty'),
        icon: Icons.notifications_off,
        title: 'Aucune notification',
        subtitle: 'Vous êtes à jour',
      );
    }
    return ListView.separated(
      key: const Key('notifications_list'),
      itemCount: state.notifications.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) =>
          _NotificationTile(notification: state.notifications[i]),
    );
  }
}

// ---------------------------------------------------------------------------

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.notification});

  final AppNotification notification;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: Key('notif_${notification.id}'),
      leading: Icon(
        _iconFor(notification.type),
        color: notification.read
            ? Theme.of(context).colorScheme.onSurfaceVariant
            : Theme.of(context).colorScheme.primary,
      ),
      title: Text(
        notification.title,
        style: TextStyle(
          fontWeight: notification.read ? FontWeight.normal : FontWeight.bold,
        ),
      ),
      subtitle: Text(notification.body),
      onTap: () {
        context.read<NotificationsBloc>().add(
          NotificationMarkReadRequested(notification.id),
        );
        final deepLink = notification.deepLink;
        if (deepLink != null && deepLink.isNotEmpty) {
          final route = NotificationRouteResolver.resolve(deepLink: deepLink);
          if (route != null) context.go(route);
        }
      },
    );
  }

  static IconData _iconFor(NotificationType type) {
    return switch (type) {
      NotificationType.appointment => Icons.event_outlined,
      NotificationType.message => Icons.chat_bubble_outline,
      NotificationType.document => Icons.folder_outlined,
      NotificationType.payment => Icons.receipt_outlined,
      NotificationType.other => Icons.notifications_outlined,
    };
  }
}
