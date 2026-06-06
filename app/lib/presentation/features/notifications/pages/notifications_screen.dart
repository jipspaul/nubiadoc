import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_patient/presentation/features/notifications/bloc/notification_bloc.dart';
import 'package:nubia_patient/presentation/features/notifications/bloc/notification_event.dart';
import 'package:nubia_patient/presentation/features/notifications/bloc/notification_state.dart';
import 'package:nubia_patient/presentation/features/notifications/widgets/notification_tile.dart';

/// Full-page notifications list.
///
/// [NotificationBloc] is provided at app level (via [NubiaApp]); this screen
/// reads it from context — no extra BlocProvider needed here.
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _NotificationsBody();
  }
}

// ---------------------------------------------------------------------------

class _NotificationsBody extends StatelessWidget {
  const _NotificationsBody();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          BlocBuilder<NotificationBloc, NotificationState>(
            builder: (context, state) {
              if (state is NotificationLoaded && state.unreadCount > 0) {
                return TextButton(
                  onPressed: () => context
                      .read<NotificationBloc>()
                      .add(const NotificationMarkAllReadRequested()),
                  child: const Text('Tout lire'),
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ],
      ),
      body: BlocBuilder<NotificationBloc, NotificationState>(
        builder: (context, state) {
          if (state is NotificationLoading || state is NotificationInitial) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state is NotificationError) {
            return Center(child: Text(state.message));
          }
          if (state is NotificationLoaded) {
            if (state.notifications.isEmpty) {
              return const _EmptyNotifications();
            }
            return ListView.separated(
              itemCount: state.notifications.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final notification = state.notifications[index];
                return NotificationTile(
                  notification: notification,
                  onTap: () {
                    if (!notification.read) {
                      context.read<NotificationBloc>().add(
                            NotificationMarkReadRequested(notification.id),
                          );
                    }
                    final deepLink = notification.deepLink;
                    if (deepLink != null && deepLink.isNotEmpty) {
                      context.push(deepLink);
                    }
                  },
                );
              },
            );
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _EmptyNotifications extends StatelessWidget {
  const _EmptyNotifications();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.notifications_none,
            size: 56,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text(
            'Aucune notification',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}
