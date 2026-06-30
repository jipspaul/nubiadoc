import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'waiting_list_bloc.dart';
import 'waiting_list_event.dart';
import 'waiting_list_state.dart';

/// Body-only content for the waiting list. Can be embedded in any layout
/// that provides [WaitingListBloc] via [BlocProvider] (e.g. [ProShell]
/// bodyBuilder or the full-page [WaitingListPage]).
class WaitingListBody extends StatefulWidget {
  const WaitingListBody({super.key});

  @override
  State<WaitingListBody> createState() => _WaitingListBodyState();
}

class _WaitingListBodyState extends State<WaitingListBody> {
  Completer<void>? _refreshCompleter;

  @override
  void initState() {
    super.initState();
    context.read<WaitingListBloc>().add(const WaitingListLoadRequested());
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<WaitingListBloc, WaitingListState>(
      listener: (context, state) {
        if (state is WaitingListLoaded || state is WaitingListError) {
          _refreshCompleter?.complete();
          _refreshCompleter = null;
        }
        if (state is WaitingListOfferSuccess) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Créneau proposé avec succès.')),
          );
        }
      },
      builder: (context, state) {
        if (state is WaitingListLoaded || state is WaitingListOfferSuccess) {
          final entries = state is WaitingListLoaded
              ? state.entries
              : <WaitingListEntry>[];
          if (entries.isEmpty) {
            return const NubiaEmptyState(
              icon: Icons.event_busy,
              title: 'Pas d\'attente',
              subtitle: 'Aucun patient en liste d\'attente',
            );
          }
          return RefreshIndicator(
            onRefresh: () {
              _refreshCompleter = Completer<void>();
              context
                  .read<WaitingListBloc>()
                  .add(const WaitingListLoadRequested());
              return _refreshCompleter!.future;
            },
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: entries.length,
              itemBuilder: (_, i) => _WaitingListTile(entry: entries[i]),
            ),
          );
        }
        if (state is WaitingListError) {
          return NubiaErrorWidget(
            message: state.message,
            onRetry: () => context
                .read<WaitingListBloc>()
                .add(const WaitingListLoadRequested()),
          );
        }
        return const _LoadingView();
      },
    );
  }
}

class WaitingListPage extends StatelessWidget {
  const WaitingListPage({super.key});

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
      body: const WaitingListBody(),
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
