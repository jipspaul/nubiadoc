import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'lab_stats_cubit.dart';

const double _kContentMaxWidth = 1120;

String _euros(int cents) => NubiaMoney.formatCents(cents);

/// Écran « Stats labos » (#7163, DP-F19.c) : coût labo / CA patient / marge
/// du mois courant, agrégés par laboratoire puis par praticien. Même
/// découpage `Scaffold` + corps rechargeable que `CabinetStatsPage`
/// (app_secretariat).
class LabStatsPage extends StatelessWidget {
  const LabStatsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('lab_stats_scaffold'),
      appBar: AppBar(
        title: const Text('Stats labos'),
        actions: [
          IconButton(
            tooltip: 'Actualiser',
            icon: const Icon(Icons.refresh),
            onPressed: () => context.read<LabStatsCubit>().load(),
          ),
        ],
      ),
      body: BlocBuilder<LabStatsCubit, LabStatsState>(
        builder: (context, state) {
          switch (state) {
            case LabStatsLoading():
              return const Center(
                key: Key('lab_stats_loading'),
                child: CircularProgressIndicator(),
              );
            case LabStatsError(:final message):
              return NubiaErrorWidget(
                key: const Key('lab_stats_error'),
                message: message,
                onRetry: () => context.read<LabStatsCubit>().load(),
              );
            case LabStatsLoaded(:final stats):
              return _LabStatsLoadedView(stats: stats);
          }
        },
      ),
    );
  }
}

class _LabStatsLoadedView extends StatelessWidget {
  const _LabStatsLoadedView({required this.stats});

  final LabStats stats;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final marginVariant = stats.totalMarginCents < 0
        ? MetricTileVariant.danger
        : MetricTileVariant.neutral;

    final metrics = <Widget>[
      MetricTile(
        key: const Key('lab_stats_total_cost'),
        icon: Icons.precision_manufacturing_outlined,
        value: _euros(stats.totalLabCostCents),
        label: 'Coût labo',
      ),
      MetricTile(
        key: const Key('lab_stats_total_revenue'),
        icon: Icons.euro_outlined,
        value: _euros(stats.totalPatientRevenueCents),
        label: 'CA patient',
      ),
      MetricTile(
        key: const Key('lab_stats_total_margin'),
        icon: Icons.trending_up_outlined,
        value: _euros(stats.totalMarginCents),
        label: 'Marge',
        variant: marginVariant,
      ),
    ];

    return SingleChildScrollView(
      key: const Key('lab_stats_loaded'),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _kContentMaxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Stats labos — ${stats.periodMonth}',
                style: textTheme.headlineSmall?.copyWith(color: cs.onSurface),
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  for (final metric in metrics)
                    SizedBox(width: 220, child: metric),
                ],
              ),
              const SizedBox(height: 24),
              Text('Par laboratoire', style: textTheme.titleMedium),
              const SizedBox(height: 12),
              if (stats.byLab.isEmpty)
                const NubiaEmptyState(
                  key: Key('lab_stats_by_lab_empty'),
                  icon: Icons.bar_chart_outlined,
                  title: 'Aucun bon valorisé sur la période',
                )
              else
                for (final lab in stats.byLab)
                  Padding(
                    key: Key('lab_stats_by_lab_${lab.labName}'),
                    padding: const EdgeInsets.only(bottom: 8),
                    child: NubiaCard(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              lab.labName,
                              style: textTheme.titleSmall,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${lab.orderCount} bons · '
                            '${_euros(lab.marginCents)} de marge',
                          ),
                        ],
                      ),
                    ),
                  ),
              const SizedBox(height: 24),
              Text('Par praticien', style: textTheme.titleMedium),
              const SizedBox(height: 12),
              if (stats.byPractitioner.isEmpty)
                const NubiaEmptyState(
                  key: Key('lab_stats_by_practitioner_empty'),
                  icon: Icons.bar_chart_outlined,
                  title: 'Aucun bon rattaché à un praticien sur la période',
                )
              else
                for (final practitioner in stats.byPractitioner)
                  Padding(
                    key: Key(
                      'lab_stats_by_practitioner_${practitioner.practitionerId}',
                    ),
                    padding: const EdgeInsets.only(bottom: 8),
                    child: NubiaCard(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              practitioner.practitionerName ?? 'Praticien',
                              style: textTheme.titleSmall,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${practitioner.orderCount} bons · '
                            '${_euros(practitioner.marginCents)} de marge',
                          ),
                        ],
                      ),
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}
