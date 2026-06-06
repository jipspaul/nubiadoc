import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:nubia_patient/domain/entities/message.dart';

/// Renders a single chat bubble.
class MessageBubble extends StatelessWidget {
  const MessageBubble({super.key, required this.message});

  final Message message;

  @override
  Widget build(BuildContext context) {
    final isPatient = message.sender == MessageSender.patient;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Align(
      alignment: isPatient ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.75,
        ),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isPatient
                ? colorScheme.primary
                : colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(isPatient ? 16 : 4),
              bottomRight: Radius.circular(isPatient ? 4 : 16),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (message.text != null)
                Text(
                  message.text!,
                  style: textTheme.bodyMedium?.copyWith(
                    color: isPatient
                        ? colorScheme.onPrimary
                        : colorScheme.onSurface,
                  ),
                ),
              const SizedBox(height: 2),
              Text(
                DateFormat.Hm().format(message.sentAt),
                style: textTheme.labelSmall?.copyWith(
                  color: isPatient
                       ? colorScheme.onPrimary.withValues(alpha: 0.7)
                      : colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
