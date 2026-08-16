import 'package:flutter/material.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

/// Carte « Occupation de la semaine » (#5384) : pied de carte affichant le
/// nombre de créneaux réellement libres de la semaine, dont ceux de demain
/// matin. Les compteurs sont dérivés côté [DashboardBloc] en rapprochant
/// `/bookable-slots` du planning réel déjà chargé (cf. note #5 maquette).
class WeekOccupancyCard extends StatelessWidget {
  const WeekOccupancyCard({
    super.key,
    required this.freeSlotsThisWeekCount,
    required this.freeSlotsTomorrowMorningCount,
  });

  final int freeSlotsThisWeekCount;
  final int freeSlotsTomorrowMorningCount;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final textTheme = Theme.of(context).textTheme;

    return NubiaCard(
      key: const Key('week_occupancy_card'),
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              children: [
                Icon(
                  Icons.insights_outlined,
                  size: 20,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text(
                  'Occupation de la semaine',
                  style: textTheme.titleMedium?.copyWith(color: cs.onSurface),
                ),
              ],
            ),
          ),
          Divider(height: 1, thickness: 1, color: tokens.borderSubtle),
          ListRow(
            key: const Key('week_free_slots_row'),
            title: 'Créneaux libres cette semaine',
            subtitle: 'dont $freeSlotsTomorrowMorningCount demain matin',
            trailing: Text(
              '$freeSlotsThisWeekCount',
              style: textTheme.titleLarge?.copyWith(
                color: cs.onSurface,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            showDivider: false,
          ),
        ],
      ),
    );
  }
}
