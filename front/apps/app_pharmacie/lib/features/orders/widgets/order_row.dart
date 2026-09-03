import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import '../orders_bloc.dart';
import '../orders_event.dart';
import 'order_status_pill.dart';
import 'order_wait.dart';

/// Une commande dans la file (patient minimisé + heure de réception + statut
/// + action de transition contextuelle au statut).
class OrderRow extends StatelessWidget {
  const OrderRow({
    super.key,
    required this.order,
    this.onTap,
    this.actionInProgress = false,
  });

  final PharmacyOrder order;
  final VoidCallback? onTap;

  /// Transition de ligne (Préparer/Marquer prête) en cours pour cette
  /// commande — pilote le loading du bouton d'action.
  final bool actionInProgress;

  @override
  Widget build(BuildContext context) {
    final receivedAt = order.createdAt.toLocal();
    final time = MaterialLocalizations.of(context)
        .formatTimeOfDay(TimeOfDay.fromDateTime(receivedAt));
    final now = DateTime.now();
    final isToday = receivedAt.year == now.year &&
        receivedAt.month == now.month &&
        receivedAt.day == now.day;
    // Une commande non reçue aujourd'hui doit rester situable dans le temps
    // (file triée sur plusieurs jours/semaines) : on préfixe l'heure avec la
    // date plutôt que de l'afficher seule, cf. #6315.
    final receivedLabel = isToday
        ? 'Reçue à $time'
        : 'Reçue le '
            '${receivedAt.day.toString().padLeft(2, '0')}/'
            '${receivedAt.month.toString().padLeft(2, '0')} à $time';
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final wait = orderWaitOf(order);
    final waitColor = switch (wait?.tone) {
      null => null,
      OrderWaitTone.neutral => tokens.textTertiary,
      OrderWaitTone.warning => tokens.warningFg,
      OrderWaitTone.danger => tokens.dangerFg,
    };

    return DecoratedBox(
      key: Key('order_row_${order.id}'),
      decoration: BoxDecoration(
        color: (wait?.isUrgent ?? false) ? tokens.dangerBg : null,
      ),
      child: ListRow(
        title: order.patientDisplayName ?? 'Patient',
        subtitleWidget: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (order.orderRef != null && order.orderRef!.isNotEmpty)
              Text(
                order.orderRef!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: tokens.textTertiary,
                      fontFamily: 'monospace',
                    ),
              ),
            wait == null
                ? Text(
                    receivedLabel,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: tokens.textTertiary,
                        ),
                  )
                : Text.rich(
                    TextSpan(
                      text: '$receivedLabel\n',
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
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PrescriberColumn(order: order),
            const SizedBox(width: 16),
            _LineCountColumn(order: order),
            const SizedBox(width: 16),
            OrderStatusPill(status: order.status),
            const SizedBox(width: 8),
            _RowAction(order: order, inProgress: actionInProgress),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}

/// Colonne « Prescripteur » : médecin + cabinet en sous-ligne. Savoir de qui
/// vient l'ordonnance conditionne les questions à poser au patient en cas de
/// doute. Pas de placeholder si l'un des deux champs manque.
class _PrescriberColumn extends StatelessWidget {
  const _PrescriberColumn({required this.order});

  final PharmacyOrder order;

  @override
  Widget build(BuildContext context) {
    final name = order.prescriberName;
    if (name == null || name.isEmpty) {
      return const SizedBox.shrink();
    }

    final practice = order.prescriberPractice;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 140),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: NubiaColors.n700,
                  fontWeight: FontWeight.w500,
                ),
          ),
          if (practice != null && practice.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              practice,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: NubiaColors.n500,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Colonne « Lignes » : nombre de lignes de l'ordonnance, aligné à droite
/// (chiffre en tabular-nums au-dessus, sous-libellé pluralisé en dessous).
/// `lineCount == null` → rien (pas de « 0 » trompeur, la donnée peut
/// simplement ne pas être connue).
class _LineCountColumn extends StatelessWidget {
  const _LineCountColumn({required this.order});

  final PharmacyOrder order;

  @override
  Widget build(BuildContext context) {
    final count = order.lineCount;
    if (count == null) {
      return const SizedBox.shrink();
    }

    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$count',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: NubiaColors.n700,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
        ),
        Text(
          count >= 2 ? 'lignes' : 'ligne',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: tokens.textTertiary,
              ),
        ),
      ],
    );
  }
}

/// Bouton d'action contextuel au statut — miroir des libellés/transitions du
/// détail (`_ContextualAction`, `order_detail_page.dart`) mais sans le refus,
/// réservé au détail. Aucun bouton pour un état terminal.
class _RowAction extends StatelessWidget {
  const _RowAction({required this.order, required this.inProgress});

  final PharmacyOrder order;
  final bool inProgress;

  @override
  Widget build(BuildContext context) {
    switch (order.status) {
      case PharmacyOrderStatus.received:
        return NubiaButton(
          key: Key('order_row_prepare_${order.id}'),
          label: 'Préparer',
          icon: Icons.play_arrow,
          size: NubiaButtonSize.sm,
          isLoading: inProgress,
          onPressed: inProgress ? null : () => _requestTransition(context),
        );
      case PharmacyOrderStatus.preparing:
        return NubiaButton(
          key: Key('order_row_ready_${order.id}'),
          label: 'Marquer prête',
          icon: Icons.done_all,
          variant: NubiaButtonVariant.secondary,
          size: NubiaButtonSize.sm,
          isLoading: inProgress,
          onPressed: inProgress ? null : () => _requestTransition(context),
        );
      case PharmacyOrderStatus.ready:
        return NubiaButton(
          key: Key('order_row_deliver_${order.id}'),
          label: 'Délivrer',
          icon: Icons.qr_code_scanner,
          variant: NubiaButtonVariant.secondary,
          size: NubiaButtonSize.sm,
          onPressed: () => context.go('/orders/${order.id}/pickup'),
        );
      case PharmacyOrderStatus.pickedUp:
      case PharmacyOrderStatus.rejected:
      case PharmacyOrderStatus.cancelled:
        return const SizedBox.shrink();
    }
  }

  void _requestTransition(BuildContext context) {
    final target = switch (order.status) {
      PharmacyOrderStatus.received => PharmacyOrderStatus.preparing,
      PharmacyOrderStatus.preparing => PharmacyOrderStatus.ready,
      _ => throw StateError('Pas de transition de ligne pour ${order.status}'),
    };
    context.read<OrdersBloc>().add(OrdersTransitionRequested(order.id, target));
  }
}
