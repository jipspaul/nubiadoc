import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'create_maintenance_ticket_dialog.dart';
import 'equipment_detail_page.dart';
import 'maintenance_bloc.dart';
import 'maintenance_event.dart';
import 'maintenance_state.dart';

const _statusLabels = {
  'open': 'Ouvert',
  'in_progress': 'En cours',
  'resolved': 'Résolu',
  'cancelled': 'Annulé',
};

const _statusVariants = {
  'open': StatusPillVariant.warning,
  'in_progress': StatusPillVariant.progress,
  'resolved': StatusPillVariant.success,
  'cancelled': StatusPillVariant.neutral,
};

const _priorityLabels = {
  'low': 'Basse',
  'medium': 'Moyenne',
  'high': 'Haute',
  'urgent': 'Urgente',
};

/// Écran « Maintenance » du cabinet (#7166/#7167, DP-F18) : compteurs, liste
/// des équipements et des tickets, création de ticket avec photo (caméra).
class MaintenancePage extends StatefulWidget {
  const MaintenancePage({super.key});

  @override
  State<MaintenancePage> createState() => _MaintenancePageState();
}

class _MaintenancePageState extends State<MaintenancePage> {
  String? _statusFilter;

  Future<void> _onCreate(
    BuildContext context,
    List<Equipment> equipmentOptions,
  ) async {
    final bloc = context.read<MaintenanceBloc>();
    final result = await showCreateMaintenanceTicketDialog(
      context,
      equipmentOptions: equipmentOptions,
    );
    if (result == null) return;
    bloc.add(MaintenanceTicketCreateRequested(
      equipmentId: result.equipmentId,
      title: result.title,
      description: result.description,
      priority: result.priority,
      assignedToEmail: result.assignedToEmail,
      photo: result.photo,
    ));
  }

  void _onOpenEquipment(
    BuildContext context,
    Equipment equipment,
    List<MaintenanceTicket> tickets,
  ) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => EquipmentDetailPage(
        equipment: equipment,
        tickets: tickets
            .where((ticket) => ticket.equipmentId == equipment.id)
            .toList(),
      ),
    ));
  }

  List<MaintenanceTicket> _filterTickets(List<MaintenanceTicket> tickets) {
    final status = _statusFilter;
    if (status == null) return tickets;
    return tickets.where((ticket) => ticket.status == status).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Maintenance'),
        actions: [
          IconButton(
            tooltip: 'Actualiser',
            icon: const Icon(Icons.refresh),
            onPressed: () => context
                .read<MaintenanceBloc>()
                .add(const MaintenanceLoadRequested()),
          ),
        ],
      ),
      body: BlocConsumer<MaintenanceBloc, MaintenanceState>(
        listenWhen: (previous, current) =>
            current is MaintenanceLoaded && current.createError != null,
        listener: (context, state) {
          final message = (state as MaintenanceLoaded).createError;
          if (message != null) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(message)));
          }
        },
        builder: (context, state) {
          switch (state) {
            case MaintenanceLoading():
              return const _MaintenanceLoadingSkeleton();
            case MaintenanceError(:final message):
              return NubiaErrorWidget(
                key: const Key('maintenance_error'),
                message: message,
                onRetry: () => context
                    .read<MaintenanceBloc>()
                    .add(const MaintenanceLoadRequested()),
              );
            case MaintenanceLoaded(
                :final stats,
                :final tickets,
                :final equipment,
              ):
              final equipmentById = {
                for (final item in equipment) item.id: item,
              };
              final filtered = _filterTickets(tickets);
              return ListView(
                key: const Key('maintenance_list'),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                children: [
                  _MaintenanceKpiBar(stats: stats),
                  const SizedBox(height: 20),
                  _StatusFacetBar(
                    tickets: tickets,
                    selected: _statusFilter,
                    onSelected: (status) => setState(
                      () => _statusFilter =
                          _statusFilter == status ? null : status,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text('Tickets', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  if (filtered.isEmpty)
                    const NubiaEmptyState(
                      key: Key('maintenance_tickets_empty'),
                      icon: Icons.build_outlined,
                      title: 'Aucun ticket',
                      subtitle:
                          'Créez un ticket pour signaler un équipement en panne.',
                    )
                  else
                    for (final ticket in filtered) ...[
                      _TicketCard(
                        key: Key('maintenance_ticket_${ticket.id}'),
                        ticket: ticket,
                        equipmentLabel: ticket.equipmentId != null
                            ? equipmentById[ticket.equipmentId]?.label
                            : null,
                      ),
                      const SizedBox(height: 8),
                    ],
                  const SizedBox(height: 24),
                  Text('Équipements',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  if (equipment.isEmpty)
                    const NubiaEmptyState(
                      key: Key('maintenance_equipment_empty'),
                      icon: Icons.handyman_outlined,
                      title: 'Aucun équipement',
                      subtitle:
                          "Aucun équipement enregistré dans l'inventaire du cabinet.",
                    )
                  else
                    for (final item in equipment) ...[
                      _EquipmentCard(
                        key: Key('equipment_${item.id}'),
                        equipment: item,
                        onTap: () => _onOpenEquipment(context, item, tickets),
                      ),
                      const SizedBox(height: 8),
                    ],
                ],
              );
          }
        },
      ),
      floatingActionButton: BlocBuilder<MaintenanceBloc, MaintenanceState>(
        builder: (context, state) {
          if (state is! MaintenanceLoaded) return const SizedBox.shrink();
          return FloatingActionButton.extended(
            key: const Key('maintenance_new_ticket_fab'),
            onPressed:
                state.creating ? null : () => _onCreate(context, state.equipment),
            icon: const Icon(Icons.add),
            label: const Text('Nouveau ticket'),
          );
        },
      ),
    );
  }
}

class _MaintenanceLoadingSkeleton extends StatelessWidget {
  const _MaintenanceLoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      key: Key('maintenance_loading'),
      padding: EdgeInsets.all(16),
      child: Column(
        children: [
          NubiaSkeletonLoader(height: 64, width: double.infinity),
          SizedBox(height: 16),
          NubiaSkeletonLoader(height: 88, width: double.infinity),
          SizedBox(height: 12),
          NubiaSkeletonLoader(height: 88, width: double.infinity),
        ],
      ),
    );
  }
}

/// Rangée de 3 compteurs (#7167 : `GET /v1/cabinet/maintenance/stats`) —
/// chaque enfant est `Expanded` pour ne jamais déborder la largeur de
/// l'écran, quelle que soit la longueur des libellés.
class _MaintenanceKpiBar extends StatelessWidget {
  const _MaintenanceKpiBar({required this.stats});

  final MaintenanceStats stats;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    return Row(
      key: const Key('maintenance_kpi_bar'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _KpiStat(
            key: const Key('maintenance_kpi_open_tickets'),
            value: '${stats.openTickets}',
            label: 'tickets ouverts',
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _KpiStat(
            key: const Key('maintenance_kpi_planned_checks'),
            value: '${stats.plannedChecks}',
            label: 'contrôles planifiés',
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _KpiStat(
            key: const Key('maintenance_kpi_overdue_checks'),
            value: '${stats.overdueChecks}',
            label: 'contrôles en retard',
            valueColor: stats.overdueChecks > 0 ? tokens.dangerFg : null,
          ),
        ),
      ],
    );
  }
}

class _KpiStat extends StatelessWidget {
  const _KpiStat({
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
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return NubiaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: valueColor ?? cs.onSurface,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: textTheme.bodySmall?.copyWith(color: NubiaColors.n500),
          ),
        ],
      ),
    );
  }
}

/// Facettes de statut au-dessus de la liste des tickets (« Tous » +
/// compteur par statut présent) — tap bascule le filtre.
class _StatusFacetBar extends StatelessWidget {
  const _StatusFacetBar({
    required this.tickets,
    required this.selected,
    required this.onSelected,
  });

  final List<MaintenanceTicket> tickets;
  final String? selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final status in _statusLabels.keys)
            if (tickets.any((ticket) => ticket.status == status)) ...[
              ChoiceChip(
                key: Key('maintenance_facet_$status'),
                label: Text(
                  '${_statusLabels[status]} '
                  '${tickets.where((t) => t.status == status).length}',
                ),
                selected: selected == status,
                onSelected: (_) => onSelected(status),
              ),
              const SizedBox(width: 8),
            ],
        ],
      ),
    );
  }
}

class _TicketCard extends StatelessWidget {
  const _TicketCard({
    super.key,
    required this.ticket,
    required this.equipmentLabel,
  });

  final MaintenanceTicket ticket;
  final String? equipmentLabel;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return NubiaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  ticket.title,
                  style: textTheme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              StatusPill(
                label: _statusLabels[ticket.status] ?? ticket.status,
                variant: _statusVariants[ticket.status] ?? StatusPillVariant.neutral,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            [
              'Priorité ${_priorityLabels[ticket.priority] ?? ticket.priority}',
              if (equipmentLabel != null) equipmentLabel!,
            ].join(' · '),
            style: textTheme.bodySmall?.copyWith(color: NubiaColors.n500),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (ticket.description != null) ...[
            const SizedBox(height: 6),
            Text(
              ticket.description!,
              style: textTheme.bodyMedium,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

class _EquipmentCard extends StatelessWidget {
  const _EquipmentCard({super.key, required this.equipment, required this.onTap});

  final Equipment equipment;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return NubiaCard(
      state: NubiaCardState.interactive,
      onTap: onTap,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  equipment.label,
                  style: textTheme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  [equipment.category, equipment.room]
                      .whereType<String>()
                      .join(' · '),
                  style: textTheme.bodySmall?.copyWith(color: NubiaColors.n500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right),
        ],
      ),
    );
  }
}
