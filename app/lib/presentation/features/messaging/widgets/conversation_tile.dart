import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:nubia_patient/domain/entities/message.dart';

/// A single row in the conversations list.
class ConversationTile extends StatelessWidget {
  const ConversationTile({
    super.key,
    required this.conversation,
    required this.onTap,
  });

  final Conversation conversation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final hasUnread = conversation.unreadCount > 0;
    final lastMsg = conversation.lastMessage;
    final isUrgent = lastMsg?.urgency == MessageUrgency.urgent;

    return ListTile(
      onTap: onTap,
      leading: Stack(
        clipBehavior: Clip.none,
        children: [
          CircleAvatar(
            backgroundColor: colorScheme.primaryContainer,
            child: Text(
              conversation.cabinetName.isNotEmpty
                  ? conversation.cabinetName[0].toUpperCase()
                  : '?',
              style: textTheme.titleMedium?.copyWith(
                color: colorScheme.onPrimaryContainer,
              ),
            ),
          ),
          if (isUrgent)
            Positioned(
              right: -2,
              top: -2,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: colorScheme.error,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: colorScheme.surface,
                    width: 1.5,
                  ),
                ),
              ),
            ),
        ],
      ),
      title: Text(
        conversation.cabinetName,
        style: textTheme.bodyLarge?.copyWith(
          fontWeight: hasUnread ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      subtitle: lastMsg?.text != null
          ? Text(
              lastMsg!.text!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            )
          : null,
      trailing: _ConversationTrailing(
        sentAt: lastMsg?.sentAt,
        unreadCount: conversation.unreadCount,
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _ConversationTrailing extends StatelessWidget {
  const _ConversationTrailing({
    required this.sentAt,
    required this.unreadCount,
  });

  final DateTime? sentAt;
  final int unreadCount;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (sentAt != null)
          Text(
            _formatDate(sentAt!),
            style: textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        if (unreadCount > 0) ...[
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: colorScheme.primary,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              unreadCount > 99 ? '99+' : '$unreadCount',
              style: textTheme.labelSmall?.copyWith(
                color: colorScheme.onPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ],
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    if (date.year == now.year &&
        date.month == now.month &&
        date.day == now.day) {
      return DateFormat.Hm().format(date);
    }
    return DateFormat('dd/MM').format(date);
  }
}


// ---------------------------------------------------------------------------

class _ConversationTrailing extends StatelessWidget {
  const _ConversationTrailing({
    required this.sentAt,
    required this.unreadCount,
  });

  final DateTime? sentAt;
  final int unreadCount;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (sentAt != null)
          Text(
            _formatDate(sentAt!),
            style: textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        if (unreadCount > 0) ...[
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: colorScheme.primary,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              unreadCount > 99 ? '99+' : '$unreadCount',
              style: textTheme.labelSmall?.copyWith(
                color: colorScheme.onPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ],
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    if (date.year == now.year &&
        date.month == now.month &&
        date.day == now.day) {
      return DateFormat.Hm().format(date);
    }
    return DateFormat('dd/MM').format(date);
  }
}
