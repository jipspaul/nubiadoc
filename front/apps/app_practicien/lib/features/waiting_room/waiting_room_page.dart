import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'waiting_room_bloc.dart';
import 'waiting_room_event.dart';
import 'waiting_room_state.dart';

/// Body-only content for the waiting room.
/// Requires [WaitingRoomBloc] to be provided via [BlocProvider] by the caller.
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
          if (state is WaitingRoomError) {
            return NubiaErrorWidget(
              key: const Key('waiting_room_error'),
              message: state.message,
              onRetry: () => context
                  .read<WaitingRoomBloc>()
                  .add(const WaitingRoomLoadRequested()),
            );
          }
          if (state is WaitingRoomLoaded) {
            return _LoadedView(state: state);
          }
          return const _LoadingView(key: Key('waiting_room_loading'));
        },
      ),
    );
  }
}

/// Full-page scaffold for direct-URL navigation.
/// Requires [WaitingRoomBloc] to be provided via [BlocProvider] by the caller.
class WaitingRoomPage extends StatelessWidget {
  const WaitingRoomPage({super.key});

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
      body: const WaitingRoomBody(),
    );
  }
}

// ---------------------------------------------------------------------------

class _LoadingView extends StatelessWidget {
  const _LoadingView({super.key});

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

// ---------------------------------------------------------------------------

class _LoadedView extends StatefulWidget {
  const _LoadedView({required this.state});
  final WaitingRoomLoaded state;

  @override
  State<_LoadedView> createState() => _LoadedViewState();
}

class _LoadedViewState extends State<_LoadedView> {
  Completer<void>? _refreshCompleter;

  @override
  Widget build(BuildContext context) {
    return BlocListener<WaitingRoomBloc, WaitingRoomState>(
      listenWhen: (_, s) => s is WaitingRoomLoaded || s is WaitingRoomError,
      listener: (_, __) {
        _refreshCompleter?.complete();
        _refreshCompleter = null;
      },
      child: Column(
        children: [
          if (widget.state.actionInProgress)
            const LinearProgressIndicator(
                key: Key('waiting_room_action_progress')),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${widget.state.entries.length} patient(s) en attente',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                FilledButton.icon(
                  key: const Key('call_next_button'),
                  onPressed:
                      widget.state.actionInProgress || widget.state.entries.isEmpty
                          ? null
                          : () => context
                              .read<WaitingRoomBloc>()
                              .add(const WaitingRoomCallNextRequested()),
                  icon: const Icon(Icons.arrow_forward, size: 18),
                  label: Text(NubiaL10n.callNext),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: widget.state.entries.isEmpty
                ? const NubiaEmptyState(
                    key: Key('waiting_room_empty'),
                    icon: Icons.event_seat_outlined,
                    title: NubiaL10n.waitingRoom,
                    subtitle: NubiaL10n.noWaitingRoom,
                  )
                : RefreshIndicator(
                    key: const Key('waiting_room_refresh'),
                    onRefresh: () {
                      _refreshCompleter = Completer<void>();
                      context
                          .read<WaitingRoomBloc>()
                          .add(const WaitingRoomLoadRequested());
                      return _refreshCompleter!.future;
                    },
                    child: ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: widget.state.entries.length,
                      itemBuilder: (context, i) => _EntryCard(
                          entry: widget.state.entries[i], position: i + 1),
                    ),
                  ),
          ),
        ],
      ),
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
