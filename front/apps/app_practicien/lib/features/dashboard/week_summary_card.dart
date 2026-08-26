import 'package:flutter/material.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

/// Carte « Cette semaine » (#5051, maquette design-v2 praticien) : aperçu
/// informationnel de l'activité hebdomadaire (lundi au vendredi) — trois
/// chiffres, aucune action de navigation (pas d'`onTap`).
class WeekSummaryCard extends StatelessWidget {
  const WeekSummaryCard({super.key, required this.summary});

  final ProDashboardSummary summary;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return NubiaCard(
      key: const Key('week_summary_card'),
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
                  'Cette semaine',
                  style: textTheme.titleMedium?.copyWith(color: cs.onSurface),
                ),
              ],
            ),
          ),
          ListRow(
            key: const Key('week_summary_acts_row'),
            title: 'Actes réalisés',
            subtitle: 'lundi au vendredi',
            trailing: StatusPill(
              label: '${summary.weeklyCompletedActs}',
              variant: StatusPillVariant.neutral,
            ),
          ),
          ListRow(
            key: const Key('week_summary_fees_row'),
            title: 'Honoraires',
            subtitle: 'encaissés et engagés',
            trailing: StatusPill(
              label: formatQuoteCents(summary.weeklyFeesCents),
              variant: StatusPillVariant.neutral,
              tabularNums: true,
            ),
          ),
          ListRow(
            key: const Key('week_summary_no_show_row'),
            title: 'Rendez-vous non honorés',
            subtitle: '${summary.weeklyNoShowCount} patient(s) concerné(s)',
            trailing: StatusPill(
              label: '${summary.weeklyNoShowCount}',
              variant: StatusPillVariant.warning,
            ),
            showDivider: false,
          ),
        ],
      ),
    );
  }
}
