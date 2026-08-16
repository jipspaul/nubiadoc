import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import 'dashboard_bloc.dart';
import 'dashboard_event.dart';
import 'dashboard_state.dart';
import 'widgets/cash_collection_card.dart';
import 'widgets/practitioners_today_card.dart';
import 'widgets/today_flow_card.dart';
import 'widgets/waiting_room_card.dart';
import 'widgets/week_occupancy_card.dart';
import 'widgets/work_queue_card.dart';

/// Tableau de bord opérationnel du secrétariat : sélectionné par
/// `DashboardPage._bodyBuilders` pour la destination [ProConfig.dashboardRoute].
class DashboardContent extends StatelessWidget {
  const DashboardContent({super.key, required this.session});

  final AuthSession session;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DashboardBloc, DashboardState>(
      builder: (context, state) {
        return switch (state) {
          DashboardInitial() ||
          DashboardLoading() =>
            const _DashboardSkeleton(),
          DashboardError(:final message) => NubiaErrorWidget(
              key: const Key('dashboard_error'),
              message: message,
              onRetry: () => context
                  .read<DashboardBloc>()
                  .add(const DashboardLoadRequested()),
            ),
          DashboardLoaded(
            :final todayCount,
            :final pendingCount,
            :final waitingCount,
            :final oldestWaitingRequestAgeDays,
            :final practitionersToday,
            :final dailyOccupancyRates,
            :final freeSlotsThisWeekCount,
            :final freeSlotsTomorrowMorningCount,
            :final todayFlow,
            :final pendingAppointmentsToday,
          ) =>
            _DashboardLoadedView(
              session: session,
              todayCount: todayCount,
              pendingCount: pendingCount,
              waitingCount: waitingCount,
              oldestWaitingRequestAgeDays: oldestWaitingRequestAgeDays,
              practitionersToday: practitionersToday,
              dailyOccupancyRates: dailyOccupancyRates,
              freeSlotsThisWeekCount: freeSlotsThisWeekCount,
              freeSlotsTomorrowMorningCount: freeSlotsTomorrowMorningCount,
              todayFlow: todayFlow,
              pendingAppointmentsToday: pendingAppointmentsToday,
            ),
        };
      },
    );
  }
}

/// Largeur maximale du contenu centré (poste de travail desktop).
const double _kContentMaxWidth = 1120;

/// Formate une date en clair, ex. « Mardi 11 août » — même formule que
/// `_dayLabel` dans `app_practicien/agenda_page.dart` (pas de dépendance
/// `intl` dans ce package).
String _formatDayLabel(DateTime date) {
  const days = [
    'Lundi',
    'Mardi',
    'Mercredi',
    'Jeudi',
    'Vendredi',
    'Samedi',
    'Dimanche',
  ];
  const months = [
    'janvier',
    'février',
    'mars',
    'avril',
    'mai',
    'juin',
    'juillet',
    'août',
    'septembre',
    'octobre',
    'novembre',
    'décembre',
  ];
  return '${days[date.weekday - 1]} ${date.day} ${months[date.month - 1]}';
}

/// Vue chargée du tableau de bord opérationnel : en-tête + tuiles de flux du
/// jour ([MetricTile]) + cartes récapitulatives. Purement administratif —
/// aucune donnée clinique n'est affichée (cloisonnement secrétariat).
class _DashboardLoadedView extends StatelessWidget {
  const _DashboardLoadedView({
    required this.session,
    required this.todayCount,
    required this.pendingCount,
    required this.waitingCount,
    this.oldestWaitingRequestAgeDays,
    required this.practitionersToday,
    required this.dailyOccupancyRates,
    required this.freeSlotsThisWeekCount,
    required this.freeSlotsTomorrowMorningCount,
    required this.todayFlow,
    required this.pendingAppointmentsToday,
  });

  final AuthSession session;
  final int todayCount;
  final int pendingCount;
  final int waitingCount;
  final int? oldestWaitingRequestAgeDays;
  final List<PractitionerToday> practitionersToday;
  final List<double> dailyOccupancyRates;
  final int freeSlotsThisWeekCount;
  final int freeSlotsTomorrowMorningCount;
  final List<AgendaEntry> todayFlow;
  final List<AgendaEntry> pendingAppointmentsToday;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    final metrics = <Widget>[
      MetricTile(
        key: const Key('stat_rdv_today'),
        icon: Icons.calendar_today_outlined,
        value: '$todayCount',
        label: "RDV aujourd'hui",
      ),
      MetricTile(
        key: const Key('stat_pending'),
        icon: Icons.pending_actions_outlined,
        value: '$pendingCount',
        label: 'RDV à confirmer',
        variant: MetricTileVariant.warning,
      ),
      MetricTile(
        key: const Key('stat_waiting_list'),
        icon: Icons.format_list_bulleted_outlined,
        value: '$waitingCount',
        label: 'Demandes de créneau',
      ),
    ];

    // #5374 : sous-titre récapitulatif « <jour date> · <secrétaire> · <N>
    // rendez-vous, <M> restants » — restants = RDV du jour non terminés,
    // dérivés du flux du jour déjà chargé (aucun appel réseau ajouté).
    final remainingCount = todayFlow.where((e) => !e.isDone).length;
    final secretaryName = session.displayName ?? 'Secrétariat';
    final subtitle = '${_formatDayLabel(DateTime.now())} · $secretaryName · '
        '$todayCount rendez-vous, $remainingCount restants';

    return SingleChildScrollView(
      key: const Key('dashboard_loaded'),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _kContentMaxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Ma journée',
                style: textTheme.headlineSmall?.copyWith(color: cs.onSurface),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                key: const Key('dashboard_subtitle'),
                style: textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              Wrap(
                key: const Key('dashboard_stats_row'),
                spacing: 16,
                runSpacing: 16,
                children: [
                  for (final tile in metrics) SizedBox(width: 220, child: tile),
                ],
              ),
              const SizedBox(height: 28),
              LayoutBuilder(
                builder: (context, constraints) {
                  final twoColumns = constraints.maxWidth >= 720;
                  final leftColumn = TodayFlowCard(entries: todayFlow);
                  final rightColumn = [
                    WorkQueueCard(
                      waitingCount: waitingCount,
                      oldestWaitingRequestAgeDays: oldestWaitingRequestAgeDays,
                      pendingAppointmentsToday: pendingAppointmentsToday,
                    ),
                    const WaitingRoomCard(),
                    const CashCollectionCard(),
                    WeekOccupancyCard(
                      dailyOccupancyRates: dailyOccupancyRates,
                      freeSlotsThisWeekCount: freeSlotsThisWeekCount,
                      freeSlotsTomorrowMorningCount:
                          freeSlotsTomorrowMorningCount,
                    ),
                    PractitionersTodayCard(
                      practitioners: practitionersToday,
                    ),
                  ];
                  if (!twoColumns) {
                    return Column(
                      children: [
                        leftColumn,
                        for (final c in rightColumn) ...[
                          const SizedBox(height: 16),
                          c,
                        ],
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: leftColumn),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          children: [
                            for (final c in rightColumn) ...[
                              c,
                              if (c != rightColumn.last)
                                const SizedBox(height: 16),
                            ],
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Skeleton de chargement du tableau de bord (tuiles + cartes).
class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      key: const Key('dashboard_loading'),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _kContentMaxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              NubiaSkeletonLoader(width: 220, height: 28),
              SizedBox(height: 24),
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  SizedBox(
                    width: 220,
                    child: NubiaSkeletonLoader(height: 118, borderRadius: 12),
                  ),
                  SizedBox(
                    width: 220,
                    child: NubiaSkeletonLoader(height: 118, borderRadius: 12),
                  ),
                  SizedBox(
                    width: 220,
                    child: NubiaSkeletonLoader(height: 118, borderRadius: 12),
                  ),
                ],
              ),
              SizedBox(height: 28),
              NubiaSkeletonLoader(height: 120, borderRadius: 12),
            ],
          ),
        ),
      ),
    );
  }
}
