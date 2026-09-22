import 'package:flutter/material.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

const _statusLabels = {
  'open': 'Ouvert',
  'in_progress': 'En cours',
  'resolved': 'Résolu',
  'cancelled': 'Annulé',
};

const _statusVariants = {
  'open': StatusPillVariant.warning,
  'in_progress': StatusPillVariant.progress,
  'resolved': StatusPillVariant.success,
  'cancelled': StatusPillVariant.neutral,
};

/// Fiche équipement (#7166/#7167, DP-F18) : informations de l'inventaire +
/// historique des tickets de maintenance de cet équipement. [tickets] est
/// déjà filtré par l'appelant ([MaintenancePage], données déjà chargées —
/// aucun nouvel appel réseau).
class EquipmentDetailPage extends StatelessWidget {
  const EquipmentDetailPage({
    super.key,
    required this.equipment,
    required this.tickets,
  });

  final Equipment equipment;
  final List<MaintenanceTicket> tickets;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(equipment.label)),
      body: ListView(
        key: const Key('equipment_detail_list'),
        padding: const EdgeInsets.all(16),
        children: [
          NubiaCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _InfoRow(label: 'Catégorie', value: equipment.category),
                if (equipment.room != null)
                  _InfoRow(label: 'Salle', value: equipment.room!),
                if (equipment.supplier != null)
                  _InfoRow(label: 'Fournisseur', value: equipment.supplier!),
                if (equipment.technicianEmail != null)
                  _InfoRow(
                    label: 'E-mail technicien',
                    value: equipment.technicianEmail!,
                  ),
                if (equipment.technicianPhone != null)
                  _InfoRow(
                    label: 'Téléphone technicien',
                    value: equipment.technicianPhone!,
                  ),
                if (equipment.purchasedAt != null)
                  _InfoRow(label: 'Achat', value: equipment.purchasedAt!),
                if (equipment.nextCheckAt != null)
                  _InfoRow(
                    label: 'Prochain contrôle',
                    value: equipment.nextCheckAt!,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text('Tickets de maintenance', style: textTheme.titleMedium),
          const SizedBox(height: 8),
          if (tickets.isEmpty)
            const NubiaEmptyState(
              key: Key('equipment_detail_tickets_empty'),
              icon: Icons.build_outlined,
              title: 'Aucun ticket pour cet équipement',
            )
          else
            for (final ticket in tickets) ...[
              NubiaCard(
                key: Key('equipment_detail_ticket_${ticket.id}'),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        ticket.title,
                        style: textTheme.bodyMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    StatusPill(
                      label: _statusLabels[ticket.status] ?? ticket.status,
                      variant: _statusVariants[ticket.status] ??
                          StatusPillVariant.neutral,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: textTheme.bodySmall?.copyWith(color: NubiaColors.n500),
            ),
          ),
          Expanded(
            child: Text(value, style: textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}
