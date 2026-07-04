import 'package:flutter/material.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'order_status_pill.dart';

/// Une commande dans la file (patient minimisé + heure de réception + statut).
class OrderRow extends StatelessWidget {
  const OrderRow({super.key, required this.order, this.onTap});

  final PharmacyOrder order;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final time = MaterialLocalizations.of(context)
        .formatTimeOfDay(TimeOfDay.fromDateTime(order.createdAt.toLocal()));
    return ListRow(
      key: Key('order_row_${order.id}'),
      title: order.patientDisplayName ?? 'Patient',
      subtitle: 'Reçue à $time',
      trailing: OrderStatusPill(status: order.status),
      onTap: onTap,
    );
  }
}
