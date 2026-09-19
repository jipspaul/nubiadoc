import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import 'kpi_tiles_cubit.dart';

/// Bandeau de quatre tuiles KPI en tête du dashboard praticien (#7188,
/// DP-F10.c) : CA du mois vs objectif (jauge), RDV du jour, rappels en
/// attente, taux d'occupation. Sélecteur de centre si le praticien exerce
/// dans plusieurs cabinets (`PractitionerKpis.byCabinet`, `GET /v1/me/kpis`,
/// #7189).
class KpiTilesRow extends StatelessWidget {
  const KpiTilesRow({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<KpiTilesCubit, KpiTilesState>(
      builder: (context, state) {
        return switch (state) {
          KpiTilesLoading() =>
            const _KpiTilesSkeleton(key: Key('kpi_tiles_loading')),
          KpiTilesError(:final message) => NubiaInlineError(
              key: const Key('kpi_tiles_error'),
              message: message,
              onRetry: () => context.read<KpiTilesCubit>().load(),
            ),
          KpiTilesLoaded() =>
            _KpiTilesContent(key: const Key('kpi_tiles_loaded'), state: state),
        };
      },
    );
  }
}

class _KpiTilesContent extends StatelessWidget {
  const _KpiTilesContent({super.key, required this.state});

  final KpiTilesLoaded state;

  @override
  Widget build(BuildContext context) {
    final displayed = state.displayed;
    final tiles = <Widget>[
      _RevenueGaugeTile(
        key: const Key('kpi_tile_revenue'),
        billedMonthCents: displayed.month.billedCents,
        objectiveTargetCents: displayed.objectiveTargetCents,
        objectiveAchievedPct: displayed.objectiveAchievedPct,
      ),
      MetricTile(
        key: const Key('kpi_tile_appointments'),
        icon: Icons.calendar_today_outlined,
        value: '${displayed.appointmentsToday}',
        label: "RDV aujourd'hui",
      ),
      MetricTile(
        key: const Key('kpi_tile_reminders'),
        icon: Icons.notifications_active_outlined,
        value: '${displayed.pendingReminders}',
        label: 'Rappels en attente',
        variant: displayed.pendingReminders > 0
            ? MetricTileVariant.warning
            : MetricTileVariant.neutral,
      ),
      MetricTile(
        key: const Key('kpi_tile_occupancy'),
        icon: Icons.event_available_outlined,
        value: displayed.occupancyRate != null
            ? '${(displayed.occupancyRate! * 100).round()}%'
            : '—',
        label: "Occupation de la semaine",
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.kpis.byCabinet.length > 1) ...[
          _CabinetSelector(state: state),
          const SizedBox(height: 12),
        ],
        Wrap(
          key: const Key('kpi_tiles_wrap'),
          spacing: 16,
          runSpacing: 16,
          children: [
            for (final tile in tiles) SizedBox(width: 220, child: tile),
          ],
        ),
      ],
    );
  }
}

/// Sélecteur de centre (#7188) : bascule l'affichage des tuiles entre
/// l'agrégat « tous les cabinets » et un cabinet précis, pour les praticiens
/// qui exercent dans plusieurs cabinets. Purement local à l'affichage — ne
/// change pas le contexte cabinet de la session (`select-context`).
class _CabinetSelector extends StatelessWidget {
  const _CabinetSelector({required this.state});

  final KpiTilesLoaded state;

  @override
  Widget build(BuildContext context) {
    final items = <NubiaSelectItem<String?>>[
      const NubiaSelectItem<String?>(value: null, label: 'Tous les cabinets'),
      for (final cabinet in state.kpis.byCabinet)
        NubiaSelectItem<String?>(
          value: cabinet.cabinetId,
          label: cabinet.cabinetName ?? 'Cabinet',
        ),
    ];
    return SizedBox(
      key: const Key('kpi_cabinet_selector'),
      width: 280,
      child: NubiaSelect<String?>(
        items: items,
        value: state.selectedCabinetId,
        label: 'Centre',
        onChanged: (value) =>
            context.read<KpiTilesCubit>().selectCabinet(value),
      ),
    );
  }
}

/// Tuile CA du mois avec jauge de progression vers l'objectif fixé par le
/// manager (#7188/#7189). Sans objectif défini, affiche le CA seul plutôt
/// qu'une jauge à 0 % trompeuse.
class _RevenueGaugeTile extends StatelessWidget {
  const _RevenueGaugeTile({
    super.key,
    required this.billedMonthCents,
    required this.objectiveTargetCents,
    required this.objectiveAchievedPct,
  });

  final int billedMonthCents;
  final int? objectiveTargetCents;
  final double? objectiveAchievedPct;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final textTheme = Theme.of(context).textTheme;

    final target = objectiveTargetCents;
    final pct = objectiveAchievedPct;

    final Color gaugeColor;
    if (pct == null) {
      gaugeColor = cs.primary;
    } else if (pct >= 1) {
      gaugeColor = tokens.successFg;
    } else if (pct >= 0.5) {
      gaugeColor = tokens.warningFg;
    } else {
      gaugeColor = tokens.dangerFg;
    }

    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(color: tokens.borderSubtle),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: NubiaColors.n900.withValues(alpha: 0.05),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Material(
        color: cs.surface,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: tokens.primarySubtleBg,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child:
                        Icon(Icons.trending_up, size: 20, color: cs.primary),
                  ),
                  const Spacer(),
                  if (pct != null)
                    Text(
                      '${(pct * 100).round()}%',
                      key: const Key('kpi_revenue_pct'),
                      style: textTheme.labelLarge?.copyWith(color: gaugeColor),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  formatQuoteCents(billedMonthCents),
                  maxLines: 1,
                  style: textTheme.headlineSmall?.copyWith(
                    color: cs.onSurface,
                    fontFeatures: tabularFigures,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                target != null
                    ? 'CA du mois · objectif ${formatQuoteCents(target)}'
                    : 'CA du mois · objectif non défini',
                style:
                    textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  key: const Key('kpi_revenue_gauge'),
                  value: target != null ? (pct ?? 0).clamp(0.0, 1.0) : 0,
                  minHeight: 6,
                  backgroundColor: tokens.borderSubtle,
                  color: gaugeColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Squelette de chargement : même largeur/hauteur que les tuiles réelles,
/// même agencement `Wrap` que [_KpiTilesContent].
class _KpiTilesSkeleton extends StatelessWidget {
  const _KpiTilesSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: [
        for (int i = 0; i < 4; i++)
          const SizedBox(
            width: 220,
            child: NubiaSkeletonLoader(
              width: 220,
              height: 108,
              borderRadius: 12,
            ),
          ),
      ],
    );
  }
}
