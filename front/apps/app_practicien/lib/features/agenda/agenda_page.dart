import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import '../patients/patients_bloc.dart';
import '../patients/patients_event.dart';
import '../patients/patients_state.dart';
import 'agenda_bloc.dart';
import 'agenda_event.dart';
import 'agenda_state.dart';

class AgendaPage extends StatelessWidget {
  const AgendaPage({super.key});

  static DateTime _startOfCurrentWeek() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day - (now.weekday - 1));
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => GetIt.instance<AgendaBloc>()
        ..add(AgendaLoadRequested(weekStart: _startOfCurrentWeek())),
      child: const _AgendaView(),
    );
  }
}

// ---------------------------------------------------------------------------

class _AgendaView extends StatelessWidget {
  const _AgendaView();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AgendaBloc, AgendaState>(
      buildWhen: (prev, curr) =>
          (prev is AgendaLoaded ? prev.includePast : false) !=
          (curr is AgendaLoaded ? curr.includePast : false),
      builder: (context, state) {
        final includePast = state is AgendaLoaded ? state.includePast : false;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Agenda'),
            actions: [
              IconButton(
                key: const Key('agenda_toggle_past'),
                icon: const Icon(Icons.history),
                tooltip: 'Inclure passés',
                isSelected: includePast,
                onPressed: () =>
                    context.read<AgendaBloc>().add(const TogglePastIncluded()),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            key: const Key('agenda_fab_consultation'),
            onPressed: () => _showPatientPicker(context),
            icon: const Icon(Icons.play_arrow),
            label: const Text('Consultation'),
          ),
          body: const AgendaBody(),
        );
      },
    );
  }
}

void _showPatientPicker(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) => _PatientPickerSheet(
      onPatientSelected: (_) {
        Navigator.of(sheetContext).pop();
        GoRouter.of(context).go('/consultation');
      },
    ),
  );
}

// ---------------------------------------------------------------------------

class _PatientPickerSheet extends StatelessWidget {
  const _PatientPickerSheet({required this.onPatientSelected});
  final void Function(String patientId) onPatientSelected;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) =>
          GetIt.instance<PatientsBloc>()..add(const PatientsLoadRequested()),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'Sélectionner un patient',
                key: const Key('patient_picker_title'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const Divider(height: 1),
            _PatientPickerBody(onPatientSelected: onPatientSelected),
          ],
        ),
      ),
    );
  }
}

class _PatientPickerBody extends StatelessWidget {
  const _PatientPickerBody({required this.onPatientSelected});
  final void Function(String patientId) onPatientSelected;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PatientsBloc, PatientsState>(
      builder: (context, state) {
        if (state is PatientsInitial || state is PatientsLoading) {
          return const SizedBox(
            height: 80,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (state is PatientsError) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Text(state.message),
          );
        }
        if (state is PatientsLoaded) {
          if (state.patients.isEmpty) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              child: Text('Aucun patient enregistré'),
            );
          }
          return ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: state.patients.length,
            itemBuilder: (_, i) {
              final p = state.patients[i];
              return ListRow(
                key: Key('patient_pick_${p.id}'),
                leading: NubiaAvatar(initials: _initials(p.fullName)),
                title: p.fullName,
                subtitle: p.email ?? p.phone,
                trailing: const Icon(Icons.chevron_right, size: 20),
                onTap: () => onPatientSelected(p.id),
              );
            },
          );
        }
        return const SizedBox.shrink();
      },
    );
  }
}

// ---------------------------------------------------------------------------

class AgendaBody extends StatelessWidget {
  const AgendaBody({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocListener<AgendaBloc, AgendaState>(
      listenWhen: (_, current) =>
          current is AgendaLoaded && current.actionError != null,
      listener: (context, state) {
        if (state is AgendaLoaded && state.actionError != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.actionError!)),
          );
        }
      },
      child: BlocBuilder<AgendaBloc, AgendaState>(
        builder: (context, state) {
          if (state is AgendaInitial || state is AgendaLoading) {
            return const _AgendaSkeleton(key: Key('agenda_loading'));
          }
          if (state is AgendaError) {
            return NubiaErrorWidget(
              key: const Key('agenda_error'),
              message: state.message,
              onRetry: () => context.read<AgendaBloc>().add(
                    AgendaLoadRequested(
                        weekStart: AgendaPage._startOfCurrentWeek()),
                  ),
            );
          }
          if (state is AgendaLoaded) {
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
  final AgendaLoaded state;

  @override
  State<_LoadedView> createState() => _LoadedViewState();
}

class _LoadedViewState extends State<_LoadedView> {
  DateTimeRange? _range;

  List<AgendaEntry> get _filtered {
    final r = _range;
    if (r == null) return widget.state.entries;
    final dayAfterEnd = DateTime(r.end.year, r.end.month, r.end.day)
        .add(const Duration(days: 1));
    return widget.state.entries
        .where((e) =>
            !e.startsAt.isBefore(r.start) && e.startsAt.isBefore(dayAfterEnd))
        .toList();
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      currentDate: widget.state.weekStart,
      initialDateRange: _range ??
          DateTimeRange(
            start: widget.state.weekStart,
            end: widget.state.weekStart.add(const Duration(days: 6)),
          ),
    );
    if (picked != null && mounted) setState(() => _range = picked);
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final grouped = _groupByDay(filtered);
    final weekEnd = widget.state.weekStart.add(const Duration(days: 6));

    return Column(
      children: [
        if (widget.state.actionInProgress)
          const LinearProgressIndicator(key: Key('agenda_action_progress')),
        _WeekNav(weekStart: widget.state.weekStart, weekEnd: weekEnd),
        const Divider(height: 1),
        _DateFilterBar(
          range: _range,
          onPick: _pickRange,
          onClear: () => setState(() => _range = null),
        ),
        Expanded(
          child: grouped.isEmpty
              ? const NubiaEmptyState(
                  key: Key('agenda_empty'),
                  icon: Icons.calendar_today_outlined,
                  title: 'Aucun rendez-vous cette semaine',
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 16),
                  itemCount: grouped.length,
                  itemBuilder: (context, i) {
                    final day = grouped[i];
                    return _DaySection(
                      date: day.date,
                      entries: day.entries,
                      actionInProgress: widget.state.actionInProgress,
                    );
                  },
                ),
        ),
      ],
    );
  }

  List<_DayGroup> _groupByDay(List<AgendaEntry> entries) {
    final map = <String, _DayGroup>{};
    for (final entry in entries) {
      final key =
          '${entry.startsAt.year}-${entry.startsAt.month}-${entry.startsAt.day}';
      map.putIfAbsent(
        key,
        () => _DayGroup(
          date: DateTime(
            entry.startsAt.year,
            entry.startsAt.month,
            entry.startsAt.day,
          ),
          entries: [],
        ),
      );
      map[key]!.entries.add(entry);
    }
    final groups = map.values.toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    return groups;
  }
}

class _DayGroup {
  _DayGroup({required this.date, required this.entries});
  final DateTime date;
  final List<AgendaEntry> entries;
}

// ---------------------------------------------------------------------------

class _DateFilterBar extends StatelessWidget {
  const _DateFilterBar({
    required this.range,
    required this.onPick,
    required this.onClear,
  });

  final DateTimeRange? range;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Row(
        children: [
          NubiaButton(
            key: const Key('agenda_date_filter_button'),
            variant: NubiaButtonVariant.tertiary,
            size: NubiaButtonSize.sm,
            icon: Icons.date_range,
            label: range == null ? 'Filtrer par date' : _rangeLabel(),
            onPressed: onPick,
          ),
          if (range != null)
            IconButton(
              key: const Key('agenda_date_filter_clear'),
              icon: const Icon(Icons.close, size: 16),
              tooltip: 'Effacer le filtre',
              onPressed: onClear,
            ),
        ],
      ),
    );
  }

  String _rangeLabel() {
    final r = range!;
    const months = [
      'jan.',
      'fév.',
      'mar.',
      'avr.',
      'mai',
      'juin',
      'juil.',
      'août',
      'sep.',
      'oct.',
      'nov.',
      'déc.',
    ];
    final sm = months[r.start.month - 1];
    final em = months[r.end.month - 1];
    if (r.start.month == r.end.month && r.start.year == r.end.year) {
      return '${r.start.day}–${r.end.day} $sm ${r.start.year}';
    }
    return '${r.start.day} $sm – ${r.end.day} $em ${r.end.year}';
  }
}

// ---------------------------------------------------------------------------

class _WeekNav extends StatelessWidget {
  const _WeekNav({required this.weekStart, required this.weekEnd});
  final DateTime weekStart;
  final DateTime weekEnd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(
            key: const Key('agenda_prev_week'),
            icon: const Icon(Icons.chevron_left),
            onPressed: () => context.read<AgendaBloc>().add(
                  AgendaWeekChanged(
                    weekStart: weekStart.subtract(const Duration(days: 7)),
                  ),
                ),
          ),
          Expanded(
            child: Text(
              _weekLabel(),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          IconButton(
            key: const Key('agenda_next_week'),
            icon: const Icon(Icons.chevron_right),
            onPressed: () => context.read<AgendaBloc>().add(
                  AgendaWeekChanged(
                    weekStart: weekStart.add(const Duration(days: 7)),
                  ),
                ),
          ),
        ],
      ),
    );
  }

  String _weekLabel() {
    final months = [
      'jan.',
      'fév.',
      'mar.',
      'avr.',
      'mai',
      'juin',
      'juil.',
      'août',
      'sep.',
      'oct.',
      'nov.',
      'déc.',
    ];
    final startMonth = months[weekStart.month - 1];
    final endMonth = months[weekEnd.month - 1];
    if (weekStart.month == weekEnd.month) {
      return '${weekStart.day}–${weekEnd.day} $startMonth ${weekStart.year}';
    }
    return '${weekStart.day} $startMonth – ${weekEnd.day} $endMonth ${weekEnd.year}';
  }
}

// ---------------------------------------------------------------------------

class _DaySection extends StatelessWidget {
  const _DaySection({
    required this.date,
    required this.entries,
    required this.actionInProgress,
  });
  final DateTime date;
  final List<AgendaEntry> entries;
  final bool actionInProgress;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            _dayLabel(),
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(color: Theme.of(context).colorScheme.primary),
          ),
        ),
        ...entries.map(
          (e) => _EntryCard(entry: e, actionInProgress: actionInProgress),
        ),
      ],
    );
  }

  String _dayLabel() {
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
}

// ---------------------------------------------------------------------------

class _EntryCard extends StatelessWidget {
  const _EntryCard({required this.entry, required this.actionInProgress});
  final AgendaEntry entry;
  final bool actionInProgress;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final startH = entry.startsAt.hour.toString().padLeft(2, '0');
    final startM = entry.startsAt.minute.toString().padLeft(2, '0');
    final endH = entry.endsAt.hour.toString().padLeft(2, '0');
    final endM = entry.endsAt.minute.toString().padLeft(2, '0');
    final timeLabel = '$startH:$startM – $endH:$endM';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: NubiaCard(
        key: Key('entry_${entry.id}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.schedule_outlined,
                    size: 16, color: cs.onSurfaceVariant),
                const SizedBox(width: 6),
                Text(
                  timeLabel,
                  style: textTheme.labelLarge?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const Spacer(),
                if (entry.isFree)
                  const StatusPill(
                    label: 'Libre',
                    variant: StatusPillVariant.success,
                  )
                else
                  const StatusPill(
                    label: 'Réservé',
                    variant: StatusPillVariant.info,
                  ),
              ],
            ),
            if (!entry.isFree && entry.patientName != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  NubiaAvatar(
                      initials: _initials(entry.patientName!), radius: 16),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.patientName!,
                          style: textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w500),
                        ),
                        if (entry.motif != null)
                          Text(
                            entry.motif!,
                            style: textTheme.bodySmall
                                ?.copyWith(color: cs.onSurfaceVariant),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ] else if (entry.motif != null) ...[
              const SizedBox(height: 8),
              Text(entry.motif!, style: textTheme.bodyMedium),
            ],
            if (!entry.isFree) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  NubiaButton(
                    key: Key('confirm_${entry.id}'),
                    variant: NubiaButtonVariant.secondary,
                    size: NubiaButtonSize.sm,
                    icon: Icons.check,
                    label: 'Confirmer',
                    onPressed: actionInProgress
                        ? null
                        : () => context.read<AgendaBloc>().add(
                              AgendaAppointmentConfirmRequested(
                                appointmentId: entry.id,
                              ),
                            ),
                  ),
                  const SizedBox(width: 8),
                  NubiaButton(
                    key: Key('start_${entry.id}'),
                    size: NubiaButtonSize.sm,
                    icon: Icons.play_arrow,
                    label: 'Démarrer',
                    onPressed: actionInProgress
                        ? null
                        : () => context.read<AgendaBloc>().add(
                              AgendaConsultationStartRequested(
                                appointmentId: entry.id,
                              ),
                            ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

/// Squelette de chargement de l'agenda (liste de cartes shimmer).
class _AgendaSkeleton extends StatelessWidget {
  const _AgendaSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (var i = 0; i < 5; i++)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: NubiaSkeletonLoader(height: 88, borderRadius: 12),
          ),
      ],
    );
  }
}

/// Initiales (max 2 lettres) à partir d'un nom complet.
String _initials(String fullName) {
  final parts =
      fullName.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
      .toUpperCase();
}
