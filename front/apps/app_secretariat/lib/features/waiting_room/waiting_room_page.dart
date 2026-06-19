import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
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
        title: const Text('Salle d\'attente'),
        actions: [
          IconButton(
            tooltip: 'Actualiser',
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
        label: const Text('Appeler suivant'),
      ),
      body: BlocBuilder<WaitingRoomBloc, WaitingRoomState>(
        builder: (context, state) {
          if (state is WaitingRoomLoaded) {
            final entries = state.entries;
            if (entries.isEmpty) {
              return const Center(
                child: Text('Aucun patient en salle d\'attente.'),
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: entries.length,
              itemBuilder: (_, i) => _WaitingEntryTile(entry: entries[i]),
            );
          }
          if (state is WaitingRoomError) {
            return Center(
              child: Text(
                state.message,
                style: const TextStyle(color: Colors.red),
              ),
            );
          }
          return const Center(child: CircularProgressIndicator());
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
