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

/// Prochain patient réellement appelable (#7570) : le premier de la liste
/// dont `isWaiting` est vrai — jamais le premier de la liste brute, qui peut
/// être `in_consultation` (déjà au fauteuil, donc pas « suivant »). Même
/// prédicat que le CTA d'en-tête (`firstWhere((e) => e.isWaiting)`).
WaitingRoomEntry? _nextToCallEntry(List<WaitingRoomEntry> entries) {
  for (final entry in entries) {
    if (entry.isWaiting) return entry;
  }
  return null;
}

/// Entrée la plus en retard au-delà du seuil critique, ou `null` si aucune
/// n'y est (#5170) — c'est celle que le bandeau nomme.
WaitingRoomEntry? _mostOverdueEntry(List<WaitingRoomEntry> entries) {
  WaitingRoomEntry? mostOverdue;
  for (final entry in entries) {
    // #6708 : un patient déjà `in_consultation` n'attend plus, il ne doit
    // pas déclencher l'alerte.
    if (!entry.isWaiting) continue;
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
  const WaitingRoomBody({super.key, this.selectedEntryId});

  /// Patient sélectionné au clavier (↑/↓, maquette design-v2, #7896) — `null`
  /// par défaut, donc sans effet pour un embarquement qui ne branche pas la
  /// sélection (cf. doc de classe ci-dessus).
  final String? selectedEntryId;

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
            final nextToCall = _nextToCallEntry(entries);
            return Column(
              children: [
                if (mostOverdue != null)
                  _OverThresholdBanner(entry: mostOverdue),
                const _WaitingRoomTableHeader(),
                Expanded(
                  child: ListView.builder(
                    key: const Key('waiting_room_list'),
                    padding: EdgeInsets.zero,
                    itemCount: entries.length,
                    itemBuilder: (_, i) => _WaitingEntryTile(
                      entry: entries[i],
                      position: i + 1,
                      isNext: entries[i].id == nextToCall?.id,
                      isSelected: entries[i].id == widget.selectedEntryId,
                      actionInProgress: state.actionInProgress,
                    ),
                  ),
                ),
                const _WaitThresholdLegend(),
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
              '${entry.patientName} attend depuis '
              '${_WaitColumn._formatWait(entry.waitSoFar)}',
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

/// En-têtes de colonnes (maquette design-v2, bandeau `.thead`) : la maquette
/// prescrit un tableau N° / PATIENT / PRATICIEN / ATTENTE / ESTIMATION /
/// ACTIONS — la liste de cartes n'en affichait aucun (#7559).
class _WaitingRoomTableHeader extends StatelessWidget {
  const _WaitingRoomTableHeader();

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: tokens.textTertiary,
          fontWeight: FontWeight.w600,
          letterSpacing: .5,
        );

    Widget cell(String label, {int flex = 2, TextAlign? align}) => Expanded(
          flex: flex,
          child: Text(
            label,
            textAlign: align,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        );

    return Container(
      key: const Key('waiting_room_table_header'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(bottom: BorderSide(color: tokens.borderSubtle)),
      ),
      child: Row(
        children: [
          cell('N°', flex: 1),
          cell('Patient', flex: 5),
          cell('Praticien', flex: 3),
          cell('Attente', flex: 2, align: TextAlign.right),
          cell('Estimation', flex: 2, align: TextAlign.right),
          cell('Actions', flex: 3, align: TextAlign.right),
        ],
      ),
    );
  }
}

/// Légende des seuils de couleur (maquette design-v2, pied de tableau
/// `.foot`) : documente la mécanique de couleur de [_WaitColumn] (15 / 20 /
/// 30 min), absente de l'écran (#7559).
class _WaitThresholdLegend extends StatelessWidget {
  const _WaitThresholdLegend();

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final style =
        Theme.of(context).textTheme.labelSmall?.copyWith(color: tokens.textTertiary);

    Widget swatch(Color color, String label) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 6),
            Text(label, style: style),
          ],
        );

    return Container(
      key: const Key('waiting_room_threshold_legend'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(top: BorderSide(color: tokens.borderSubtle)),
      ),
      child: Wrap(
        spacing: 18,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          swatch(NubiaColors.n900, 'moins de 15 min'),
          swatch(tokens.infoFg, '15 min'),
          swatch(tokens.warningFg, '20 min'),
          swatch(tokens.dangerFg, '30 min et plus'),
          const _WaitingRoomKeyboardShortcuts(),
        ],
      ),
    );
  }
}

/// Rappel des raccourcis clavier en pied de salle d'attente (maquette
/// design-v2, `.kb` — #7896) : même motif que `_AgendaKeyboardShortcuts` de
/// l'écran voisin `/agenda`, qui rend déjà correctement ce cluster. ⌘⏎
/// existait déjà côté câblage ; ↑/↓ et R sont ajoutés avec leur affichage.
class _WaitingRoomKeyboardShortcuts extends StatelessWidget {
  const _WaitingRoomKeyboardShortcuts();

  static const _entries = [
    ('⌘⏎', 'appeler le suivant'),
    ('↑ ↓', 'patient'),
    ('R', 'actualiser'),
  ];

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    return Wrap(
      key: const Key('waiting_room_keyboard_shortcuts'),
      spacing: 12,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final entry in _entries)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _KbdBadge(entry.$1),
              const SizedBox(width: 4),
              Text(
                entry.$2,
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: tokens.textTertiary),
              ),
            ],
          ),
      ],
    );
  }
}

/// Pastille façon touche clavier (`.kbd` de la maquette) — même rendu que
/// `_KbdBadge` d'`agenda_page.dart` (motif de référence de l'issue #7896).
class _KbdBadge extends StatelessWidget {
  const _KbdBadge(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: NubiaColors.n50,
        border: Border.all(color: NubiaColors.n200),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: NubiaColors.n600,
        ),
      ),
    );
  }
}

class WaitingRoomPage extends StatefulWidget {
  const WaitingRoomPage({super.key});

  /// Déclenche l'appel du patient suivant si la file n'est pas vide — partagé
  /// entre le bouton de la barre d'outils et le raccourci ⌘⏎ (#5167 : la
  /// maquette design-v2 remplace le `FloatingActionButton.extended`, motif
  /// mobile qui masque une ligne sur un comptoir clavier-souris).
  static void _callNext(BuildContext context) {
    final bloc = context.read<WaitingRoomBloc>();
    final state = bloc.state;
    if (state is WaitingRoomLoaded &&
        state.entries.any((e) => e.isWaiting) &&
        !state.actionInProgress) {
      bloc.add(const WaitingRoomCallNextRequested());
    }
  }

  @override
  State<WaitingRoomPage> createState() => _WaitingRoomPageState();
}

/// Porte la sélection clavier ↑/↓ (maquette design-v2, pied de tableau,
/// #7896 — motif repris de `AgendaPage._selectDelta`) : purement un état
/// d'affichage local, ne pilote aucune action back — « appeler » reste sur
/// ⌘⏎/le bouton, jamais sur la ligne sélectionnée au clavier.
class _WaitingRoomPageState extends State<WaitingRoomPage> {
  String? _selectedEntryId;

  void _moveSelection(BuildContext context, int delta) {
    final state = context.read<WaitingRoomBloc>().state;
    if (state is! WaitingRoomLoaded || state.entries.isEmpty) return;
    final entries = state.entries;
    final currentIndex = _selectedEntryId == null
        ? -1
        : entries.indexWhere((e) => e.id == _selectedEntryId);
    final next = (currentIndex + delta).clamp(0, entries.length - 1);
    setState(() => _selectedEntryId = entries[next].id);
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.enter, meta: true): () =>
            WaitingRoomPage._callNext(context),
        const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
            _moveSelection(context, 1),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
            _moveSelection(context, -1),
        const SingleActivator(LogicalKeyboardKey.keyR): () => context
            .read<WaitingRoomBloc>()
            .add(const WaitingRoomLoadRequested()),
      },
      child: Scaffold(
        key: const Key('waiting_room_scaffold'),
        appBar: AppBar(
          title: Text(
            NubiaL10n.waitingRoom,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
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
                final hasPatients = state is WaitingRoomLoaded &&
                    state.entries.any((e) => e.isWaiting);
                final canCall = hasPatients && !state.actionInProgress;
                final label = hasPatients
                    ? NubiaL10n.callNextNamed(
                        state.entries.firstWhere((e) => e.isWaiting).patientName,
                      )
                    : NubiaL10n.callNext;
                return Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: NubiaButton(
                    key: const Key('waiting_room_call_next_button'),
                    label: label,
                    icon: Icons.skip_next,
                    onPressed: canCall
                        ? () => WaitingRoomPage._callNext(context)
                        : null,
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
        body: Focus(
          autofocus: true,
          child: Column(
            children: [
              BlocBuilder<WaitingRoomBloc, WaitingRoomState>(
                builder: (context, state) => state is WaitingRoomLoaded
                    ? _WaitingRoomKpiToolbar(
                        entries: state.entries,
                        loadedAt: state.loadedAt,
                      )
                    : const SizedBox.shrink(),
              ),
              Expanded(
                child: WaitingRoomBody(selectedEntryId: _selectedEntryId),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bandeau KPI + pastille de fraîcheur, pleine largeur du corps, sous
/// l'AppBar (#7219) : le loger dans `AppBar.title` l'exposait au partage de
/// largeur du titre avec les `actions` (bouton Actualiser + CTA « Appeler
/// … »), qui rabotait les trois libellés même quand la largeur abondait —
/// troisième récidive du même symptôme (#6428, #6430). Poser le bandeau
/// dans le corps lui donne toute la largeur de l'écran, sans partage forcé.
class _WaitingRoomKpiToolbar extends StatelessWidget {
  const _WaitingRoomKpiToolbar({
    required this.entries,
    required this.loadedAt,
  });

  final List<WaitingRoomEntry> entries;
  final DateTime loadedAt;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(bottom: BorderSide(color: tokens.borderSubtle)),
      ),
      // #6943 : les deux `Flexible` à flex égal se partageaient la largeur
      // moitié-moitié, quel que soit le besoin réel de chacun — la pastille
      // de fraîcheur (courte) volait ainsi la moitié de la place au bandeau
      // KPI (trois libellés bien plus longs). Le bandeau KPI garde sa
      // largeur intrinsèque ; seule la pastille, seule `Flexible` restante,
      // absorbe l'espace résiduel (et s'ellipse dans le pire des cas).
      child: Row(
        children: [
          WaitingRoomKpiBar(entries: entries),
          const SizedBox(width: 20),
          Flexible(child: _FreshnessIndicator(loadedAt: loadedAt)),
        ],
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
    required this.isNext,
    required this.isSelected,
    required this.actionInProgress,
  });

  final WaitingRoomEntry entry;
  final int position;

  /// `true` si cette entrée est le prochain patient réellement appelable
  /// (#7570) — dérivé de `WaitingRoomEntry.isWaiting`, jamais de [position],
  /// qui n'est qu'un rang d'affichage sur la liste brute (`in_consultation`
  /// compris).
  final bool isNext;

  /// `true` si cette entrée est pointée par la sélection clavier ↑/↓
  /// (maquette design-v2, pied de tableau, #7896) — purement visuel, ne
  /// pilote aucune action.
  final bool isSelected;

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

    // #7905 : une entrée déjà `in_consultation` n'est plus appelable.
    final bool isInConsultation = entry.status == 'in_consultation';

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
    final row = ListRow(
      key: Key('waiting_entry_row_${entry.id}'),
      selected: isSelected,
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PositionBadge(position: position, isNext: isNext),
          const SizedBox(width: 10),
          NubiaAvatar(initials: initialsFrom(entry.patientName)),
        ],
      ),
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
          _EstimationColumn(entry: entry, isNext: isNext),
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
                // #6702 : aucun endpoint d'attribution de praticien
                // n'existe côté API — un bouton d'apparence active qui ne
                // faisait qu'afficher une snackbar « à venir » induisait en
                // erreur, en particulier ici où il apparaît justement au
                // moment où une attribution est nécessaire. Grisé avec la
                // raison plutôt que retiré, pour garder le signal visuel
                // qu'une action reste à faire sur cette entrée.
                Tooltip(
                  message: "Attribution d'un praticien indisponible pour "
                      "l'instant.",
                  child: NubiaButton(
                    key: Key('waiting_entry_assign_button_${entry.id}'),
                    label: 'Attribuer',
                    icon: Icons.person_add,
                    size: NubiaButtonSize.sm,
                    variant: NubiaButtonVariant.secondary,
                    onPressed: null,
                  ),
                ),
              ],
            ],
          ),
          if (!isUnassigned) ...[
            const SizedBox(width: 16),
            () {
              final button = NubiaButton(
                key: Key('waiting_entry_call_button_${entry.id}'),
                label: NubiaL10n.call,
                icon: Icons.campaign,
                size: NubiaButtonSize.sm,
                variant: isNext
                    ? NubiaButtonVariant.primary
                    : NubiaButtonVariant.secondary,
                onPressed: actionInProgress || isInConsultation
                    ? null
                    : () => context
                        .read<WaitingRoomBloc>()
                        .add(WaitingRoomCallRequested(entry.id)),
              );
              // #7905 : une entrée déjà `in_consultation` n'est plus jamais
              // appelable — comme pour « Attribuer » (#6702, plus haut), un
              // bouton d'apparence active qui se contentait d'afficher une
              // snackbar induisait en erreur (message faux, puis muet dès
              // le 2e clic identique, le bloc ignorant un `actionError`
              // inchangé). Grisé avec la raison plutôt que retiré.
              if (!isInConsultation) return button;
              return Tooltip(
                message: 'Ce patient est déjà en consultation.',
                child: button,
              );
            }(),
          ],
          const SizedBox(width: 8),
          _RowOverflowMenu(entryId: entry.id),
        ],
      ),
    );

    Widget content = row;
    if (isNext) {
      content = DecoratedBox(
        key: const Key('waiting_entry_next_stripe'),
        decoration: const BoxDecoration(
          border: Border(
            left: BorderSide(color: NubiaColors.brand700, width: 3),
          ),
        ),
        child: content,
      );
    }
    if (isSelected) {
      content = ColoredBox(color: NubiaColors.brand50, child: content);
    }
    return content;
  }
}

/// Numéro de position dans la file (maquette `.pos`) : `position` reste
/// l'index de la liste renvoyée par le back (+1), purement client — aucune
/// dépendance API (#7559).
class _PositionBadge extends StatelessWidget {
  const _PositionBadge({required this.position, required this.isNext});

  final int position;
  final bool isNext;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    return Container(
      key: Key('waiting_entry_position_$position'),
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isNext ? NubiaColors.brand700 : tokens.neutralBg,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        '$position',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: isNext ? NubiaColors.n0 : tokens.neutralFg,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

/// Menu de dépassement « … » par ligne (maquette `.more`, colonne ACTIONS) :
/// aucune action secondaire n'a d'endpoint côté API pour l'instant (seuls
/// `call-next` et l'appel de tête de file existent, cf.
/// `WaitingRoomCallRequested`) — grisé avec la raison plutôt qu'omis, même
/// logique que le bouton « Attribuer » (#6702), pour garder le signal visuel
/// que la colonne existe sans promettre une action qui n'agit pas (#7559).
class _RowOverflowMenu extends StatelessWidget {
  const _RowOverflowMenu({required this.entryId});

  final String entryId;

  @override
  Widget build(BuildContext context) {
    return NubiaButton.icon(
      key: Key('waiting_entry_more_actions_$entryId'),
      icon: Icons.more_horiz,
      diameter: 28,
      semanticLabel: 'Actions supplémentaires à venir',
      onPressed: null,
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
          // #7321 : 84px tronquait tout praticien au nom un peu long
          // (« Dr Claire Lef… ») même quand la ligne avait ~300px de libre.
          // 160px laisse passer les noms réalistes ; l'ellipse reste le
          // filet de sécurité pour les cas extrêmes.
          constraints: const BoxConstraints(maxWidth: 160),
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
  const _EstimationColumn({required this.entry, required this.isNext});

  final WaitingRoomEntry entry;
  final bool isNext;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final style = Theme.of(context)
        .textTheme
        .labelSmall
        ?.copyWith(color: tokens.textTertiary);
    final minutes = entry.estimatedWaitMinutes;
    final value = minutes != null
        ? '~${_WaitColumn._formatWait(Duration(minutes: minutes))}'
        : '—';
    // Tête de file (#5169 / #7570) : le prochain patient réellement
    // appelable n'a pas d'estimation car il est sur le point d'être appelé,
    // pas en attente d'un calcul.
    final nullLabel =
        minutes != null ? null : (isNext ? 'à appeler' : 'à évaluer');

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
