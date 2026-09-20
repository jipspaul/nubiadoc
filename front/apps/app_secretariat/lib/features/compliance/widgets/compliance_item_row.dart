import 'package:flutter/material.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

/// Libellé lisible d'un [ComplianceItem.kind] (`training`/`equipment_check`/
/// `register`/`other`, CHECK migration 0289).
String complianceKindLabel(String kind) => switch (kind) {
      'training' => 'Formation',
      'equipment_check' => 'Contrôle équipement',
      'register' => 'Registre',
      _ => 'Autre',
    };

({String label, NubiaBadgeVariant variant})? complianceAlertBadge(
  String? alertLevel,
) =>
    switch (alertLevel) {
      'overdue' => (label: 'Échu', variant: NubiaBadgeVariant.error),
      'due_j7' => (label: 'J-7', variant: NubiaBadgeVariant.warning),
      'due_j30' => (label: 'J-30', variant: NubiaBadgeVariant.info),
      _ => null,
    };

/// Ligne d'un item de l'échéancier de conformité (#7169) : libellé,
/// échéance, alerte (échu/J-7/J-30), et actions (justificatif, clôture).
class ComplianceItemRow extends StatelessWidget {
  const ComplianceItemRow({
    super.key,
    required this.item,
    this.onComplete,
    this.onAttachEvidence,
    this.showDivider = true,
  });

  final ComplianceItem item;
  final VoidCallback? onComplete;
  final VoidCallback? onAttachEvidence;
  final bool showDivider;

  String get _subtitle {
    final parts = <String>[
      complianceKindLabel(item.kind),
      if (item.equipmentLabel != null) item.equipmentLabel!,
      'Échéance ${item.dueDate}',
      if (item.recurrenceMonths != null)
        'Récurrent (${item.recurrenceMonths} mois)',
    ];
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final badge = complianceAlertBadge(item.alertLevel);
    return ListRow(
      key: Key('compliance_item_row_${item.id}'),
      title: item.label,
      subtitle: _subtitle,
      leading: item.isDone
          ? const Icon(Icons.check_circle_outline, color: Colors.green)
          : Icon(
              Icons.event_outlined,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (badge != null) ...[
            NubiaBadge.label(label: badge.label, variant: badge.variant),
            const SizedBox(width: 8),
          ],
          if (item.evidenceDocumentId != null)
            const Icon(Icons.attach_file, size: 18)
          else if (!item.isDone && onAttachEvidence != null)
            IconButton(
              key: Key('compliance_item_evidence_${item.id}'),
              tooltip: 'Joindre un justificatif',
              icon: const Icon(Icons.upload_file_outlined, size: 20),
              onPressed: onAttachEvidence,
            ),
          if (!item.isDone && onComplete != null)
            IconButton(
              key: Key('compliance_item_complete_${item.id}'),
              tooltip: 'Clôturer',
              icon: const Icon(Icons.task_alt_outlined, size: 20),
              onPressed: onComplete,
            ),
        ],
      ),
      showDivider: showDivider,
    );
  }
}
