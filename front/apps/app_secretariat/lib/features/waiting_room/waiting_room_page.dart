import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'waiting_room_bloc.dart';
import 'waiting_room_event.dart';
import 'waiting_room_state.dart';

class WaitingRoomPage extends StatefulWidget {
  const WaitingRoomPage({super.key});

  @override
  State<WaitingRoomPage> createState() => _WaitingRoomPageState();
}

class _WaitingRoomPageState extends State<WaitingRoomPage> {
  @override
  void initState() {
    super.initState();
    context.read<WaitingRoomBloc>().add(const WaitingRoomLoadRequested());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context
            .read<WaitingRoomBloc>()
            .add(const WaitingRoomCallNextRequested()),
        icon: const Icon(Icons.person_add_alt_1_outlined),
        label: Text(NubiaL10n.callNext),
      ),
      body: BlocBuilder<WaitingRoomBloc, WaitingRoomState>(
        builder: (context, state) {
          if (state is WaitingRoomLoaded) {
            final entries = state.entries;
            if (entries.isEmpty) {
              return const NubiaEmptyState(
                icon: Icons.people_outline,
                title: 'Salle d\'attente vide',
                subtitle: NubiaL10n.noWaitingRoom,
              );
            }
            return ListView.builder(
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
          return const _LoadingView();
        },
      ),
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

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      itemCount: 5,
      itemBuilder: (_, __) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: NubiaSkeletonLoader(height: 72),
      ),
    );
  }
}
