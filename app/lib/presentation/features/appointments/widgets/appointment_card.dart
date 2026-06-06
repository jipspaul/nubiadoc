import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:nubia_patient/domain/entities/appointment.dart';
import 'package:nubia_patient/presentation/theme/nubia_tokens.dart';

/// A card displaying a single [Appointment] row.
///
/// Shows motif, practitioner name + specialty, date/time, and status chip.
/// [onTap] navigates to AppointmentDetailScreen.
class AppointmentCard extends StatelessWidget {
  const AppointmentCard({
    super.key,
    required this.appointment,
    required this.onTap,
  });

  final Appointment appointment;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final tokens = Theme.of(context).extension<NubiaTokens>()!;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      appointment.motif,
                      style: textTheme.titleSmall,
                    ),
                  ),
                  _StatusChip(
                    status: appointment.status,
                    tokens: tokens,
                    colorScheme: colorScheme,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _PractitionerRow(
                name: appointment.practitionerName,
                specialty: appointment.practitionerSpecialty,
                colorScheme: colorScheme,
                tokens: tokens,
              ),
              const SizedBox(height: 6),
              _DateRow(
                startsAt: appointment.startsAt,
                duration: appointment.duration,
                colorScheme: colorScheme,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _PractitionerRow extends StatelessWidget {
  const _PractitionerRow({
    required this.name,
    required this.specialty,
    required this.colorScheme,
    required this.tokens,
  });

  final String name;
  final String specialty;
  final ColorScheme colorScheme;
  final NubiaTokens tokens;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      children: [
        Icon(Icons.person_outline, size: 16, color: tokens.textTertiary),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            '$name · $specialty',
            style: textTheme.bodySmall?.copyWith(color: tokens.textTertiary),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _DateRow extends StatelessWidget {
  const _DateRow({
    required this.startsAt,
    required this.duration,
    required this.colorScheme,
  });

  final DateTime startsAt;
  final Duration duration;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final formatted = DateFormat("EEE d MMM yyyy 'à' HH'h'mm", 'fr').format(startsAt);
    final durationLabel = '${duration.inMinutes} min';

    return Row(
      children: [
        Icon(Icons.calendar_today_outlined,
            size: 16, color: colorScheme.primary),
        const SizedBox(width: 4),
        Text(
          '$formatted · $durationLabel',
          style:
              textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.status,
    required this.tokens,
    required this.colorScheme,
  });

  final AppointmentStatus status;
  final NubiaTokens tokens;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final (label, fg, bg) = _chipStyle(status, tokens, colorScheme);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: textTheme.labelSmall?.copyWith(color: fg),
      ),
    );
  }

  static (String, Color, Color) _chipStyle(
    AppointmentStatus status,
    NubiaTokens tokens,
    ColorScheme colorScheme,
  ) {
    switch (status) {
      case AppointmentStatus.confirmed:
        return ('Confirmé', tokens.successFg, tokens.successBg);
      case AppointmentStatus.requested:
        return ('En attente', tokens.warningFg, tokens.warningBg);
      case AppointmentStatus.cancelled:
        return ('Annulé', tokens.dangerFg, tokens.dangerBg);
      case AppointmentStatus.completed:
        return ('Terminé', tokens.textTertiary, tokens.primarySubtleBg);
      case AppointmentStatus.noShow:
        return ('Absent', tokens.dangerFg, tokens.dangerBg);
    }
  }
}
