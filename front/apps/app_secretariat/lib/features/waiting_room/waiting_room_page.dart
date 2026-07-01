import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'waiting_room_bloc.dart';
import 'waiting_room_event.dart';
import 'waiting_room_state.dart';

/// Body-only content for the waiting room. Can be embedded in any layout
/// that provides [WaitingRoomBloc] via [BlocProvider] (e.g. [ProShell]
/// bodyBuilder or the full-page [WaitingRoomPage]).
class WaitingRoomBody extends StatefulWidget {
  const WaitingRoomBody({super.key});

  @override
  State<WaitingRoomBody> createState() => _WaitingRoomBodyState();
}

class _WaitingRoomBodyState extends State<WaitingRoomBody> {
  @override
  void initState() {
    super.initState();
    context.read<WaitingRoomBloc>().add(const WaitingRoomLoadRequested());
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<WaitingRoomBloc, WaitingRoomState>(
      builder: (context, state) {
        if (state is WaitingRoomLoaded) {
          final entries = state.entries;
          if (entries.isEmpty) {
            return const NubiaEmptyState(
              key: Key('waiting_room_empty'),
              icon: Icons.people_outline,
              title: 'Salle d\'attente vide',
              subtitle: NubiaL10n.noWaitingRoom,
            );
          }
          return ListView.builder(
            key: const Key('waiting_room_list'),
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: entries.length,
            itemBuilder: (_, i) => _WaitingEntryTile(entry: entries[i]),
          );
        }
        if (state is WaitingRoomError) {
          return NubiaErrorWidget(
            message: state.message,
            onRetry: () => context
                .read<WaitingRoomBloc>()
                .add(const WaitingRoomLoadRequested()),
          );
        }
        return const Center(child: CircularProgressIndicator());
      },
    );
  }
}

class WaitingRoomPage extends StatelessWidget {
  const WaitingRoomPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('waiting_room_scaffold'),
      appBar: AppBar(
        title: Text(NubiaL10n.waitingRoom),
        actions: [
          IconButton(
            tooltip: NubiaL10n.refresh,
            icon: const Icon(Icons.refresh),
            onPressed: () => context
                .read<WaitingRoomBloc>()
                .add(const WaitingRoomLoadRequested()),
          ),
        ],
      ),
      floatingActionButton: BlocBuilder<WaitingRoomBloc, WaitingRoomState>(
        builder: (context, state) {
          final hasPatients =
              state is WaitingRoomLoaded && state.entries.isNotEmpty;
          return FloatingActionButton.extended(
            onPressed: hasPatients
                ? () => context
                    .read<WaitingRoomBloc>()
                    .add(const WaitingRoomCallNextRequested())
                : null,
            icon: const Icon(Icons.skip_next),
            label: Text(NubiaL10n.callNext),
          );
        },
      ),
      body: const WaitingRoomBody(),
    );
  }
}

class _WaitingEntryTile extends StatelessWidget {
  const _WaitingEntryTile({required this.entry});

  final WaitingRoomEntry entry;

  @override
  Widget build(BuildContext context) {
    final wait = entry.waitSoFar;
    final waitLabel = wait.inMinutes < 60
        ? '${wait.inMinutes} min'
        : '${wait.inHours} h ${wait.inMinutes.remainder(60)} min';

    return ListTile(
      leading: const Icon(Icons.person_outline),
      title: Text(entry.patientName),
      subtitle: Text('Arrivé il y a $waitLabel'),
      trailing: entry.estimatedWaitMinutes != null
          ? Text(
              '~${entry.estimatedWaitMinutes} min',
              style: Theme.of(context).textTheme.bodySmall,
            )
          : null,
    );
  }
}

