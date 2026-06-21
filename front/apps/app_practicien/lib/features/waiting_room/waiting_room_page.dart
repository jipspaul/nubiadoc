import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'waiting_room_bloc.dart';
import 'waiting_room_event.dart';
import 'waiting_room_state.dart';

class WaitingRoomPage extends StatelessWidget {
  const WaitingRoomPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => GetIt.instance<WaitingRoomBloc>()
        ..add(const WaitingRoomLoadRequested()),
      child: const _WaitingRoomBody(),
    );
  }
}

// ---------------------------------------------------------------------------

class _WaitingRoomBody extends StatelessWidget {
  const _WaitingRoomBody();

  @override
  Widget build(BuildContext context) {
    return BlocListener<WaitingRoomBloc, WaitingRoomState>(
      listenWhen: (_, current) =>
          current is WaitingRoomLoaded && current.actionError != null,
      listener: (context, state) {
        if (state is WaitingRoomLoaded && state.actionError != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.actionError!)),
          );
        }
      },
      child: BlocBuilder<WaitingRoomBloc, WaitingRoomState>(
        builder: (context, state) {
          if (state is WaitingRoomInitial || state is WaitingRoomLoading) {
            return const Center(
              key: Key('waiting_room_loading'),
              child: CircularProgressIndicator(),
            );
          }
          if (state is WaitingRoomError) {
            return _ErrorView(
              key: const Key('waiting_room_error'),
              message: state.message,
            );
          }
          if (state is WaitingRoomLoaded) {
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
  final WaitingRoomLoaded state;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (state.actionInProgress)
          const LinearProgressIndicator(
              key: Key('waiting_room_action_progress')),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${state.entries.length} patient(s) en attente',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              FilledButton.icon(
                key: const Key('call_next_button'),
                onPressed: state.actionInProgress || state.entries.isEmpty
                    ? null
                    : () => context
                        .read<WaitingRoomBloc>()
                        .add(const WaitingRoomCallNextRequested()),
                icon: const Icon(Icons.arrow_forward, size: 18),
                label: const Text('Patient suivant'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: state.entries.isEmpty
              ? const Center(
                  key: Key('waiting_room_empty'),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.event_seat_outlined, size: 48),
                      SizedBox(height: 12),
                      Text('Salle d\'attente vide'),
                    ],
                  ),
                )
              : RefreshIndicator(
                  key: const Key('waiting_room_refresh'),
                  onRefresh: () async => context
                      .read<WaitingRoomBloc>()
                      .add(const WaitingRoomLoadRequested()),
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: state.entries.length,
                    itemBuilder: (context, i) =>
                        _EntryCard(entry: state.entries[i], position: i + 1),
                  ),
                ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _EntryCard extends StatelessWidget {
  const _EntryCard({required this.entry, required this.position});
  final WaitingRoomEntry entry;
  final int position;

  @override
  Widget build(BuildContext context) {
    final wait = entry.waitSoFar;
    final waitLabel = wait.inMinutes < 1
        ? 'À l\'instant'
        : '${wait.inMinutes} min d\'attente';

    return Card(
      key: Key('entry_${entry.id}'),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: ListTile(
        leading: CircleAvatar(
          child: Text('$position'),
        ),
        title: Text(entry.patientName),
        subtitle: Text(waitLabel),
        trailing: entry.estimatedWaitMinutes != null
            ? Chip(
                label: Text('~${entry.estimatedWaitMinutes} min'),
                visualDensity: VisualDensity.compact,
              )
            : null,
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
            onPressed: () => context
                .read<WaitingRoomBloc>()
                .add(const WaitingRoomLoadRequested()),
            child: const Text('Réessayer'),
          ),
        ],
      ),
    );
  }
}
