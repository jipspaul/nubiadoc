import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import '../../router/app_router.dart';
import '../../session/pro_auth_cubit.dart';
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

/// Intervalle du rafraîchissement automatique (tablette murale, #5034) : la
/// file change sans qu'on la touche, le geste tactile n'est plus le seul
/// mécanisme de mise à jour.
const kWaitingRoomAutoRefreshInterval = Duration(seconds: 30);

class _WaitingRoomBodyState extends State<WaitingRoomBody> {
  Timer? _autoRefreshTimer;

  @override
  void initState() {
    super.initState();
    context.read<WaitingRoomBloc>().add(const WaitingRoomLoadRequested());
    _autoRefreshTimer = Timer.periodic(
      kWaitingRoomAutoRefreshInterval,
      (_) => context.read<WaitingRoomBloc>().add(
            const WaitingRoomLoadRequested(),
          ),
    );
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    super.dispose();
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
        title: Row(
          children: [
            Flexible(
              child: Text(
                NubiaL10n.waitingRoom,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 16),
            BlocBuilder<WaitingRoomBloc, WaitingRoomState>(
              builder: (context, state) => state is WaitingRoomLoaded
                  ? _FreshnessIndicator(loadedAt: state.loadedAt)
                  : const SizedBox.shrink(),
            ),
          ],
        ),
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

/// Pastille verte + texte relatif dans la barre de titre — âge de la
/// dernière donnée reçue (maquette design-v2, `.live` : « Mise à jour il y a
/// 8 s »). Se rafraîchit à la seconde sans dépendre d'un nouvel état du bloc.
class _FreshnessIndicator extends StatefulWidget {
  const _FreshnessIndicator({required this.loadedAt});

  final DateTime loadedAt;

  @override
  State<_FreshnessIndicator> createState() => _FreshnessIndicatorState();
}

class _FreshnessIndicatorState extends State<_FreshnessIndicator> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      key: const Key('waiting_room_freshness_indicator'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: const BoxDecoration(
            color: NubiaColors.brand600,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          'Mise à jour il y a ${_relativeAge(widget.loadedAt)}',
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: NubiaColors.n500),
        ),
      ],
    );
  }

  static String _relativeAge(DateTime loadedAt) {
    final elapsed = DateTime.now().difference(loadedAt);
    if (elapsed.inSeconds < 60) return '${elapsed.inSeconds} s';
    if (elapsed.inMinutes < 60) return '${elapsed.inMinutes} min';
    return '${elapsed.inHours} h';
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

/// Largeur de la colonne latérale droite (`.c2`, maquette design-v2, #5036 —
/// disposition deux colonnes, 378 px fixes) — sous ce seuil de largeur
/// disponible, la colonne disparaît plutôt que d'écraser la file
/// (comportement tablette/portrait).
const kPresencePanelBreakpoint = 900.0;
const kPresencePanelWidth = 378.0;

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
          if (widget.state.entries.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: _NextPatientHeroCard(
                entry: widget.state.entries.first,
                disabled: widget.state.actionInProgress,
                onCallNext: () => context
                    .read<WaitingRoomBloc>()
                    .add(const WaitingRoomCallNextRequested()),
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
                  label: widget.state.entries.isEmpty
                      ? NubiaL10n.callNext
                      : NubiaL10n.callNextNamed(
                          widget.state.entries.first.patientName),
                  icon: Icons.campaign,
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
                        entry: widget.state.entries[i],
                        position: i + 1,
                        actionInProgress: widget.state.actionInProgress,
                      ),
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
            SizedBox(
              width: kPresencePanelWidth,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 16, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _RoomPacePanel(entries: widget.state.entries),
                    const SizedBox(height: 12),
                    _MyPatientsPanel(entries: widget.state.entries),
                    const SizedBox(height: 12),
                    const _ConfidentialityNote(),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------

/// Carte hero « Prochain patient à appeler » (maquette design-v2, #5037) —
/// premier de [WaitingRoomLoaded.entries], seul endroit où figure une alerte
/// clinique (ex. allergie) : n'affiche que ce que fournit [WaitingRoomEntry]
/// aujourd'hui (pas d'alerte tant qu'aucun champ domaine dédié n'existe, cf.
/// [WaitingRoomEntry.reason]), plutôt que d'inventer une donnée hors maquette.
class _NextPatientHeroCard extends StatelessWidget {
  const _NextPatientHeroCard({
    required this.entry,
    required this.disabled,
    required this.onCallNext,
  });

  final WaitingRoomEntry entry;
  final bool disabled;
  final VoidCallback onCallNext;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final appointmentTime = entry.appointmentTime;
    final waitMinutes = entry.waitSoFar.inMinutes;

    final metaParts = [
      if (entry.reason != null && entry.reason!.isNotEmpty) entry.reason!,
      if (appointmentTime != null) 'RDV de ${_formatTime(appointmentTime)}',
    ];

    return Container(
      key: const Key('next_patient_hero'),
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: NubiaColors.brand700,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'PROCHAIN PATIENT À APPELER',
            style: textTheme.labelSmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.75),
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              NubiaAvatar(
                  initials: NubiaInitials.of(entry.patientName), radius: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      entry.patientName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.headlineSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (metaParts.isNotEmpty)
                      Text(
                        metaParts.join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.85),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$waitMinutes min',
                    style: textTheme.headlineSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  Text(
                    'd\'attente',
                    style: textTheme.bodySmall
                        ?.copyWith(color: Colors.white.withValues(alpha: 0.75)),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              StatusPill(
                key: const Key('next_patient_hero_arrival_tag'),
                label: 'Arrivée à ${_formatTime(entry.arrivedAt)}',
                variant: StatusPillVariant.neutral,
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  key: const Key('next_patient_hero_call_button'),
                  onPressed: disabled ? null : onCallNext,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: NubiaColors.brand700,
                  ),
                  icon: const Icon(Icons.campaign),
                  label: Text(
                    'Appeler ${entry.patientName}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('next_patient_hero_open_file'),
                  onPressed: () => context.go(AppRouter.patients),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white),
                  ),
                  icon: const Icon(Icons.folder_open),
                  label: const Text(
                    'Ouvrir le dossier',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Convertit toujours via `.toLocal()` avant de lire heure/minute — évite
  /// le piège UTC #3856 (les `DateTime` remontés par l'API sont en UTC).
  static String _formatTime(DateTime time) {
    final local = time.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }
}

// ---------------------------------------------------------------------------

/// Panneau latéral « Rythme de la salle » (maquette design-v2, #5038, `.bx`
/// header `timer`) — attente moyenne et attente la plus longue parmi les
/// présents, dérivées de [WaitingRoomEntry.waitSoFar], et retard sur le
/// planning du prochain patient à appeler (#5032).
class _RoomPacePanel extends StatelessWidget {
  const _RoomPacePanel({required this.entries});

  final List<WaitingRoomEntry> entries;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final tokens = Theme.of(context).extension<NubiaTokens>()!;

    final waitMinutes = entries.map((e) => e.waitSoFar.inMinutes).toList();
    final averageMinutes = waitMinutes.isEmpty
        ? 0
        : (waitMinutes.reduce((a, b) => a + b) / waitMinutes.length).round();

    var longestIndex = 0;
    for (var i = 1; i < waitMinutes.length; i++) {
      if (waitMinutes[i] > waitMinutes[longestIndex]) longestIndex = i;
    }
    final longestMinutes = waitMinutes.isEmpty ? 0 : waitMinutes[longestIndex];
    final longestPatientName =
        entries.isEmpty ? '' : entries[longestIndex].patientName;

    // Retard sur le planning du prochain patient à appeler : écart entre
    // l'heure prévue du RDV et l'heure réelle d'appel (maintenant, tant que
    // l'appel n'a pas encore eu lieu). Pas de ligne sans RDV planifié.
    final scheduledAt = entries.isEmpty ? null : entries.first.appointmentTime;
    final calledAt = DateTime.now();
    final delayMinutes =
        scheduledAt == null ? null : calledAt.difference(scheduledAt).inMinutes;

    return NubiaCard(
      key: const Key('room_pace_panel'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.timer, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Rythme de la salle',
                  style: textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _PaceRow(
            key: const Key('room_pace_average'),
            label: 'Attente moyenne',
            subtitle: 'sur les ${entries.length} présents',
            value: '$averageMinutes min',
          ),
          const SizedBox(height: 12),
          _PaceRow(
            key: const Key('room_pace_longest'),
            label: 'Attente la plus longue',
            subtitle: longestPatientName,
            value: '$longestMinutes min',
            valueColor: tokens.warningFg,
          ),
          if (scheduledAt != null && delayMinutes != null) ...[
            const SizedBox(height: 12),
            _PaceRow(
              key: const Key('room_pace_delay'),
              label: 'Retard sur le planning',
              subtitle:
                  'RDV de ${_NextPatientHeroCard._formatTime(scheduledAt)}'
                  ' appelé à ${_NextPatientHeroCard._formatTime(calledAt)}',
              value: '${delayMinutes >= 0 ? '+' : ''}$delayMinutes min',
              valueColor: tokens.warningFg,
            ),
          ],
        ],
      ),
    );
  }
}

/// Une ligne du panneau « Rythme de la salle » : libellé + sous-texte, durée
/// à droite (couleur warning pour l'attente la plus longue).
class _PaceRow extends StatelessWidget {
  const _PaceRow({
    super.key,
    required this.label,
    required this.subtitle,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String subtitle;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style:
                    textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
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
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          value,
          style: textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: valueColor ?? tokens.neutralFg,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

/// Panneau latéral « Mes patients dans la file » (maquette design-v2, #5039,
/// `.bx` header `person`) — répartition de la file par praticien, dérivée de
/// [WaitingRoomEntry.practitionerId]/[WaitingRoomEntry.practitionerName] et
/// de l'identité praticien courante ([ProAuthCubit]). Motif administratif
/// uniquement, aucune donnée clinique (cf. [_ConfidentialityNote]).
class _MyPatientsPanel extends StatelessWidget {
  const _MyPatientsPanel({required this.entries});

  final List<WaitingRoomEntry> entries;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final tokens = Theme.of(context).extension<NubiaTokens>()!;

    final session = switch (context.watch<ProAuthCubit>().state) {
      AuthAuthenticated(:final session) => session,
      _ => const AuthSession(kind: UserKind.pro, userId: 'me'),
    };
    final currentPractitionerId = session.practitionerId;

    final mine = <WaitingRoomEntry>[];
    final unassigned = <WaitingRoomEntry>[];
    final byColleagueId = <String, List<WaitingRoomEntry>>{};
    final colleagueNames = <String, String>{};
    for (final entry in entries) {
      final practitionerId = entry.practitionerId;
      if (practitionerId == null) {
        unassigned.add(entry);
      } else if (practitionerId == currentPractitionerId) {
        mine.add(entry);
      } else {
        byColleagueId.putIfAbsent(practitionerId, () => []).add(entry);
        colleagueNames.putIfAbsent(
            practitionerId, () => entry.practitionerName ?? 'confrère');
      }
    }

    return NubiaCard(
      key: const Key('my_patients_panel'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.person, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Mes patients dans la file',
                  style: textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              NubiaBadge.count(
                key: const Key('my_patients_badge'),
                count: mine.length,
              ),
            ],
          ),
          const SizedBox(height: 12),
          _QueueBreakdownRow(
            key: const Key('queue_breakdown_mine'),
            label: 'Pour vous',
            subtitle: mine.map((e) => _firstName(e.patientName)).join(', '),
            value: mine.length,
            valueColor: NubiaColors.brand700,
          ),
          for (final colleagueId in byColleagueId.keys) ...[
            const SizedBox(height: 12),
            _QueueBreakdownRow(
              key: Key('queue_breakdown_$colleagueId'),
              label: 'Pour ${colleagueNames[colleagueId]}',
              subtitle: byColleagueId[colleagueId]!
                  .map((e) => e.patientName)
                  .join(', '),
              value: byColleagueId[colleagueId]!.length,
            ),
          ],
          if (unassigned.isNotEmpty) ...[
            const SizedBox(height: 12),
            _QueueBreakdownRow(
              key: const Key('queue_breakdown_unassigned'),
              label: 'Non attribué',
              subtitle: unassigned
                  .map((e) => e.reason != null
                      ? '${e.patientName} · ${e.reason}'
                      : e.patientName)
                  .join(', '),
              value: unassigned.length,
              valueColor: tokens.warningFg,
            ),
          ],
        ],
      ),
    );
  }
}

/// Extrait le prénom d'un nom complet (« Camille Moreau » → « Camille »).
String _firstName(String fullName) =>
    fullName.trim().split(RegExp(r'\s+')).first;

/// Une ligne du panneau « Mes patients dans la file » : libellé + sous-texte,
/// compteur à droite (couleur sémantique selon le groupe).
class _QueueBreakdownRow extends StatelessWidget {
  const _QueueBreakdownRow({
    super.key,
    required this.label,
    required this.subtitle,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String subtitle;
  final int value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style:
                    textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
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
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '$value',
          style: textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: valueColor ?? tokens.neutralFg,
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
  const _EntryCard({
    required this.entry,
    required this.position,
    required this.actionInProgress,
  });
  final WaitingRoomEntry entry;
  final int position;
  final bool actionInProgress;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final tokens = Theme.of(context).extension<NubiaTokens>()!;

    final wait = entry.waitSoFar;
    final waitMinutes = wait.inMinutes;
    final waitLabel =
        waitMinutes < 1 ? 'À l\'instant' : '$waitMinutes min d\'attente';
    final waitSubtitle = entry.estimatedWaitMinutes != null
        ? '$waitLabel · ~${entry.estimatedWaitMinutes} min estimé'
        : waitLabel;

    // À qui le patient est attribué (#5028) : « vous », le nom du confrère,
    // ou « non attribué » quand aucun praticien n'est encore assigné.
    final session = switch (context.watch<ProAuthCubit>().state) {
      AuthAuthenticated(:final session) => session,
      _ => const AuthSession(kind: UserKind.pro, userId: 'me'),
    };
    final practitionerLabel = switch (entry.practitionerId) {
      null => 'non attribué',
      final id when id == session.practitionerId => 'vous',
      _ => entry.practitionerName ?? 'confrère',
    };

    // Patient d'un confrère : non appelable depuis cette file (#5026) — le
    // bouton d'appel de la ligne reste visible mais atténué, cf. maquette
    // design-v2 (`.cb`, opacity .35).
    final isOtherPractitioner = entry.practitionerId != null &&
        entry.practitionerId != session.practitionerId;

    // Motif admin en tête du sous-titre (#5030) — pas de « · » orphelin
    // quand le motif est absent.
    final subtitle = entry.reason != null && entry.reason!.isNotEmpty
        ? '${entry.reason} · $waitSubtitle · $practitionerLabel'
        : '$waitSubtitle · $practitionerLabel';

    // #6058 : `practitioner_id` est toujours renseigné côté API
    // (`WaitingRoomEntry.practitioner_id: Uuid`, `appointment.practitioner_id
    // NOT NULL` — 0005_scheduling.sql). La branche « Sans RDV » / « Attribuer »
    // était donc inatteignable et son action un no-op ; retirée tant qu'aucun
    // flux backend (walk-in) ne peut produire cet état.
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
                    subtitle,
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
            const SizedBox(width: 8),
            _RowCallButton(
              entryKey: Key('entry_action_${entry.id}'),
              dimmed: isOtherPractitioner,
              onPressed: actionInProgress || isOtherPractitioner
                  ? null
                  : () => context
                      .read<WaitingRoomBloc>()
                      .add(WaitingRoomCallRequested(entry.id)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bouton d'appel par ligne (maquette design-v2, `.cb` — #5026) : carré
/// 32×32, coins arrondis 9px, bordure `--n200`, icône `campaign`. Permet
/// d'appeler un patient hors de son rang, en plus du bouton principal
/// (au-dessus de la liste) qui appelle toujours la tête de file.
class _RowCallButton extends StatelessWidget {
  const _RowCallButton({
    required this.entryKey,
    required this.dimmed,
    required this.onPressed,
  });

  final Key entryKey;
  final bool dimmed;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final button = Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: NubiaColors.n200),
      ),
      child: IconButton(
        key: entryKey,
        padding: EdgeInsets.zero,
        iconSize: 18,
        splashRadius: 18,
        tooltip: NubiaL10n.call,
        icon: const Icon(Icons.campaign),
        onPressed: onPressed,
      ),
    );
    return dimmed ? Opacity(opacity: 0.35, child: button) : button;
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
