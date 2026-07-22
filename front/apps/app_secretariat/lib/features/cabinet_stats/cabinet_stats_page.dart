import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'cabinet_stats_bloc.dart';
import 'cabinet_stats_event.dart';
import 'cabinet_stats_state.dart';

/// Page complète (route dédiée) — `Scaffold` + `AppBar` autour de
/// [CabinetStatsBody], même découpage que `WaitingRoomBody`/`WaitingRoomPage`.
class CabinetStatsPage extends StatelessWidget {
  const CabinetStatsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('cabinet_stats_scaffold'),
      appBar: AppBar(
        title: const Text('Pilotage du cabinet'),
        actions: [
          IconButton(
            tooltip: 'Actualiser',
            icon: const Icon(Icons.refresh),
            onPressed: () => context
                .read<CabinetStatsBloc>()
                .add(const CabinetStatsLoadRequested()),
          ),
        ],
      ),
      body: const CabinetStatsBody(),
    );
  }
}

const double _kContentMaxWidth = 1120;

String _euros(int cents) => '${(cents / 100).toStringAsFixed(2)} €';

/// Une ligne d'activité agrégée par praticien (somme des actes CCAM).
class _PractitionerActivity {
  _PractitionerActivity(this.practitionerId, this.practitionerName);

  final String practitionerId;
  final String practitionerName;
  int actCount = 0;
  int totalAmountCents = 0;
}

List<_PractitionerActivity> _groupByPractitioner(
  List<CabinetActivityStat> rows,
) {
  final byId = <String, _PractitionerActivity>{};
  for (final row in rows) {
    final entry = byId.putIfAbsent(
      row.practitionerId,
      () => _PractitionerActivity(
        row.practitionerId,
        row.practitionerName ?? 'Praticien',
      ),
    );
    entry.actCount += row.actCount;
    entry.totalAmountCents += row.totalAmountCents;
  }
  return byId.values.toList()
    ..sort((a, b) => b.totalAmountCents.compareTo(a.totalAmountCents));
}

/// Corps réutilisable de l'écran de pilotage cabinet (#4153) — embarquable
/// dans un onglet `ProShell` (comme `WaitingRoomBody`) ou une page dédiée.
class CabinetStatsBody extends StatefulWidget {
  const CabinetStatsBody({super.key});

  @override
  State<CabinetStatsBody> createState() => _CabinetStatsBodyState();
}

class _CabinetStatsBodyState extends State<CabinetStatsBody> {
  @override
  void initState() {
    super.initState();
    context.read<CabinetStatsBloc>().add(const CabinetStatsLoadRequested());
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CabinetStatsBloc, CabinetStatsState>(
      builder: (context, state) {
        switch (state) {
          case CabinetStatsLoading():
            return const Center(
              key: Key('cabinet_stats_loading'),
              child: CircularProgressIndicator(),
            );
          case CabinetStatsError(:final message):
            return NubiaErrorWidget(
              key: const Key('cabinet_stats_error'),
              message: message,
              onRetry: () => context
                  .read<CabinetStatsBloc>()
                  .add(const CabinetStatsLoadRequested()),
            );
          case CabinetStatsLoaded(:final activity, :final billing):
            return _CabinetStatsLoadedView(
                activity: activity, billing: billing);
        }
      },
    );
  }
}

class _CabinetStatsLoadedView extends StatelessWidget {
  const _CabinetStatsLoadedView(
      {required this.activity, required this.billing});

  final List<CabinetActivityStat> activity;
  final CabinetBillingStats billing;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final byPractitioner = _groupByPractitioner(activity);
    final conversionLabel = billing.conversionRate == null
        ? '—'
        : '${(billing.conversionRate! * 100).toStringAsFixed(0)} %';

    final metrics = <Widget>[
      MetricTile(
        key: const Key('stat_revenue_collected'),
        icon: Icons.euro_outlined,
        value: _euros(billing.revenueCollectedCents),
        label: 'CA encaissé',
      ),
      MetricTile(
        key: const Key('stat_outstanding'),
        icon: Icons.hourglass_top_outlined,
        value: _euros(billing.outstandingCents),
        label: 'Reste à encaisser',
        variant: MetricTileVariant.warning,
      ),
      MetricTile(
        key: const Key('stat_conversion_rate'),
        icon: Icons.trending_up_outlined,
        value: conversionLabel,
        label: 'Taux de transformation',
      ),
      MetricTile(
        key: const Key('stat_signed_sent'),
        icon: Icons.fact_check_outlined,
        value: '${billing.signedCount} / ${billing.sentTotal}',
        label: 'Devis signés / envoyés',
      ),
    ];

    return SingleChildScrollView(
      key: const Key('cabinet_stats_loaded'),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _kContentMaxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Pilotage du cabinet',
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
              Text('Activité par praticien', style: textTheme.titleMedium),
              const SizedBox(height: 12),
              if (byPractitioner.isEmpty)
                const NubiaEmptyState(
                  key: Key('cabinet_stats_activity_empty'),
                  icon: Icons.bar_chart_outlined,
                  title: 'Aucune activité sur la période',
                )
              else
                for (final entry in byPractitioner)
                  Padding(
                    key: Key('practitioner_activity_${entry.practitionerId}'),
                    padding: const EdgeInsets.only(bottom: 8),
                    child: NubiaCard(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(entry.practitionerName,
                              style: textTheme.titleSmall),
                          Text(
                            '${entry.actCount} actes · ${_euros(entry.totalAmountCents)}',
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
