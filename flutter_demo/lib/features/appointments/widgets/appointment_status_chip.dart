import 'package:flutter/material.dart';

import '../models/appointment.dart';

/// Chip coloré affichant le statut d'un RDV.
class AppointmentStatusChip extends StatelessWidget {
  const AppointmentStatusChip({super.key, required this.status});

  final AppointmentStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (label, bg, fg) = switch (status) {
      AppointmentStatus.confirmed => (
          'Confirmé',
          scheme.primaryContainer,
          scheme.onPrimaryContainer,
        ),
      AppointmentStatus.requested => (
          'Demandé',
          scheme.secondaryContainer,
          scheme.onSecondaryContainer,
        ),
      AppointmentStatus.cancelled => (
          'Annulé',
          scheme.errorContainer,
          scheme.onErrorContainer,
        ),
      AppointmentStatus.done => (
          'Terminé',
          scheme.surfaceContainerHighest,
          scheme.onSurfaceVariant,
        ),
    };

    return Chip(
      label: Text(label),
      backgroundColor: bg,
      labelStyle: Theme.of(context).textTheme.labelSmall?.copyWith(color: fg),
      padding: EdgeInsets.zero,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      side: BorderSide.none,
    );
  }
}
