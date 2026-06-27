import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'mes_rdv_bloc.dart';
import 'mes_rdv_event.dart';
import 'mes_rdv_state.dart';

/// Onglet "Mes RDV" — liste upcoming/historique + cancel/checkin.
class MesRdvPage extends StatelessWidget {
  const MesRdvPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) =>
          GetIt.instance<MesRdvBloc>()..add(const MesRdvLoadRequested()),
      child: const _MesRdvBody(),
    );
  }
}

// ---------------------------------------------------------------------------

class _MesRdvBody extends StatelessWidget {
  const _MesRdvBody();

  @override
  Widget build(BuildContext context) {
    return BlocListener<MesRdvBloc, MesRdvState>(
      listenWhen: (_, current) =>
          current is MesRdvLoaded && current.actionError != null,
      listener: (context, state) {
        if (state is MesRdvLoaded && state.actionError != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.actionError!)),
          );
        }
      },
      child: BlocBuilder<MesRdvBloc, MesRdvState>(
        builder: (context, state) {
          if (state is MesRdvInitial || state is MesRdvLoading) {
            return const Center(
              key: Key('mes_rdv_loading'),
              child: CircularProgressIndicator(),
            );
          }
          if (state is MesRdvError) {
            return NubiaErrorWidget(
              key: const Key('mes_rdv_error'),
              message: state.message,
              onRetry: () =>
                  context.read<MesRdvBloc>().add(const MesRdvLoadRequested()),
            );
          }
          if (state is MesRdvLoaded) {
            return _LoadedView(state: state);
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _LoadedView extends StatefulWidget {
  const _LoadedView({required this.state});
  final MesRdvLoaded state;

  @override
  State<_LoadedView> createState() => _LoadedViewState();
}

class _LoadedViewState extends State<_LoadedView> {
  bool _sortAsc = false;

  @override
  Widget build(BuildContext context) {
    int compare(Appointment a, Appointment b) => _sortAsc
        ? a.startsAt.compareTo(b.startsAt)
        : b.startsAt.compareTo(a.startsAt);

    final upcoming = [...widget.state.upcoming]..sort(compare);
    final history = [...widget.state.history]..sort(compare);

    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          if (widget.state.actionInProgress)
            const LinearProgressIndicator(key: Key('mes_rdv_action_progress')),
          Row(
            children: [
              const Expanded(
                child: TabBar(
                  tabs: [
                    Tab(text: 'À venir'),
                    Tab(text: 'Historique'),
                  ],
                ),
              ),
              IconButton(
                key: const Key('sort_button'),
                icon: const Icon(Icons.sort),
                tooltip:
                    _sortAsc ? 'Plus récent d\'abord' : 'Plus ancien d\'abord',
                onPressed: () => setState(() => _sortAsc = !_sortAsc),
              ),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _AppointmentList(
                  key: const Key('upcoming_list'),
                  appointments: upcoming,
                  emptyLabel: 'Aucun rendez-vous à venir',
                  isUpcoming: true,
                ),
                _AppointmentList(
                  key: const Key('history_list'),
                  appointments: history,
                  emptyLabel: 'Aucun historique',
                  isUpcoming: false,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _AppointmentList extends StatelessWidget {
  const _AppointmentList({
    super.key,
    required this.appointments,
    required this.emptyLabel,
    required this.isUpcoming,
  });

  final List<Appointment> appointments;
  final String emptyLabel;
  final bool isUpcoming;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () {
        context.read<MesRdvBloc>().add(const MesRdvLoadRequested());
        return Future<void>.delayed(Duration.zero);
      },
      child: appointments.isEmpty
          ? LayoutBuilder(
              builder: (_, constraints) => SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: SizedBox(
                  height: constraints.maxHeight,
                  child: NubiaEmptyState(
                    key: Key('empty_${isUpcoming ? 'upcoming' : 'history'}'),
                    icon: Icons.calendar_today_outlined,
                    title: emptyLabel,
                  ),
                ),
              ),
            )
          : ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: appointments.length,
              itemBuilder: (context, i) =>
                  _AppointmentCard(appointment: appointments[i]),
            ),
    );
  }
}

// ---------------------------------------------------------------------------

class _AppointmentCard extends StatelessWidget {
  const _AppointmentCard({required this.appointment});
  final Appointment appointment;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    appointment.motif,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                _StatusChip(status: appointment.status),
              ],
            ),
            const SizedBox(height: 6),
            _IconRow(
              icon: Icons.person_outline,
              label:
                  '${appointment.practitionerName} · ${appointment.practitionerSpecialty}',
            ),
            const SizedBox(height: 4),
            _IconRow(
              icon: Icons.calendar_today_outlined,
              label: _formatDateTime(appointment.startsAt),
              color: Theme.of(context).colorScheme.primary,
            ),
            if (appointment.cabinetAddress != null) ...[
              const SizedBox(height: 4),
              _IconRow(
                icon: Icons.location_on_outlined,
                label: appointment.cabinetAddress!,
              ),
            ],
            if (appointment.isUpcoming ||
                appointment.canCancel ||
                appointment.canModify) ...[
              const SizedBox(height: 12),
              _ActionButtons(appointment: appointment),
            ],
          ],
        ),
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    const weekdays = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
    const months = [
      'jan',
      'fév',
      'mar',
      'avr',
      'mai',
      'jun',
      'jul',
      'aoû',
      'sep',
      'oct',
      'nov',
      'déc',
    ];
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '${weekdays[dt.weekday - 1]} ${dt.day} ${months[dt.month - 1]} à $h:$m';
  }
}

// ---------------------------------------------------------------------------

class _ActionButtons extends StatelessWidget {
  const _ActionButtons({required this.appointment});
  final Appointment appointment;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (appointment.isUpcoming)
          FilledButton.icon(
            key: Key('checkin_${appointment.id}'),
            onPressed: () => context
                .read<MesRdvBloc>()
                .add(MesRdvCheckinRequested(appointment.id)),
            icon: const Icon(Icons.check_circle_outline, size: 16),
            label: const Text('Check-in'),
          ),
        if (appointment.canModify)
          OutlinedButton.icon(
            key: Key('modify_${appointment.id}'),
            onPressed: () => context.push('/appointments'),
            icon: const Icon(Icons.edit_calendar_outlined, size: 16),
            label: const Text('Modifier'),
          ),
        if (appointment.canCancel)
          OutlinedButton.icon(
            key: Key('cancel_${appointment.id}'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
              side: BorderSide(color: Theme.of(context).colorScheme.error),
            ),
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Annuler ce RDV ?'),
                  content: const Text('Cette action est irréversible.'),
                  actions: [
                    TextButton(
                      key: const Key('dialog_dismiss'),
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Annuler'),
                    ),
                    FilledButton(
                      key: const Key('dialog_confirm'),
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text('Confirmer'),
                    ),
                  ],
                ),
              );
              if (confirmed == true && context.mounted) {
                context
                    .read<MesRdvBloc>()
                    .add(MesRdvCancelRequested(appointment));
              }
            },
            icon: const Icon(Icons.cancel_outlined, size: 16),
            label: const Text('Annuler'),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _IconRow extends StatelessWidget {
  const _IconRow({required this.icon, required this.label, this.color});
  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final fg = color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: fg),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: fg),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final AppointmentStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = _style(context);
    return Chip(
      label: Text(label),
      labelStyle:
          Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
      backgroundColor: color.withValues(alpha: 0.12),
      side: BorderSide.none,
      padding: EdgeInsets.zero,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
  }

  (String, Color) _style(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return switch (status) {
      AppointmentStatus.confirmed => ('Confirmé', cs.primary),
      AppointmentStatus.requested => ('En attente', cs.secondary),
      AppointmentStatus.cancelled => ('Annulé', cs.error),
      AppointmentStatus.completed => ('Terminé', cs.onSurfaceVariant),
      AppointmentStatus.noShow => ('Absent', cs.error),
    };
  }
}
