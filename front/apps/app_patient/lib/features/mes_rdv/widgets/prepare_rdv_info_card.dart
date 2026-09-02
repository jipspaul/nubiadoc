import 'package:flutter/material.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import '../appointment_formatting.dart';

/// En-tête « infos pratiques » de `PrepareRdvPage` : praticien, adresse,
/// accès (parking / PMR / code porte) et heure de rappel — champs renvoyés
/// par `GET /appointments/:id/preparation` mais jusque-là jetés par le DTO
/// et jamais restitués au patient (#6203).
class PrepareRdvInfoCard extends StatelessWidget {
  const PrepareRdvInfoCard({super.key, required this.preparation});

  final AppointmentPreparation preparation;

  @override
  Widget build(BuildContext context) {
    final access = preparation.access;
    final rows = <Widget>[
      if (preparation.providerName != null)
        _InfoRow(
          icon: Icons.medical_services_outlined,
          label: preparation.providerName!,
        ),
      if (preparation.address != null)
        _InfoRow(
          key: const Key('prepare_rdv_address'),
          icon: Icons.place_outlined,
          label: preparation.address!,
        ),
      if (access != null) ...[
        _InfoRow(
          icon: Icons.local_parking_outlined,
          label: access.parking ? 'Parking disponible' : 'Pas de parking',
        ),
        _InfoRow(
          icon: Icons.accessible_outlined,
          label: access.pmr ? 'Accès PMR' : 'Non accessible PMR',
        ),
        if (access.doorCode != null)
          _InfoRow(
            icon: Icons.dialpad_outlined,
            label: 'Code porte : ${access.doorCode}',
          ),
      ],
      if (preparation.reminderAt != null)
        _InfoRow(
          icon: Icons.notifications_outlined,
          label: 'Rappel ${formatAppointmentDateTime(preparation.reminderAt!)}',
        ),
    ];

    if (rows.isEmpty) return const SizedBox.shrink();

    return NubiaCard(
      key: const Key('prepare_rdv_info_card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            rows[i],
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _InfoRow extends StatelessWidget {
  const _InfoRow({super.key, required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: tokens.textTertiary),
        const SizedBox(width: 10),
        Expanded(child: Text(label)),
      ],
    );
  }
}
