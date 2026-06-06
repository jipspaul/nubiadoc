import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:nubia_patient/presentation/features/appointments/bloc/booking_bloc.dart';
import 'package:nubia_patient/presentation/theme/nubia_tokens.dart';

/// A single slot chip — tappable if available, greyed-out if not.
class SlotChip extends StatelessWidget {
  const SlotChip({
    super.key,
    required this.slot,
    required this.isSelected,
    required this.onTap,
  });

  final AppointmentSlot slot;
  final bool isSelected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tokens = Theme.of(context).extension<NubiaTokens>();
    final label = DateFormat('EEE d MMM – HH:mm').format(slot.startsAt);

    final backgroundColor = !slot.available
        ? (tokens?.borderSubtle ?? colorScheme.surfaceContainerHighest)
        : isSelected
            ? colorScheme.primary
            : colorScheme.surface;

    final foregroundColor = !slot.available
        ? (tokens?.textTertiary ?? colorScheme.onSurfaceVariant)
        : isSelected
            ? colorScheme.onPrimary
            : colorScheme.onSurface;

    return GestureDetector(
      onTap: slot.available ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: const BorderRadius.all(Radius.circular(8)),
          border: Border.all(
            color: isSelected
                ? colorScheme.primary
                : (tokens?.borderDefault ?? colorScheme.outline),
          ),
        ),
        child: Text(
          label,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: foregroundColor),
        ),
      ),
    );
  }
}
