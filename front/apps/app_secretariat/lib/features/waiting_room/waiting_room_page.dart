import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'waiting_room_bloc.dart';
import 'waiting_room_event.dart';
import 'waiting_room_state.dart';
import 'widgets/waiting_room_kpis.dart';

/// Seuil critique d'attente (cf. KPI « au-delà de 30 min », #5170/#5173).
const int _criticalWaitThresholdMinutes = 30;

/// Entrée la plus en retard au-delà du seuil critique, ou `null` si aucune
/// n'y est (#5170) — c'est celle que le bandeau nomme.
WaitingRoomEntry? _mostOverdueEntry(List<WaitingRoomEntry> entries) {
  WaitingRoomEntry? mostOverdue;
  for (final entry in entries) {
    if (entry.waitSoFar.inMinutes < _criticalWaitThresholdMinutes) continue;
    if (mostOverdue == null || entry.waitSoFar > mostOverdue.waitSoFar) {
      mostOverdue = entry;
    }
  }
  return mostOverdue;
}

/// Body-only content for the waiting room. Can be embedded in any layout
/// that provides [WaitingRoomBloc] via [BlocProvider] (e.g. [ProShell]
/// bodyBuilder or the full-page [WaitingRoomPage]).
class WaitingRoomBody extends StatefulWidget {
  const WaitingRoomBody({super.key});

  @override
  State<WaitingRoomBody> createState() => _WaitingRoomBodyState();
}

class _WaitingRoomBodyState extends State<WaitingRoomBody> {
  Timer? _refreshTimer;

  /// Rafraîchissement périodique auto (poste secrétariat, personne ne
  /// regarde en continu) — maquette design-v2, point 4 : « une salle
  /// d'attente change sans qu'on la regarde ». L'âge de la donnée s'affiche
  /// dans la barre d'outils ([_FreshnessIndicator]) ; le bouton refresh
  /// manuel reste disponible en plus.
  static const _autoRefreshInterval = Duration(seconds: 15);

  @override
  void initState() {
    super.initState();
    context.read<WaitingRoomBloc>().add(const WaitingRoomLoadRequested());
    _refreshTimer = Timer.periodic(
      _autoRefreshInterval,
      (_) => context
          .read<WaitingRoomBloc>()
          .add(const WaitingRoomLoadRequested()),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
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
            final mostOverdue = _mostOverdueEntry(entries);
            return Column(
              children: [
                if (mostOverdue != null)
                  _OverThresholdBanner(entry: mostOverdue),
                Expanded(
                  child: ListView.builder(
                    key: const Key('waiting_room_list'),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: entries.length,
                    itemBuilder: (_, i) => _WaitingEntryTile(
                      entry: entries[i],
                      position: i + 1,
                      actionInProgress: state.actionInProgress,
                    ),
                  ),
                ),
              ],
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
      ),
    );
  }
}

/// Bandeau d'alerte affiché au-dessus de la liste quand au moins une
/// entrée dépasse le seuil critique (#5170) : nomme le patient le plus en
/// retard et propose « Prévenir le praticien ». Ne montre aucune donnée
/// praticien (nom, heure de séance) faute d'extension d'entité (ticket
/// colonne Praticien) — cf. corps de l'issue.
class _OverThresholdBanner extends StatelessWidget {
  const _OverThresholdBanner({required this.entry});

  final WaitingRoomEntry entry;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final minutes = entry.waitSoFar.inMinutes;
    return Container(
      key: const Key('waiting_room_alert_banner'),
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tokens.warningBg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.error, color: tokens.warningFg),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '${entry.patientName} attend depuis $minutes min',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: tokens.warningFg,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          const SizedBox(width: 12),
          NubiaButton(
            key: const Key('waiting_room_notify_practitioner_button'),
            label: 'Prévenir le praticien',
            size: NubiaButtonSize.sm,
            variant: NubiaButtonVariant.secondary,
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Notification du praticien à venir'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class WaitingRoomPage extends StatelessWidget {
  const WaitingRoomPage({super.key});

  /// Déclenche l'appel du patient suivant si la file n'est pas vide — partagé
  /// entre le bouton de la barre d'outils et le raccourci ⌘⏎ (#5167 : la
  /// maquette design-v2 remplace le `FloatingActionButton.extended`, motif
  /// mobile qui masque une ligne sur un comptoir clavier-souris).
  static void _callNext(BuildContext context) {
    final bloc = context.read<WaitingRoomBloc>();
    final state = bloc.state;
    if (state is WaitingRoomLoaded &&
        state.entries.isNotEmpty &&
        !state.actionInProgress) {
      bloc.add(const WaitingRoomCallNextRequested());
    }
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.enter, meta: true): () =>
            _callNext(context),
      },
      child: Scaffold(
        key: const Key('waiting_room_scaffold'),
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
              const SizedBox(width: 24),
              Expanded(
                child: BlocBuilder<WaitingRoomBloc, WaitingRoomState>(
                  builder: (context, state) => state is WaitingRoomLoaded
                      ? Row(
                          children: [
                            Flexible(
                              child:
                                  WaitingRoomKpiBar(entries: state.entries),
                            ),
                            const SizedBox(width: 12),
                            Flexible(
                              child: _FreshnessIndicator(
                                loadedAt: state.loadedAt,
                              ),
                            ),
                          ],
                        )
                      : const SizedBox.shrink(),
                ),
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
            BlocBuilder<WaitingRoomBloc, WaitingRoomState>(
              builder: (context, state) {
                final hasPatients =
                    state is WaitingRoomLoaded && state.entries.isNotEmpty;
                final canCall = hasPatients && !state.actionInProgress;
                final label = hasPatients
                    ? NubiaL10n.callNextNamed(state.entries.first.patientName)
                    : NubiaL10n.callNext;
                return Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: NubiaButton(
                    key: const Key('waiting_room_call_next_button'),
                    label: label,
                    icon: Icons.skip_next,
                    onPressed: canCall ? () => _callNext(context) : null,
                  ),
                );
              },
            ),
            const Padding(
              padding: EdgeInsets.only(left: 8, right: 16),
              child: NubiaBadge.label(label: '⌘⏎'),
            ),
          ],
        ),
        body: const Focus(
          autofocus: true,
          child: WaitingRoomBody(),
        ),
      ),
    );
  }
}

/// Pastille verte + texte relatif — âge de la dernière donnée reçue
/// (maquette design-v2, point 4 : « Actualisé il y a 4 s »). Vit dans un
/// widget dédié pour se rafraîchir à la seconde sans dépendre d'un nouvel
/// état du bloc (#5161).
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
    final elapsed = DateTime.now().difference(widget.loadedAt);
    final age = elapsed.inSeconds < 60
        ? '${elapsed.inSeconds} s'
        : elapsed.inMinutes < 60
            ? '${elapsed.inMinutes} min'
            : '${elapsed.inHours} h';
    return StatusPill(
      key: const Key('waiting_room_freshness_indicator'),
      icon: Icons.circle,
      label: 'Actualisé il y a $age',
      variant: StatusPillVariant.success,
      flexibleLabel: true,
    );
  }
}

class _WaitingEntryTile extends StatelessWidget {
  const _WaitingEntryTile({
    required this.entry,
    required this.position,
    required this.actionInProgress,
  });

  final WaitingRoomEntry entry;
  final int position;

  /// Une action (appel suivant/ligne) est déjà en cours côté back — désactive
  /// le bouton « Appeler » de la ligne pour éviter le double-appel (#6637).
  final bool actionInProgress;

  @override
  Widget build(BuildContext context) {
    final reason = entry.reason;
    // Conversion via `.toLocal()` avant de lire heure/minute — évite le
    // piège UTC #3856 (les `DateTime` remontés par l'API sont en UTC).
    final appointmentTime = entry.appointmentTime?.toLocal();
    final timeLabel = appointmentTime != null
        ? '${appointmentTime.hour.toString().padLeft(2, '0')}:'
            '${appointmentTime.minute.toString().padLeft(2, '0')}'
        : null;
    final subtitle = reason == null || reason.isEmpty
        ? null
        : timeLabel == null
            ? reason
            : '$reason · RDV $timeLabel';

    // Urgence sans rendez-vous : aucun praticien attribué (#5171).
    final bool isUnassigned = entry.appointmentId == null;

    // #6636 : pastille pilotée par `status` (API), plus par un littéral —
    // sinon un patient déjà `in_consultation` s'affiche comme s'il attendait.
    final (String statusLabel, StatusPillVariant statusVariant) =
        switch (entry.status) {
      'in_consultation' => ('En consultation', StatusPillVariant.progress),
      _ when isUnassigned => ('Sans RDV', StatusPillVariant.warning),
      _ => ('En attente', StatusPillVariant.info),
    };

    // Tête de file (#5165) : liseré émeraude à gauche, jamais un fond de
    // ligne — le fond entrerait en concurrence avec la couleur du retard.
    final bool isNext = position == 1;

    final row = ListRow(
      leading: NubiaAvatar(initials: initialsFrom(entry.patientName)),
      title: entry.patientName,
      subtitle: subtitle,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _PractitionerColumn(entry: entry),
          const SizedBox(width: 8),
          _WaitColumn(entry: entry),
          const SizedBox(width: 8),
          _EstimationColumn(entry: entry, position: position),
          const SizedBox(width: 16),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              StatusPill(
                label: statusLabel,
                variant: statusVariant,
              ),
              if (isUnassigned) ...[
                const SizedBox(height: 4),
                NubiaButton(
                  key: Key('waiting_entry_assign_button_${entry.id}'),
                  label: 'Attribuer',
                  icon: Icons.person_add,
                  size: NubiaButtonSize.sm,
                  variant: NubiaButtonVariant.secondary,
                  onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("Attribution d'un praticien à venir"),
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (!isUnassigned) ...[
            const SizedBox(width: 16),
            NubiaButton(
              key: Key('waiting_entry_call_button_${entry.id}'),
              label: NubiaL10n.call,
              icon: Icons.campaign,
              size: NubiaButtonSize.sm,
              variant: isNext
                  ? NubiaButtonVariant.primary
                  : NubiaButtonVariant.secondary,
              onPressed: actionInProgress
                  ? null
                  : () => context
                      .read<WaitingRoomBloc>()
                      .add(WaitingRoomCallRequested(entry.id)),
            ),
          ],
        ],
      ),
    );

    if (!isNext) {
      return row;
    }
    return DecoratedBox(
      key: const Key('waiting_entry_next_stripe'),
      decoration: const BoxDecoration(
        border: Border(
          left: BorderSide(color: NubiaColors.brand700, width: 3),
        ),
      ),
      child: row,
    );
  }
}

/// Colonne « Praticien » (#5168) : nom + pastille carrée, même code couleur
/// que la grille agenda (couleur dérivée de `practitionerId` via
/// [practitionerColor], partagée entre les deux écrans). « Non attribué »
/// quand l'urgence n'a pas encore de praticien (cf. #5171).
class _PractitionerColumn extends StatelessWidget {
  const _PractitionerColumn({required this.entry});

  final WaitingRoomEntry entry;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final name = entry.practitionerName;
    final hasPractitioner = name != null && name.isNotEmpty;
    final label = hasPractitioner ? name : 'Non attribué';
    final color = practitionerColor(entry.practitionerId);
    final style = Theme.of(context)
        .textTheme
        .labelSmall
        ?.copyWith(color: tokens.textTertiary);

    return Row(
      key: Key('waiting_entry_practitioner_${entry.id}'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 84),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
      ],
    );
  }
}

/// Colonne « Attente » dédiée (#5162) : `waitSoFar` sort du sous-titre pour
/// devenir sa propre colonne, en gros, dont la couleur monte par seuils
/// (15 / 20 / 30 min) — sinon 38 min ressemble à 3 min. Sous-label « arrivé
/// à HH:MM » dérivé de `arrivedAt`, valeur non inventée.
class _WaitColumn extends StatelessWidget {
  const _WaitColumn({required this.entry});

  final WaitingRoomEntry entry;

  static Color _colorFor(NubiaTokens tokens, int minutes) {
    if (minutes >= 30) return tokens.dangerFg;
    if (minutes >= 20) return tokens.warningFg;
    if (minutes >= 15) return tokens.infoFg;
    return NubiaColors.n900;
  }

  // Formatage conservé : minutes seules sous 60, sinon « h + min ».
  static String _formatWait(Duration wait) {
    final minutes = wait.inMinutes;
    if (minutes < 60) return '$minutes min';
    final hours = minutes ~/ 60;
    final remainder = (minutes % 60).toString().padLeft(2, '0');
    return '${hours}h$remainder';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final wait = entry.waitSoFar;
    // Conversion via `.toLocal()` avant de lire heure/minute — évite le
    // piège UTC #3856 (les `DateTime` remontés par l'API sont en UTC).
    final arrivedAt = entry.arrivedAt.toLocal();
    final arrivedLabel = 'arrivé à '
        '${arrivedAt.hour.toString().padLeft(2, '0')}:'
        '${arrivedAt.minute.toString().padLeft(2, '0')}';

    return Column(
      key: Key('waiting_entry_wait_${entry.id}'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          _formatWait(wait),
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: _colorFor(tokens, wait.inMinutes),
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 2),
        Text(
          arrivedLabel,
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(color: tokens.textTertiary),
        ),
      ],
    );
  }
}

/// Colonne « Estimation » dédiée (#5169) : `estimatedWaitMinutes` sort de la
/// note de bas de page pour devenir sa propre colonne, sans jamais inventer
/// de valeur quand le champ est nul.
class _EstimationColumn extends StatelessWidget {
  const _EstimationColumn({required this.entry, required this.position});

  final WaitingRoomEntry entry;
  final int position;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final style = Theme.of(context)
        .textTheme
        .labelSmall
        ?.copyWith(color: tokens.textTertiary);
    final minutes = entry.estimatedWaitMinutes;
    final value = minutes != null ? '~$minutes min' : '—';
    // Tête de file (#5169) : la première position n'a pas d'estimation car
    // elle est sur le point d'être appelée, pas en attente d'un calcul.
    final nullLabel =
        minutes != null ? null : (position == 1 ? 'à appeler' : 'à évaluer');

    return Column(
      key: Key('waiting_entry_estimation_${entry.id}'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(value, style: style),
        if (nullLabel != null) ...[
          const SizedBox(height: 2),
          Text(nullLabel, style: style),
        ],
      ],
    );
  }
}
