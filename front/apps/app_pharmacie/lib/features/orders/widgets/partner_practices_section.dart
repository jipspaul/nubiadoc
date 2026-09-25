import 'package:flutter/material.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

/// Bloc « Cabinets partenaires » de la colonne latérale (design-v2, #7616) :
/// nombre de commandes reçues aujourd'hui par cabinet prescripteur, dérivé de
/// la file déjà chargée (aucun appel réseau supplémentaire).
///
/// Contrairement à la maquette, seuls les cabinets ayant au moins une
/// commande aujourd'hui apparaissent : la file ne connaît que les cabinets
/// dont elle a reçu une ordonnance, jamais un annuaire complet des cabinets
/// partenaires (qui n'existe pas côté front) — jamais de « 0 commande »
/// inventé (cf. #4916).
class PartnerPracticesSection extends StatelessWidget {
  const PartnerPracticesSection({super.key, required this.orders});

  final List<PharmacyOrder> orders;

  @override
  Widget build(BuildContext context) {
    final counts = _todaysCountsByPractice(orders, DateTime.now());
    if (counts.isEmpty) return const SizedBox.shrink();

    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final entries = counts.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        return byCount != 0 ? byCount : a.key.compareTo(b.key);
      });

    return DecoratedBox(
      key: const Key('partner_practices_section'),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: tokens.borderSubtle)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Icon(Icons.local_pharmacy,
                    size: 18, color: tokens.textTertiary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Cabinets partenaires',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          for (final entry in entries)
            ListRow(
              key: Key('partner_practice_${entry.key}'),
              title: entry.key,
              subtitle: entry.value >= 2
                  ? '${entry.value} commandes aujourd\'hui'
                  : '${entry.value} commande aujourd\'hui',
            ),
        ],
      ),
    );
  }
}

Map<String, int> _todaysCountsByPractice(
    List<PharmacyOrder> orders, DateTime now) {
  final counts = <String, int>{};
  for (final order in orders) {
    final practice = order.prescriberPractice;
    if (practice == null || practice.isEmpty) continue;
    if (!_isSameDay(order.createdAt, now)) continue;
    counts[practice] = (counts[practice] ?? 0) + 1;
  }
  return counts;
}

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
