import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'notifications_bloc.dart';
import 'notifications_event.dart';
import 'notifications_state.dart';

/// Page inbox des notifications patient.
///
/// Doit être placée dans un [BlocProvider<NotificationsBloc>].
class NotificationsPage extends StatelessWidget {
  const NotificationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<NotificationsBloc, NotificationsState>(
      builder: (context, state) {
        if (state is NotificationsInitial || state is NotificationsLoading) {
          return const Center(
            key: Key('notifications_loading'),
            child: CircularProgressIndicator(),
          );
        }
        if (state is NotificationsError) {
          return Center(
            key: const Key('notifications_error'),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(state.message),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => context
                      .read<NotificationsBloc>()
                      .add(const NotificationsLoadRequested()),
                  child: const Text('Réessayer'),
                ),
              ],
            ),
          );
        }
        if (state is NotificationsLoaded) {
          return _NotificationsContent(state: state);
        }
        return const SizedBox.shrink();
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
    return Column(
      children: [
        if (state.unreadCount > 0)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => context
                    .read<NotificationsBloc>()
                    .add(const NotificationMarkAllReadRequested()),
                child: const Text('Tout marquer comme lu'),
              ),
            ),
          ),
        Expanded(
          child: ListView.separated(
            key: const Key('notifications_list'),
            itemCount: state.notifications.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) =>
                _NotificationTile(notification: state.notifications[i]),
          ),
        ),
      ],
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
          fontWeight:
              notification.read ? FontWeight.normal : FontWeight.bold,
        ),
      ),
      subtitle: Text(notification.body),
      onTap: () => context
          .read<NotificationsBloc>()
          .add(NotificationMarkReadRequested(notification.id)),
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
