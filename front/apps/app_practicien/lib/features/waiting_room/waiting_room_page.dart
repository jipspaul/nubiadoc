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

/// Squelette de chargement de la file d'attente.
class _LoadingView extends StatelessWidget {
  const _LoadingView({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (var i = 0; i < 6; i++)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: NubiaSkeletonLoader(height: 72, borderRadius: 12),
          ),
      ],
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
    final textTheme = Theme.of(context).textTheme;
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
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${widget.state.entries.length} patient(s) en attente',
                    style: textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                NubiaButton(
                  key: const Key('call_next_button'),
                  label: NubiaL10n.callNext,
                  icon: Icons.arrow_forward,
                  size: NubiaButtonSize.sm,
                  isLoading: widget.state.actionInProgress,
                  onPressed: widget.state.actionInProgress ||
                          widget.state.entries.isEmpty
                      ? null
                      : () => context
                          .read<WaitingRoomBloc>()
                          .add(const WaitingRoomCallNextRequested()),
                ),
              ],
            ),
          ),
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
                      padding: const EdgeInsets.only(bottom: 8),
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
    final textTheme = Theme.of(context).textTheme;
    final tokens = Theme.of(context).extension<NubiaTokens>()!;

    final wait = entry.waitSoFar;
    final waitMinutes = wait.inMinutes;
    final waitLabel =
        waitMinutes < 1 ? 'À l\'instant' : '$waitMinutes min d\'attente';

    // Statut dérivé du temps d'attente : jamais la couleur seule (label + pill).
    final (String statusLabel, StatusPillVariant statusVariant) =
        switch (waitMinutes) {
      < 15 => ('En attente', StatusPillVariant.info),
      < 30 => ('Patiente', StatusPillVariant.warning),
      _ => ('Attente longue', StatusPillVariant.error),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: NubiaCard(
        key: Key('entry_${entry.id}'),
        child: Row(
          children: [
            _PositionBadge(position: position),
            const SizedBox(width: 12),
            NubiaAvatar(
                initials: NubiaInitials.of(entry.patientName), radius: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.patientName,
                    style: textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    entry.estimatedWaitMinutes != null
                        ? '$waitLabel · ~${entry.estimatedWaitMinutes} min estimé'
                        : waitLabel,
                    style: textTheme.bodySmall
                        ?.copyWith(color: tokens.textTertiary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            StatusPill(label: statusLabel, variant: statusVariant),
          ],
        ),
      ),
    );
  }
}

/// Pastille de position dans la file (n° d'ordre).
class _PositionBadge extends StatelessWidget {
  const _PositionBadge({required this.position});
  final int position;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tokens.primarySubtleBg,
        shape: BoxShape.circle,
      ),
      child: Text(
        '$position',
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: tokens.primarySubtleFg,
          fontWeight: FontWeight.w600,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}
