import 'package:flutter/material.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

/// Agrégats du bandeau KPI de la salle d'attente (#5173) : nombre en
/// attente, attente moyenne et nombre au-delà de 30 min — tout dérivé de
/// `WaitingRoomLoaded.entries`, aucun appel réseau supplémentaire.
class WaitingRoomKpis {
  const WaitingRoomKpis({
    required this.waitingCount,
    required this.averageWaitMinutes,
    required this.overThirtyCount,
  });

  factory WaitingRoomKpis.fromEntries(List<WaitingRoomEntry> entries) {
    if (entries.isEmpty) {
      return const WaitingRoomKpis(
        waitingCount: 0,
        averageWaitMinutes: 0,
        overThirtyCount: 0,
      );
    }
    final waitMinutes = entries.map((e) => e.waitSoFar.inMinutes).toList();
    final averageWaitMinutes =
        (waitMinutes.reduce((a, b) => a + b) / waitMinutes.length).round();
    final overThirtyCount = waitMinutes.where((m) => m >= 30).length;
    return WaitingRoomKpis(
      waitingCount: entries.length,
      averageWaitMinutes: averageWaitMinutes,
      overThirtyCount: overThirtyCount,
    );
  }

  final int waitingCount;
  final int averageWaitMinutes;
  final int overThirtyCount;
}

/// Bandeau de 3 indicateurs dans la barre d'outils de la salle d'attente :
/// en attente, attente moyenne, au-delà de 30 min (rouge dès qu'il y en a).
class WaitingRoomKpiBar extends StatelessWidget {
  const WaitingRoomKpiBar({super.key, required this.entries});

  final List<WaitingRoomEntry> entries;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final kpis = WaitingRoomKpis.fromEntries(entries);

    return Row(
      children: [
        Expanded(
          child: _WaitingRoomKpiStat(
            key: const Key('waiting_room_kpi_count'),
            value: '${kpis.waitingCount}',
            label: 'en attente',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _WaitingRoomKpiStat(
            key: const Key('waiting_room_kpi_average'),
            value: '${kpis.averageWaitMinutes} min',
            label: 'attente moyenne',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _WaitingRoomKpiStat(
            key: const Key('waiting_room_kpi_over_thirty'),
            value: '${kpis.overThirtyCount}',
            label: 'au-delà de 30 min',
            valueColor: kpis.overThirtyCount > 0 ? tokens.dangerFg : null,
          ),
        ),
      ],
    );
  }
}

/// Une valeur (chiffres tabulaires) et son libellé, empilés — un indicateur
/// du [WaitingRoomKpiBar].
class _WaitingRoomKpiStat extends StatelessWidget {
  const _WaitingRoomKpiStat({
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
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            color: valueColor ?? theme.colorScheme.onSurface,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: tokens.textTertiary,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
