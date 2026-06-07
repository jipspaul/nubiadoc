import 'package:flutter/material.dart';
import 'package:nubia_patient/domain/entities/prescription.dart';

/// Displays one medication line of a prescription with a delete action.
class PrescriptionItemTile extends StatelessWidget {
  const PrescriptionItemTile({
    super.key,
    required this.item,
    required this.onRemove,
  });

  final PrescriptionItem item;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.form != null
                        ? '${item.label} — ${item.form}'
                        : item.label,
                    style: textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.posology,
                    style: textTheme.bodySmall,
                  ),
                  Text(
                    'Durée : ${item.duration} · Qté : ${item.quantity}',
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              color: colorScheme.error,
              tooltip: 'Supprimer',
              onPressed: onRemove,
            ),
          ],
        ),
      ),
    );
  }
}
