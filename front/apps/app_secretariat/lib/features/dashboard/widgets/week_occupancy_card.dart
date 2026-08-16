import 'package:flutter/material.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

/// Libellés des barres, dans l'ordre `dailyOccupancyRates` (Lun→Sam, cf.
/// maquette — le cabinet est fermé le dimanche, non représenté).
const _kDayLabels = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam'];

/// Hauteur maximale (px) d'une barre pleine (taux = 1.0).
const _kBarMaxHeight = 56.0;

/// Carte « Occupation de la semaine » : histogramme du taux d'occupation par
/// jour (Lun→Sam, #5383) — dérivé de l'agenda déjà chargé par
/// [DashboardBloc], barre du jour courant mise en avant — et, en pied, le
/// nombre de créneaux réellement libres de la semaine, dont ceux de demain
/// matin (#5384), rapprochés du planning réel (cf. note #5 maquette).
class WeekOccupancyCard extends StatelessWidget {
  const WeekOccupancyCard({
    super.key,
    required this.dailyOccupancyRates,
    required this.freeSlotsThisWeekCount,
    required this.freeSlotsTomorrowMorningCount,
  });

  /// Taux d'occupation (0.0 à 1.0) du lundi au samedi, dans cet ordre —
  /// 6 valeurs, une par barre de l'histogramme.
  final List<double> dailyOccupancyRates;
  final int freeSlotsThisWeekCount;
  final int freeSlotsTomorrowMorningCount;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final textTheme = Theme.of(context).textTheme;
    // ISO 8601 : 1 = lundi ... 6 = samedi, 7 = dimanche (jamais mis en
    // avant, aucune barre ne le représente).
    final todayIndex = DateTime.now().weekday - 1;

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
          Padding(
            key: const Key('week_occupancy_bars'),
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < _kDayLabels.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(
                    child: _OccupancyBar(
                      label: _kDayLabels[i],
                      rate: i < dailyOccupancyRates.length
                          ? dailyOccupancyRates[i]
                          : 0.0,
                      isToday: i == todayIndex,
                    ),
                  ),
                ],
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

/// Une barre de l'histogramme + son étiquette de jour. `.now` de la
/// maquette (barre du jour courant en émeraude foncé `--brand700`) → autres
/// barres en émeraude clair `--brand200`.
class _OccupancyBar extends StatelessWidget {
  const _OccupancyBar({
    required this.label,
    required this.rate,
    required this.isToday,
  });

  final String label;
  final double rate;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final height =
        (_kBarMaxHeight * rate.clamp(0.0, 1.0)).clamp(4.0, _kBarMaxHeight);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: _kBarMaxHeight,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              height: height,
              decoration: BoxDecoration(
                color: isToday ? NubiaColors.brand700 : NubiaColors.brand200,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(4),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: textTheme.labelSmall?.copyWith(
            color: isToday ? cs.onSurface : cs.onSurfaceVariant,
            fontWeight: isToday ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ],
    );
  }
}
