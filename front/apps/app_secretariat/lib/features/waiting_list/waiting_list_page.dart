import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'waiting_list_bloc.dart';
import 'waiting_list_event.dart';
import 'waiting_list_state.dart';

class WaitingListPage extends StatefulWidget {
  const WaitingListPage({super.key});

  @override
  State<WaitingListPage> createState() => _WaitingListPageState();
}

class _WaitingListPageState extends State<WaitingListPage> {
  @override
  void initState() {
    super.initState();
    context.read<WaitingListBloc>().add(const WaitingListLoadRequested());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Liste d\'attente'),
        actions: [
          IconButton(
            tooltip: 'Actualiser',
            icon: const Icon(Icons.refresh),
            onPressed: () => context
                .read<WaitingListBloc>()
                .add(const WaitingListLoadRequested()),
          ),
        ],
      ),
      body: BlocConsumer<WaitingListBloc, WaitingListState>(
        listener: (context, state) {
          if (state is WaitingListOfferSuccess) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Créneau proposé avec succès.')),
            );
          }
        },
        builder: (context, state) {
          if (state is WaitingListLoaded || state is WaitingListOfferSuccess) {
            final entries = state is WaitingListLoaded ? state.entries : <WaitingListEntry>[];
            if (entries.isEmpty) {
              return const Center(
                child: Text('Aucun patient en liste d\'attente.'),
              );
            }
            return RefreshIndicator(
              onRefresh: () async => context
                  .read<WaitingListBloc>()
                  .add(const WaitingListLoadRequested()),
              child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: entries.length,
                itemBuilder: (_, i) => _WaitingListTile(entry: entries[i]),
              ),
            );
          }
          if (state is WaitingListError) {
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

class _WaitingListTile extends StatelessWidget {
  const _WaitingListTile({required this.entry});

  final WaitingListEntry entry;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(child: Text('${entry.position}')),
      title: Text(entry.patientName),
      subtitle: Text('Demande du ${_formatDate(entry.requestedAt)}'),
      trailing: IconButton(
        tooltip: 'Proposer un créneau',
        icon: const Icon(Icons.calendar_today_outlined),
        onPressed: () => context
            .read<WaitingListBloc>()
            .add(WaitingListOfferSlotRequested(entry.id)),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }
}
