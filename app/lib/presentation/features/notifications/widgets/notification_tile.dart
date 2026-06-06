import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:nubia_patient/domain/entities/app_notification.dart';

/// A single row in the notifications list.
class NotificationTile extends StatelessWidget {
  const NotificationTile({
    super.key,
    required this.notification,
    required this.onTap,
  });

  final AppNotification notification;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isUnread = !notification.read;

    return InkWell(
      onTap: onTap,
      child: ColoredBox(
        color: isUnread
            ? colorScheme.primaryContainer.withValues(alpha: 0.12)
            : Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _NotificationIcon(type: notification.type, isUnread: isUnread),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      notification.title,
                      style: textTheme.bodyMedium?.copyWith(
                        fontWeight:
                            isUnread ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      notification.body,
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatDate(notification.createdAt),
                      style: textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (isUnread)
                Padding(
                  padding: const EdgeInsets.only(top: 4, left: 8),
                  child: CircleAvatar(
                    radius: 4,
                    backgroundColor: colorScheme.primary,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'À l\'instant';
    if (diff.inHours < 1) return 'Il y a ${diff.inMinutes} min';
    if (diff.inDays < 1) return 'Il y a ${diff.inHours} h';
    if (diff.inDays < 7) return 'Il y a ${diff.inDays} j';
    return DateFormat('dd/MM/yyyy', 'fr').format(dt);
  }
}

// ---------------------------------------------------------------------------

class _NotificationIcon extends StatelessWidget {
  const _NotificationIcon({required this.type, required this.isUnread});

  final NotificationType type;
  final bool isUnread;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return CircleAvatar(
      radius: 20,
      backgroundColor: isUnread
          ? colorScheme.primaryContainer
          : colorScheme.surfaceContainerHighest,
      child: Icon(
        _icon,
        size: 20,
        color: isUnread ? colorScheme.onPrimaryContainer : colorScheme.onSurfaceVariant,
      ),
    );
  }

  IconData get _icon {
    switch (type) {
      case NotificationType.appointment:
        return Icons.calendar_today_outlined;
      case NotificationType.message:
        return Icons.chat_bubble_outline;
      case NotificationType.document:
        return Icons.folder_outlined;
      case NotificationType.payment:
        return Icons.receipt_outlined;
      case NotificationType.other:
        return Icons.notifications_outlined;
    }
  }
}
