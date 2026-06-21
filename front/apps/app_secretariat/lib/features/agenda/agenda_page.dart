import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'agenda_bloc.dart';
import 'agenda_event.dart';
import 'agenda_state.dart';

DateTime _currentWeekStart() {
  final now = DateTime.now();
  return now.subtract(Duration(days: now.weekday - 1));
}

class AgendaPage extends StatelessWidget {
  const AgendaPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => GetIt.instance<AgendaBloc>()
        ..add(AgendaLoadRequested(weekStart: _currentWeekStart())),
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
    return Column(
      children: [
        if (state.actionInProgress)
          const LinearProgressIndicator(key: Key('agenda_action_progress')),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${state.entries.length} créneau(x) cette semaine',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              FilledButton.icon(
                key: const Key('new_appointment_button'),
                onPressed: state.actionInProgress
                    ? null
                    : () => _showNewAppointmentDialog(context),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Nouveau RDV'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        if (state.availableSlots.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              '${state.availableSlots.length} créneau(x) disponible(s)',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        Expanded(
          child: state.entries.isEmpty
              ? const Center(
                  key: Key('agenda_empty'),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.calendar_month_outlined, size: 48),
                      SizedBox(height: 12),
                      Text('Aucun rendez-vous cette semaine'),
                    ],
                  ),
                )
              : RefreshIndicator(
                  key: const Key('agenda_refresh_indicator'),
                  onRefresh: () async => context.read<AgendaBloc>().add(
                    AgendaLoadRequested(weekStart: _currentWeekStart()),
                  ),
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: state.entries.length,
                    itemBuilder: (context, i) =>
                        _EntryCard(entry: state.entries[i]),
                  ),
                ),
        ),
      ],
    );
  }

  void _showNewAppointmentDialog(BuildContext context) {
    // Minimal dialog stub — full booking flow to be implemented in FR3.x
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Nouveau rendez-vous'),
        content: const Text(
            'Sélectionnez un créneau disponible dans l\'agenda.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _EntryCard extends StatelessWidget {
  const _EntryCard({required this.entry});
  final AgendaEntry entry;

  @override
  Widget build(BuildContext context) {
    final time =
        '${entry.startsAt.hour.toString().padLeft(2, '0')}:${entry.startsAt.minute.toString().padLeft(2, '0')}';

    return Card(
      key: Key('entry_${entry.id}'),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: ListTile(
        leading: CircleAvatar(
          child: Text(time, style: const TextStyle(fontSize: 11)),
        ),
        title: Text(entry.patientName ?? 'Créneau libre'),
        subtitle: entry.motif != null ? Text(entry.motif!) : null,
        trailing: entry.isFree
            ? null
            : FilledButton.tonal(
                key: Key('confirm_${entry.id}'),
                onPressed: () => context.read<AgendaBloc>().add(
                      AgendaAppointmentConfirmRequested(
                          appointmentId: entry.id),
                    ),
                child: const Text('Confirmer'),
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
            onPressed: () => context.read<AgendaBloc>().add(
                  AgendaLoadRequested(weekStart: _currentWeekStart()),
                ),
            child: const Text('Réessayer'),
          ),
        ],
      ),
    );
  }
}
