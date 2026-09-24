import 'package:flutter/material.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'order_wait.dart';

/// Agrégats du bandeau de compteurs de la file de commandes (#4915).
///
/// « délivrées aujourd'hui » compte les commandes `pickedUp` du jour parmi
/// [orders] : sous-estimation possible si la file dépasse la fenêtre
/// chargée côté API (`GET /v1/pharmacy/orders` sans filtre renvoie au plus
/// 200 lignes toutes statuts confondus, triées par réception la plus
/// récente — les retraits anciens peuvent en être évincés). À fiabiliser
/// par un champ agrégé API si ça se révèle un problème en usage réel ; les
/// 3 autres compteurs (dérivés du statut courant, pas d'un historique) n'ont
/// pas cette limite.
class OrdersKpis {
  const OrdersKpis({
    required this.urgentCount,
    required this.preparingCount,
    required this.readyCount,
    required this.pickedUpTodayCount,
  });

  factory OrdersKpis.fromOrders(List<PharmacyOrder> orders, {DateTime? now}) {
    final reference = now ?? DateTime.now();
    var urgentCount = 0;
    var preparingCount = 0;
    var readyCount = 0;
    var pickedUpTodayCount = 0;
    for (final order in orders) {
      switch (order.status) {
        case PharmacyOrderStatus.received:
          if (orderWaitOf(order, now: reference)?.isUrgent ?? false) {
            urgentCount++;
          }
          break;
        case PharmacyOrderStatus.preparing:
          preparingCount++;
          break;
        case PharmacyOrderStatus.ready:
          readyCount++;
          break;
        case PharmacyOrderStatus.pickedUp:
          final pickedUpAt = order.pickedUpAt;
          if (pickedUpAt != null && _isSameDay(pickedUpAt, reference)) {
            pickedUpTodayCount++;
          }
          break;
        case PharmacyOrderStatus.rejected:
        case PharmacyOrderStatus.cancelled:
          break;
      }
    }
    return OrdersKpis(
      urgentCount: urgentCount,
      preparingCount: preparingCount,
      readyCount: readyCount,
      pickedUpTodayCount: pickedUpTodayCount,
    );
  }

  final int urgentCount;
  final int preparingCount;
  final int readyCount;
  final int pickedUpTodayCount;
}

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Bandeau de 4 compteurs en tête de la file de commandes : à préparer
/// d'urgence (rouge), en préparation (orange), prêtes à retirer et
/// délivrées aujourd'hui (neutres) — aucun appel réseau supplémentaire,
/// tout est dérivé de la file déjà chargée.
class OrdersKpiBanner extends StatelessWidget {
  const OrdersKpiBanner({super.key, required this.orders});

  final List<PharmacyOrder> orders;

  /// Largeur de bandeau sous laquelle 4 tuiles côte à côte n'ont plus assez
  /// de place pour les libellés les plus longs (« à préparer d'urgence »,
  /// « délivrées aujourd'hui ») et les cassent en plein mot — atteint par la
  /// colonne de file resserrée (`_wideQueueColumnWidth`, 360 px) quand le
  /// détail est ouvert à 1440 (#7594). On passe alors en grille 2×2.
  static const _twoColumnsBreakpoint = 480.0;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final kpis = OrdersKpis.fromOrders(orders);
    final stats = [
      _OrdersKpiStat(
        key: const Key('orders_kpi_urgent'),
        value: '${kpis.urgentCount}',
        label: 'à préparer d\'urgence',
        valueColor: tokens.dangerFg,
      ),
      _OrdersKpiStat(
        key: const Key('orders_kpi_preparing'),
        value: '${kpis.preparingCount}',
        label: 'en préparation',
        valueColor: tokens.warningFg,
      ),
      _OrdersKpiStat(
        key: const Key('orders_kpi_ready'),
        value: '${kpis.readyCount}',
        label: 'prêtes à retirer',
      ),
      _OrdersKpiStat(
        key: const Key('orders_kpi_picked_up_today'),
        value: '${kpis.pickedUpTodayCount}',
        label: 'délivrées aujourd\'hui',
      ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < _twoColumnsBreakpoint) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: stats[0]),
                    const SizedBox(width: 24),
                    Expanded(child: stats[1]),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: stats[2]),
                    const SizedBox(width: 24),
                    Expanded(child: stats[3]),
                  ],
                ),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: stats[0]),
              const SizedBox(width: 24),
              Expanded(child: stats[1]),
              const SizedBox(width: 24),
              Expanded(child: stats[2]),
              const SizedBox(width: 24),
              Expanded(child: stats[3]),
            ],
          );
        },
      ),
    );
  }
}

/// Une valeur (chiffres tabulaires) et son libellé, empilés — un compteur du
/// [OrdersKpiBanner].
class _OrdersKpiStat extends StatelessWidget {
  const _OrdersKpiStat({
    super.key,
    required this.value,
    required this.label,
    this.valueColor,
  });

  final String value;
  final String label;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<NubiaTokens>()!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: theme.textTheme.titleLarge?.copyWith(
            color: valueColor ?? theme.colorScheme.onSurface,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: tokens.textTertiary,
          ),
        ),
      ],
    );
  }
}
