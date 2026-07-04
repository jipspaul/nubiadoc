import 'package:flutter/material.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

/// Timeline verticale des 4 étapes du click-and-collect.
/// Refus/annulation : bandeau dédié au-dessus (états terminaux hors parcours).
class OrderTimeline extends StatelessWidget {
  const OrderTimeline({super.key, required this.order});

  final PharmacyOrder order;

  static const _steps = <(PharmacyOrderStatus, String)>[
    (PharmacyOrderStatus.received, 'Commande reçue'),
    (PharmacyOrderStatus.preparing, 'En cours de préparation'),
    (PharmacyOrderStatus.ready, 'Prête à être retirée'),
    (PharmacyOrderStatus.pickedUp, 'Retirée'),
  ];

  int get _currentIndex => switch (order.status) {
        PharmacyOrderStatus.received => 0,
        PharmacyOrderStatus.preparing => 1,
        PharmacyOrderStatus.ready => 2,
        PharmacyOrderStatus.pickedUp => 3,
        PharmacyOrderStatus.rejected || PharmacyOrderStatus.cancelled => -1,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final current = _currentIndex;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (current == -1)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              order.status == PharmacyOrderStatus.rejected
                  ? 'Commande refusée par la pharmacie'
                      '${order.rejectionReason != null ? ' — ${order.rejectionReason}' : ''}'
                  : 'Commande annulée',
              key: const Key('timeline_terminal_banner'),
              style:
                  theme.textTheme.bodyMedium?.copyWith(color: tokens.dangerFg),
            ),
          ),
        for (final (index, step) in _steps.indexed)
          _TimelineStep(
            key: Key('timeline_step_${step.$1.name}'),
            label: step.$2,
            done: current >= 0 && index <= current,
            isLast: index == _steps.length - 1,
          ),
      ],
    );
  }
}

class _TimelineStep extends StatelessWidget {
  const _TimelineStep({
    super.key,
    required this.label,
    required this.done,
    required this.isLast,
  });

  final String label;
  final bool done;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final color = done ? tokens.successFg : theme.disabledColor;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              Icon(
                done ? Icons.check_circle : Icons.radio_button_unchecked,
                size: 20,
                color: color,
              ),
              if (!isLast) Expanded(child: Container(width: 2, color: color)),
            ],
          ),
          const SizedBox(width: 12),
          Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: done ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
