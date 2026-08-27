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

/// Largeur de la colonne latérale « Praticiens présents » (maquette
/// design-v2, #5040) — sous ce seuil de largeur disponible, la colonne
/// disparaît plutôt que d'écraser la file (comportement tablette/portrait).
const kPresencePanelBreakpoint = 900.0;
const kPresencePanelWidth = 280.0;

class _LoadedViewState extends State<_LoadedView> {
  Completer<void>? _refreshCompleter;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final body = BlocListener<WaitingRoomBloc, WaitingRoomState>(
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
          if (widget.state.reloadError != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: NubiaInlineError(
                key: const Key('waiting_room_reload_error'),
                message: widget.state.reloadError!,
                onRetry: () => context
                    .read<WaitingRoomBloc>()
                    .add(const WaitingRoomLoadRequested()),
              ),
            ),
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

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < kPresencePanelBreakpoint) return body;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: body),
            const SizedBox(
              width: kPresencePanelWidth,
              child: Padding(
                padding: EdgeInsets.fromLTRB(0, 16, 16, 16),
                child: _PresencePanel(key: Key('presence_panel')),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------

/// Panneau latéral « Praticiens présents » (maquette design-v2, #5040,
/// `.bx` header `groups`) — liste statique le temps qu'un flux de présence
/// existe côté domaine (aucune source de données praticiens-présents
/// aujourd'hui dans [WaitingRoomLoaded]).
class _PresencePanel extends StatelessWidget {
  const _PresencePanel({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        NubiaCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.groups, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Praticiens présents',
                      style: textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const _PractitionerPresenceRow(
                initials: 'AR',
                name: 'Dr Amélie Rousseau',
                subtitle: 'Vous · en consultation',
                statusLabel: 'Présente',
                statusVariant: StatusPillVariant.success,
              ),
              const SizedBox(height: 12),
              const _PractitionerPresenceRow(
                initials: 'ML',
                name: 'Dr Marc Lefèvre',
                subtitle: 'Fauteuil 2 · termine à 18h',
                statusLabel: 'Départ 18h',
                statusVariant: StatusPillVariant.warning,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const _ConfidentialityNote(),
      ],
    );
  }
}

/// Une ligne du panneau « Praticiens présents » : avatar, nom, sous-texte,
/// pastille de statut (jamais couleur seule — label + [StatusPill]).
class _PractitionerPresenceRow extends StatelessWidget {
  const _PractitionerPresenceRow({
    required this.initials,
    required this.name,
    required this.subtitle,
    required this.statusLabel,
    required this.statusVariant,
  });

  final String initials;
  final String name;
  final String subtitle;
  final String statusLabel;
  final StatusPillVariant statusVariant;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        NubiaAvatar(initials: initials, radius: 16),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style:
                    textTheme.bodySmall?.copyWith(color: tokens.textTertiary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              StatusPill(label: statusLabel, variant: statusVariant),
            ],
          ),
        ),
      ],
    );
  }
}

/// Note de confidentialité clinique (maquette design-v2, `.note`, icône
/// `shield`) — verbatim : la file d'attente n'affiche que le motif
/// administratif, jamais d'alerte clinique (celles-ci restent réservées à
/// la carte du prochain appelé).
class _ConfidentialityNote extends StatelessWidget {
  const _ConfidentialityNote();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    return Container(
      key: const Key('waiting_room_confidentiality_note'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: NubiaColors.n50,
        border: Border.all(color: NubiaColors.n200),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.shield, size: 18, color: NubiaColors.n400),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'La file affiche le motif administratif du rendez-vous. Les '
              'alertes cliniques ne figurent que sur la carte du prochain '
              'appelé.',
              style: textTheme.bodySmall?.copyWith(color: tokens.textTertiary),
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
      < 15 => ('Moins de 15 min', StatusPillVariant.info),
      < 30 => ('Plus de 15 min', StatusPillVariant.warning),
      _ => ('Plus de 30 min', StatusPillVariant.error),
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
