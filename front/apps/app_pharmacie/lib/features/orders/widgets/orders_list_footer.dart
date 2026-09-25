import 'package:flutter/material.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

/// Agrégats du pied de liste — regroupés ici pour rester testables
/// indépendamment du widget (miroir de `DevisFooterStats`).
@immutable
class OrdersFooterStats {
  const OrdersFooterStats({
    required this.displayedCount,
    required this.totalCount,
    this.averagePreparationMinutes,
  });

  final int displayedCount;
  final int totalCount;

  /// `null` tant qu'aucune commande du filtre courant n'a atteint `ready`
  /// (rien à moyenner) — jamais de délai inventé (cf. #4916).
  final int? averagePreparationMinutes;

  factory OrdersFooterStats.of(
    List<PharmacyOrder> visibleOrders, {
    required int displayedCount,
  }) {
    var sumMinutes = 0;
    var readyCount = 0;
    for (final order in visibleOrders) {
      final readyAt = order.readyAt;
      if (readyAt == null) continue;
      sumMinutes += readyAt.difference(order.createdAt).inMinutes;
      readyCount++;
    }
    return OrdersFooterStats(
      displayedCount: displayedCount,
      totalCount: visibleOrders.length,
      averagePreparationMinutes:
          readyCount == 0 ? null : (sumMinutes / readyCount).round(),
    );
  }
}

/// Pied de la file des commandes (design-v2, écart #4 de la QA #7616) :
/// « N commandes affichées sur M · Délai moyen de préparation : X min » +
/// rappels clavier, absent jusqu'ici alors que l'écran Devis de cette même
/// app (`devis_list_footer.dart`) et les écrans secrétariat équivalents
/// (Stock, Fiches patients) l'ont déjà.
class OrdersListFooter extends StatelessWidget {
  const OrdersListFooter({super.key, required this.stats});

  final OrdersFooterStats stats;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final style = Theme.of(context)
        .textTheme
        .bodySmall
        ?.copyWith(color: tokens.textTertiary);
    final strongStyle = style?.copyWith(
      fontWeight: FontWeight.w600,
      color: Theme.of(context).colorScheme.onSurface,
    );
    final avg = stats.averagePreparationMinutes;
    final displayed = stats.displayedCount;

    return Container(
      key: const Key('orders_list_footer'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: tokens.borderSubtle)),
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text.rich(
            TextSpan(style: style, children: [
              TextSpan(text: '$displayed', style: strongStyle),
              TextSpan(
                  text: ' commande${displayed > 1 ? 's' : ''} affichée'
                      '${displayed > 1 ? 's' : ''} sur ${stats.totalCount}'),
            ]),
          ),
          Text.rich(
            TextSpan(style: style, children: [
              const TextSpan(text: 'Délai moyen de préparation : '),
              TextSpan(text: avg == null ? '—' : '$avg min', style: strongStyle),
            ]),
          ),
          Text('↑ ↓ naviguer', style: style),
          Text('⏎ ouvrir', style: style),
          Text('S scanner', style: style),
          Text('/ rechercher', style: style),
        ],
      ),
    );
  }
}
