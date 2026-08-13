import 'package:flutter/material.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'order_status_pill.dart';
import 'order_wait.dart';

/// Une commande dans la file (patient minimisé + heure de réception + statut).
class OrderRow extends StatelessWidget {
  const OrderRow({super.key, required this.order, this.onTap});

  final PharmacyOrder order;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final time = MaterialLocalizations.of(context)
        .formatTimeOfDay(TimeOfDay.fromDateTime(order.createdAt.toLocal()));
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final wait = orderWaitOf(order);
    final waitColor = switch (wait.tone) {
      OrderWaitTone.neutral => tokens.textTertiary,
      OrderWaitTone.warning => tokens.warningFg,
      OrderWaitTone.danger => tokens.dangerFg,
    };

    return DecoratedBox(
      key: Key('order_row_${order.id}'),
      decoration: BoxDecoration(
        color: wait.isUrgent ? tokens.dangerBg : null,
      ),
      child: ListRow(
        title: order.patientDisplayName ?? 'Patient',
        subtitleWidget: Text.rich(
          TextSpan(
            text: 'Reçue à $time\n',
            children: [
              TextSpan(
                text: wait.label,
                style: TextStyle(
                  color: waitColor,
                  fontWeight: wait.tone == OrderWaitTone.neutral
                      ? FontWeight.w400
                      : FontWeight.w700,
                ),
              ),
            ],
          ),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: tokens.textTertiary,
              ),
        ),
        trailing: OrderStatusPill(status: order.status),
        onTap: onTap,
      ),
    );
  }
}
