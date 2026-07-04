import 'package:flutter/material.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import '../../orders/widgets/order_status_pill.dart';

/// Informations de retrait d'une commande (patient minimisé, horodatages).
class PickupInfoCard extends StatelessWidget {
  const PickupInfoCard({super.key, required this.order});

  final PharmacyOrder order;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final locale = MaterialLocalizations.of(context);

    String formatInstant(DateTime value) {
      final local = value.toLocal();
      final date = locale.formatShortDate(local);
      final time = locale.formatTimeOfDay(TimeOfDay.fromDateTime(local));
      return '$date à $time';
    }

    return NubiaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  order.patientDisplayName ?? 'Patient',
                  style: theme.textTheme.titleMedium,
                ),
              ),
              OrderStatusPill(status: order.status),
            ],
          ),
          const SizedBox(height: 12),
          _InfoLine(label: 'Reçue', value: formatInstant(order.createdAt)),
          if (order.readyAt != null)
            _InfoLine(label: 'Prête', value: formatInstant(order.readyAt!)),
          if (order.pickedUpAt != null)
            _InfoLine(
                label: 'Retirée', value: formatInstant(order.pickedUpAt!)),
          if (order.rejectionReason != null) ...[
            const SizedBox(height: 8),
            Text(
              'Motif du refus : ${order.rejectionReason}',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 88,
            child: Text(label, style: theme.textTheme.bodySmall),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
