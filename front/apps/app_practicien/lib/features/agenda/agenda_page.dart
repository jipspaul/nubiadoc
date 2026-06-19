import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:nubia_domain/nubia_domain.dart';

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
      child: const _AgendaBody(),
    );
  }
}

// ---------------------------------------------------------------------------

class _AgendaBody extends StatelessWidget {
  const _AgendaBody();

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
            return const Center(
              key: Key('agenda_loading'),
              child: CircularProgressIndicator(),
            );
          }
          if (state is AgendaError) {
            return _ErrorView(
              key: const Key('agenda_error'),
              message: state.message,
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

class _LoadedView extends StatelessWidget {
  const _LoadedView({required this.state});
  final AgendaLoaded state;

  @override
  Widget build(BuildContext context) {
    final grouped = _groupByDay(state.entries);
    final weekEnd = state.weekStart.add(const Duration(days: 6));

    return Column(
      children: [
        if (state.actionInProgress)
          const LinearProgressIndicator(key: Key('agenda_action_progress')),
        _WeekNav(weekStart: state.weekStart, weekEnd: weekEnd),
        const Divider(height: 1),
        Expanded(
          child: grouped.isEmpty
              ? const Center(
                  key: Key('agenda_empty'),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.calendar_today_outlined, size: 48),
                      SizedBox(height: 12),
                      Text('Aucun rendez-vous cette semaine'),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 16),
                  itemCount: grouped.length,
                  itemBuilder: (context, i) {
                    final day = grouped[i];
                    return _DaySection(
                      date: day.date,
                      entries: day.entries,
                      actionInProgress: state.actionInProgress,
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
    final startH = entry.startsAt.hour.toString().padLeft(2, '0');
    final startM = entry.startsAt.minute.toString().padLeft(2, '0');
    final endH = entry.endsAt.hour.toString().padLeft(2, '0');
    final endM = entry.endsAt.minute.toString().padLeft(2, '0');
    final timeLabel = '$startH:$startM – $endH:$endM';

    return Card(
      key: Key('entry_${entry.id}'),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.access_time, size: 14),
                const SizedBox(width: 4),
                Text(timeLabel,
                    style: Theme.of(context).textTheme.bodySmall),
                if (!entry.isFree) ...[
                  const SizedBox(width: 8),
                  Chip(
                    label: Text(
                      entry.patientName ?? '',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ],
            ),
            if (entry.motif != null) ...[
              const SizedBox(height: 4),
              Text(
                entry.motif!,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
            if (!entry.isFree) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  OutlinedButton.icon(
                    key: Key('confirm_${entry.id}'),
                    onPressed: actionInProgress
                        ? null
                        : () => context.read<AgendaBloc>().add(
                              AgendaAppointmentConfirmRequested(
                                appointmentId: entry.id,
                              ),
                            ),
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('Confirmer'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    key: Key('start_${entry.id}'),
                    onPressed: actionInProgress
                        ? null
                        : () => context.read<AgendaBloc>().add(
                              AgendaConsultationStartRequested(
                                appointmentId: entry.id,
                              ),
                            ),
                    icon: const Icon(Icons.play_arrow, size: 16),
                    label: const Text('Démarrer'),
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

class _ErrorView extends StatelessWidget {
  const _ErrorView({super.key, required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () {
              final bloc = context.read<AgendaBloc>();
              final current = bloc.state;
              if (current is AgendaLoaded) {
                bloc.add(AgendaLoadRequested(weekStart: current.weekStart));
              }
            },
            child: const Text('Réessayer'),
          ),
        ],
      ),
    );
  }
}
