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
  // #3801 : « À venir » et « Historique » veulent des ordres par défaut
  // opposés (le prochain RDV en tête vs le plus récent passé en tête) — un
  // seul état de tri partagé appliquait l'ordre pensé pour l'historique
  // (DESC) à l'onglet à venir, reléguant le RDV imminent en bas de liste.
  bool _upcomingSortAsc = true;
  bool _historySortAsc = false;
  int _selectedIndex = 0;

  bool get _currentSortAsc =>
      _selectedIndex == 0 ? _upcomingSortAsc : _historySortAsc;

  void _toggleSort() => setState(() {
        if (_selectedIndex == 0) {
          _upcomingSortAsc = !_upcomingSortAsc;
        } else {
          _historySortAsc = !_historySortAsc;
        }
      });

  @override
  Widget build(BuildContext context) {
    int compareUpcoming(Appointment a, Appointment b) => _upcomingSortAsc
        ? a.startsAt.compareTo(b.startsAt)
        : b.startsAt.compareTo(a.startsAt);
    int compareHistory(Appointment a, Appointment b) => _historySortAsc
        ? a.startsAt.compareTo(b.startsAt)
        : b.startsAt.compareTo(a.startsAt);

    final upcoming = [...widget.state.upcoming]..sort(compareUpcoming);
    final history = [...widget.state.history]..sort(compareHistory);

    return Column(
      children: [
        if (widget.state.actionInProgress)
          const LinearProgressIndicator(key: Key('mes_rdv_action_progress')),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: SegmentedControl(
                  key: const Key('mes_rdv_segments'),
                  segments: const ['À venir', 'Historique'],
                  selectedIndex: _selectedIndex,
                  onChanged: (i) => setState(() => _selectedIndex = i),
                ),
              ),
              IconButton(
                key: const Key('sort_button'),
                icon: const Icon(Icons.sort),
                tooltip: _selectedIndex == 0
                    ? (_currentSortAsc
                        ? 'Plus lointain d\'abord'
                        : 'Plus proche d\'abord')
                    : (_currentSortAsc
                        ? 'Plus récent d\'abord'
                        : 'Plus ancien d\'abord'),
                onPressed: _toggleSort,
              ),
            ],
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: _selectedIndex,
            sizing: StackFit.expand,
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
      onRefresh: () async {
        final bloc = context.read<MesRdvBloc>();
        bloc.add(const MesRdvLoadRequested());
        await bloc.stream.firstWhere(
          (s) => s is MesRdvLoaded || s is MesRdvError,
          orElse: () => const MesRdvLoading(),
        );
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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: NubiaCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                NubiaAvatar(initials: _initials(appointment.practitionerName)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Praticien en titre : un humain cherche d'abord chez QUI
                      // il a rendez-vous (le motif passe en secondaire).
                      Text(
                        appointment.practitionerName,
                        style: textTheme.titleSmall,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${appointment.motif} · ${appointment.practitionerSpecialty}',
                        style: textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _StatusPill(status: appointment.status),
              ],
            ),
            const SizedBox(height: 12),
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

  String _initials(String name) {
    // Retire le préfixe de civilité (« Dr », « Dr. », « Pr », « M. »…) pour ne
    // pas polluer les initiales : « Dr Amélie Dubois » → « AD », pas « DD ».
    final cleaned = name
        .replaceAll(
          RegExp(r'^(Dr|Dr\.|Pr|Pr\.|M\.|Mme|Mlle)\s+', caseSensitive: false),
          '',
        )
        .trim();
    final parts =
        cleaned.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      return parts.first.characters.first.toUpperCase();
    }
    return (parts.first.characters.first + parts.last.characters.first)
        .toUpperCase();
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
          NubiaButton(
            key: Key('checkin_${appointment.id}'),
            label: 'Check-in',
            size: NubiaButtonSize.sm,
            icon: Icons.check_circle_outline,
            onPressed: () => context
                .read<MesRdvBloc>()
                .add(MesRdvCheckinRequested(appointment.id)),
          ),
        if (appointment.canModify)
          NubiaButton(
            key: Key('modify_${appointment.id}'),
            label: 'Modifier',
            variant: NubiaButtonVariant.secondary,
            size: NubiaButtonSize.sm,
            icon: Icons.edit_calendar_outlined,
            onPressed: () async {
              final modified =
                  await context.push<bool>('/rdv/${appointment.id}/modifier');
              if (modified == true && context.mounted) {
                context.read<MesRdvBloc>().add(const MesRdvLoadRequested());
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Rendez-vous modifié')),
                );
              }
            },
          ),
        if (appointment.canCancel)
          NubiaButton(
            key: Key('cancel_${appointment.id}'),
            label: 'Annuler',
            variant: NubiaButtonVariant.destructive,
            size: NubiaButtonSize.sm,
            icon: Icons.cancel_outlined,
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

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});
  final AppointmentStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, variant) = switch (status) {
      AppointmentStatus.confirmed => ('Confirmé', StatusPillVariant.success),
      AppointmentStatus.requested => ('En attente', StatusPillVariant.warning),
      AppointmentStatus.cancelled => ('Annulé', StatusPillVariant.error),
      AppointmentStatus.completed => ('Terminé', StatusPillVariant.info),
      AppointmentStatus.noShow => ('Absent', StatusPillVariant.error),
    };
    return StatusPill(label: label, variant: variant);
  }
}
