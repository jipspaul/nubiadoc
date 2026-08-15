import 'package:flutter/material.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import '../dashboard_state.dart';

/// Carte « Praticiens aujourd'hui » (#5385) : une ligne par praticien ayant
/// des RDV aujourd'hui, avec le nombre de RDV et une pastille de présence
/// dérivée de l'agenda déjà chargé (aucun appel réseau supplémentaire).
class PractitionersTodayCard extends StatelessWidget {
  const PractitionersTodayCard({super.key, required this.practitioners});

  final List<PractitionerToday> practitioners;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return NubiaCard(
      key: const Key('practitioners_today_card'),
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              children: [
                Icon(
                  Icons.groups_outlined,
                  size: 20,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text(
                  "Praticiens aujourd'hui",
                  style: textTheme.titleMedium?.copyWith(color: cs.onSurface),
                ),
              ],
            ),
          ),
          if (practitioners.isEmpty)
            const Padding(
              key: Key('practitioners_today_empty'),
              padding: EdgeInsets.only(bottom: 8),
              child: NubiaEmptyState(
                icon: Icons.event_busy_outlined,
                title: "Aucun praticien avec RDV aujourd'hui",
              ),
            )
          else
            for (int i = 0; i < practitioners.length; i++)
              _PractitionerRow(
                practitioner: practitioners[i],
                showDivider: i < practitioners.length - 1,
              ),
        ],
      ),
    );
  }
}

class _PractitionerRow extends StatelessWidget {
  const _PractitionerRow({
    required this.practitioner,
    required this.showDivider,
  });

  final PractitionerToday practitioner;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final count = practitioner.appointmentCount;
    final rdvLabel = '$count RDV';

    final String stateLabel;
    final String pillLabel;
    final StatusPillVariant pillVariant;
    if (practitioner.isInConsultation) {
      stateLabel = 'en consultation';
      pillLabel = 'Présente';
      pillVariant = StatusPillVariant.success;
    } else {
      final hour = practitioner.lastAppointmentEndsAt.hour;
      stateLabel = 'termine à ${hour}h';
      pillLabel = 'Départ ${hour}h';
      pillVariant = StatusPillVariant.warning;
    }

    return ListRow(
      key: Key('practitioner_today_${practitioner.practitionerId}'),
      title: practitioner.practitionerName,
      subtitle: '$rdvLabel · $stateLabel',
      trailing: StatusPill(label: pillLabel, variant: pillVariant),
      showDivider: showDivider,
    );
  }
}
