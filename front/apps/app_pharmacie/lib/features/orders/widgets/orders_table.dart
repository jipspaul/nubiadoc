import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import '../orders_bloc.dart';
import '../orders_event.dart';
import 'order_status_pill.dart';
import 'order_wait.dart';

/// Largeurs des colonnes du tableau de la file des commandes (design-v2,
/// #7840) — grille maquette
/// `Reçue | Patient | Prescripteur | Lignes | Statut | Action`, jumelle de
/// la grille stock (`stock_table.dart`, #6948) sur la même maquette.
class _OrdersColumns {
  const _OrdersColumns._();

  static const double gap = 12;
  static const double recue = 90;
  static const double prescripteur = 150;
  static const double lignes = 64;
  static const double statut = 130;
  static const double action = 150;

  /// Largeur minimale de la colonne `Expanded` (Patient) — même défense
  /// qu'en dessous de laquelle l'en-tête se rend verticalement, cf.
  /// `_StockColumns.cabinetMin` (stock_table.dart, #6948).
  static const double patientMin = 140;

  /// Largeur minimale du tableau entier : en dessous, [OrdersTable] défile
  /// horizontalement plutôt que d'écraser la colonne Patient — même
  /// stratégie que le tableau stock (#6948).
  static const double minTotalWidth = recue +
      gap +
      patientMin +
      gap +
      prescripteur +
      gap +
      lignes +
      gap +
      statut +
      gap +
      action +
      32;
}

class OrdersTableHeader extends StatelessWidget {
  const OrdersTableHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final style = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: tokens.textTertiary,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          SizedBox(width: _OrdersColumns.recue, child: Text('Reçue', style: style)),
          const SizedBox(width: _OrdersColumns.gap),
          Expanded(child: Text('Patient', style: style)),
          const SizedBox(width: _OrdersColumns.gap),
          SizedBox(
            width: _OrdersColumns.prescripteur,
            child: Text('Prescripteur', style: style),
          ),
          const SizedBox(width: _OrdersColumns.gap),
          SizedBox(
            width: _OrdersColumns.lignes,
            child: Text('Lignes', style: style, textAlign: TextAlign.right),
          ),
          const SizedBox(width: _OrdersColumns.gap),
          SizedBox(width: _OrdersColumns.statut, child: Text('Statut', style: style)),
          const SizedBox(width: _OrdersColumns.gap),
          SizedBox(
            width: _OrdersColumns.action,
            child: Text('Action', style: style, textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }
}

/// Tableau de la file des commandes complet — en-tête + lignes (#7840),
/// jumeau de [StockTable] (stock_table.dart) sur la même maquette : même
/// défilement horizontal en dessous de [_OrdersColumns.minTotalWidth] plutôt
/// que d'écraser la colonne Patient.
class OrdersTable extends StatelessWidget {
  const OrdersTable({
    super.key,
    required this.orders,
    required this.onOrderTap,
    this.pendingOrderId,
  });

  final List<PharmacyOrder> orders;
  final ValueChanged<String> onOrderTap;

  /// Commande dont la transition de ligne est en cours (pilote le loading
  /// du bouton d'action) — miroir de `OrdersLoaded.pendingOrderId`.
  final String? pendingOrderId;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth < _OrdersColumns.minTotalWidth
            ? _OrdersColumns.minTotalWidth
            : constraints.maxWidth;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: width,
            height: constraints.maxHeight,
            child: Column(
              children: [
                const OrdersTableHeader(),
                Expanded(
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.zero,
                    itemCount: orders.length,
                    itemBuilder: (ctx, i) => OrdersTableRow(
                      order: orders[i],
                      onTap: () => onOrderTap(orders[i].id),
                      actionInProgress: pendingOrderId == orders[i].id,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Ligne du tableau de la file des commandes (design-v2, #7840) : colonnes
/// Reçue (heure/date + délai), Patient (nom + n° commande), Prescripteur,
/// Lignes (nombre), Statut, Action. La ligne entière est cliquable (ouvre le
/// détail de la commande) sauf le bouton d'action, qui garde son comportement
/// propre — même contrat que [StockTableRow] (stock_table.dart).
class OrdersTableRow extends StatelessWidget {
  const OrdersTableRow({
    super.key,
    required this.order,
    this.onTap,
    this.actionInProgress = false,
  });

  final PharmacyOrder order;
  final VoidCallback? onTap;
  final bool actionInProgress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<NubiaTokens>()!;
    final textTheme = theme.textTheme;

    final receivedAt = order.createdAt.toLocal();
    final time = MaterialLocalizations.of(context)
        .formatTimeOfDay(TimeOfDay.fromDateTime(receivedAt));
    final now = DateTime.now();
    final isToday = receivedAt.year == now.year &&
        receivedAt.month == now.month &&
        receivedAt.day == now.day;
    // Une commande non reçue aujourd'hui doit rester situable dans le temps
    // (file triée sur plusieurs jours/semaines) : on affiche la date plutôt
    // que l'heure seule, cf. #6315.
    final receivedTop = isToday
        ? time
        : '${receivedAt.day.toString().padLeft(2, '0')}/'
            '${receivedAt.month.toString().padLeft(2, '0')}';

    final wait = orderWaitOf(order);
    final waitColor = switch (wait?.tone) {
      null => null,
      OrderWaitTone.neutral => tokens.textTertiary,
      OrderWaitTone.warning => tokens.warningFg,
      OrderWaitTone.danger => tokens.dangerFg,
    };

    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: _OrdersColumns.recue,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    receivedTop,
                    style: textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontFeatures: tabularFigures,
                    ),
                  ),
                  if (wait != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      wait.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall?.copyWith(
                        color: waitColor,
                        fontWeight: wait.tone == OrderWaitTone.neutral
                            ? FontWeight.w400
                            : FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: _OrdersColumns.gap),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    order.patientDisplayName ?? 'Patient',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.titleSmall,
                  ),
                  if (order.orderRef != null && order.orderRef!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      order.orderRef!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall?.copyWith(
                        color: tokens.textTertiary,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: _OrdersColumns.gap),
            SizedBox(
              width: _OrdersColumns.prescripteur,
              child: _PrescriberColumn(order: order),
            ),
            const SizedBox(width: _OrdersColumns.gap),
            SizedBox(
              width: _OrdersColumns.lignes,
              child: _LineCountColumn(order: order),
            ),
            const SizedBox(width: _OrdersColumns.gap),
            SizedBox(
              width: _OrdersColumns.statut,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: OrderStatusPill(status: order.status),
              ),
            ),
            const SizedBox(width: _OrdersColumns.gap),
            SizedBox(
              width: _OrdersColumns.action,
              child: Align(
                alignment: Alignment.centerRight,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: _RowAction(order: order, inProgress: actionInProgress),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        DecoratedBox(
          key: Key('order_row_${order.id}'),
          decoration: BoxDecoration(
            color: (wait?.isUrgent ?? false) ? tokens.dangerBg : null,
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(onTap: onTap, child: row),
          ),
        ),
        Divider(height: 1, thickness: 1, color: tokens.borderSubtle),
      ],
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
    return Column(
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
          textAlign: TextAlign.right,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: NubiaColors.n700,
                fontWeight: FontWeight.w700,
                fontFeatures: tabularFigures,
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
          onPressed: () => context.go(
            '/orders/${order.id}/pickup',
            // La commande complète (#7549) : le sous-écran de scan en a
            // besoin pour identifier ce qu'il délivre AVANT de scanner.
            extra: order,
          ),
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
