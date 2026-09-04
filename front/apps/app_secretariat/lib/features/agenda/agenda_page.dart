import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'agenda_bloc.dart';
import 'agenda_event.dart';
import 'agenda_state.dart';

DateTime _currentWeekStart() {
  final now = DateTime.now();
  return now.subtract(Duration(days: now.weekday - 1));
}

/// Créneaux réellement réservables pour le picker « Nouveau RDV » (#3466).
///
/// `slot.isAvailable` (statut `open`) ne suffit pas : les données peuvent
/// contenir un créneau ouvert qui chevauche un RDV déjà posé pour le même
/// praticien. Le réserver déclenche la contrainte d'exclusion back
/// (`appointment_no_overlap`) → 409 `slot_taken`. On exclut donc tout créneau
/// ouvert chevauchant un RDV non annulé du même praticien (les RDV connus étant
/// ceux de la semaine chargée dans l'agenda).
List<Slot> bookableSlots(List<Slot> slots, List<AgendaEntry> entries) {
  final booked = entries
      .where((e) => !e.isFree && e.status != 'cancelled')
      .toList(growable: false);
  bool overlapsBooked(Slot s) {
    for (final e in booked) {
      if (e.practitionerId == s.practitionerId &&
          s.startsAt.isBefore(e.endsAt) &&
          e.startsAt.isBefore(s.endsAt)) {
        return true;
      }
    }
    return false;
  }

  return slots
      .where((s) => s.isAvailable && !overlapsBooked(s))
      .toList(growable: false);
}

// ---------------------------------------------------------------------------

String _dayKey(DateTime d) => '${d.year}-${d.month}-${d.day}';

/// Contenu de la destination « agenda » du shell (`router/app_router.dart`).
///
/// #5083 — cadrage : la maquette `design/v2-screens/secretariat-agenda.png`
/// affiche un rail de navigation gauche (`space_dashboard`, `calendar_month`,
/// `groups`, `meeting_room`, `description`, `payments`, `inventory_2`,
/// `settings`) à titre de décor de mise en situation (point 9, verbatim :
/// « la refonte du shell n'est pas dans cette itération »). Ce rail est déjà
/// fourni par `SecretariatShell`/`ProShell` (voir README.md « Navigation —
/// surface unique (#5154) ») ; [AgendaPage] ne doit PAS le redessiner ni le
/// dupliquer — elle reste uniquement le contenu de la branche « agenda ».
class AgendaPage extends StatelessWidget {
  const AgendaPage({super.key, this.openAppointmentId});

  /// RDV à sélectionner à l'ouverture (volet latéral déjà ouvert dessus,
  /// #5079) — passé en `extra` depuis le ticket « Appeler » du tableau de
  /// bord secrétariat (#6246), pour cibler directement le RDV du ticket
  /// plutôt que la grille hebdomadaire complète.
  final String? openAppointmentId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => GetIt.instance<AgendaBloc>()
        ..add(AgendaLoadRequested(weekStart: _currentWeekStart())),
      child: _AgendaBody(openAppointmentId: openAppointmentId),
    );
  }
}

// ---------------------------------------------------------------------------

class _AgendaBody extends StatefulWidget {
  const _AgendaBody({this.openAppointmentId});

  final String? openAppointmentId;

  @override
  State<_AgendaBody> createState() => _AgendaBodyState();
}

class _AgendaBodyState extends State<_AgendaBody> {
  Completer<void>? _refreshCompleter;

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<AgendaBloc, AgendaState>(
      listener: (context, state) {
        if (state is AgendaLoaded || state is AgendaError) {
          _refreshCompleter?.complete();
          _refreshCompleter = null;
        }
        if (state is AgendaLoaded && state.actionError != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.actionError!)),
          );
        }
      },
      builder: (context, state) {
        if (state is AgendaInitial || state is AgendaLoading) {
          return const _AgendaSkeleton();
        }
        if (state is AgendaError) {
          return NubiaErrorWidget(
            key: const Key('agenda_error'),
            message: state.message,
            onRetry: () => context.read<AgendaBloc>().add(
                  AgendaLoadRequested(weekStart: _currentWeekStart()),
                ),
          );
        }
        if (state is AgendaLoaded) {
          return _LoadedView(
            state: state,
            onRefresh: () {
              _refreshCompleter = Completer<void>();
              context.read<AgendaBloc>().add(
                    AgendaLoadRequested(weekStart: state.weekStart),
                  );
              return _refreshCompleter!.future;
            },
            initialSelectedEntryId: widget.openAppointmentId,
          );
        }
        return const SizedBox.shrink();
      },
    );
  }
}

// ---------------------------------------------------------------------------

class _LoadedView extends StatefulWidget {
  const _LoadedView({
    required this.state,
    required this.onRefresh,
    this.initialSelectedEntryId,
  });
  final AgendaLoaded state;
  final Future<void> Function() onRefresh;
  final String? initialSelectedEntryId;

  @override
  State<_LoadedView> createState() => _LoadedViewState();
}

class _LoadedViewState extends State<_LoadedView> {
  /// Praticiens actuellement filtrés (puces à bascule, maquette design-v2,
  /// #5076) — vide = tous les praticiens affichés ; plusieurs praticiens
  /// peuvent être actifs simultanément (pas un filtre exclusif comme
  /// l'ancien `DropdownButton`).
  final Set<String> _practitionerFilter = <String>{};
  String _searchQuery = '';
  String? _selectedEntryId;

  final FocusNode _listFocusNode = FocusNode(debugLabel: 'agenda_list');
  final FocusNode _searchFocusNode = FocusNode(debugLabel: 'agenda_search');

  @override
  void initState() {
    super.initState();
    _selectedEntryId = widget.initialSelectedEntryId;
    // `autofocus` seul ne suffit pas ici : la route hôte (ModalRoute) prend
    // le focus initial en premier — demande explicite pour que
    // ←/→/↑/↓/⏎/T fonctionnent dès l'affichage de la grille, sans clic
    // préalable (même pattern que stock_page.dart, #5188).
    _listFocusNode.requestFocus();
  }

  @override
  void dispose() {
    _listFocusNode.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Map<String, String> get _practitioners {
    // #4666 : roster complet (via state.practitionerNames, résolu depuis
    // ListCabinetPractitionersUseCase) — ne pas reconstruire depuis
    // `entries` seules : un praticien sans créneau/RDV cette semaine
    // disparaissait alors du filtre et du picker « Nouveau RDV ».
    final practitioners = <String, String>{...widget.state.practitionerNames};
    for (final e in widget.state.entries) {
      if (e.practitionerName.isNotEmpty) {
        practitioners.putIfAbsent(e.practitionerId, () => e.practitionerName);
      }
    }
    return practitioners;
  }

  List<AgendaEntry> get _filteredEntries {
    final query = _searchQuery.trim().toLowerCase();
    return widget.state.entries.where((e) {
      if (_practitionerFilter.isNotEmpty &&
          !_practitionerFilter.contains(e.practitionerId)) {
        return false;
      }
      if (query.isEmpty) return true;
      return (e.patientName ?? '').toLowerCase().contains(query);
    }).toList();
  }

  void _togglePractitionerFilter(String practitionerId) {
    setState(() {
      if (!_practitionerFilter.remove(practitionerId)) {
        _practitionerFilter.add(practitionerId);
      }
    });
  }

  /// Créneaux libres affichés dans la grille (#5069/#5077) — mêmes créneaux
  /// bookables que le picker « Nouveau RDV » (#3466, [bookableSlots]), pour
  /// que la pastille cliquée dans la grille ouvre le dialogue avec un
  /// créneau qui ne déclenchera pas un 409 `slot_taken`. Filtrés par le
  /// même filtre praticien que la grille (pas par la recherche patient, qui
  /// ne s'applique pas à un créneau libre).
  List<Slot> get _filteredFreeSlots {
    final slots = bookableSlots(widget.state.availableSlots, widget.state.entries);
    if (_practitionerFilter.isEmpty) return slots;
    return slots
        .where((s) => _practitionerFilter.contains(s.practitionerId))
        .toList(growable: false);
  }

  void _selectEntry(String entryId) {
    setState(() => _selectedEntryId = entryId);
  }

  /// RDV pointé par [_selectedEntryId] (volet latéral, #5079) — cherche dans
  /// `widget.state.entries` plutôt que `_filteredEntries` : un changement de
  /// filtre praticien/recherche ne doit pas fermer le volet d'un RDV déjà
  /// sélectionné qui sort du filtre.
  AgendaEntry? get _selectedEntry {
    final id = _selectedEntryId;
    if (id == null) return null;
    for (final e in widget.state.entries) {
      if (e.id == id) return e;
    }
    return null;
  }

  void _loadWeek(DateTime weekStart) {
    context.read<AgendaBloc>().add(AgendaLoadRequested(weekStart: weekStart));
  }

  void _selectDelta(int delta, List<AgendaEntry> entries) {
    if (entries.isEmpty) return;
    final currentIndex = _selectedEntryId == null
        ? -1
        : entries.indexWhere((e) => e.id == _selectedEntryId);
    final next = (currentIndex + delta).clamp(0, entries.length - 1);
    setState(() => _selectedEntryId = entries[next].id);
  }

  void _confirmSelected(List<AgendaEntry> entries) {
    final index = _selectedEntryId == null
        ? -1
        : entries.indexWhere((e) => e.id == _selectedEntryId);
    if (index == -1) return;
    final selected = entries[index];
    // Même règle que le bouton Confirmer du volet (_AgendaDetailPanel) :
    // un RDV libre ou déjà confirmé n'a pas d'action ici (409 sinon).
    if (selected.isFree || selected.isConfirmed) return;
    context.read<AgendaBloc>().add(
          AgendaAppointmentConfirmRequested(appointmentId: selected.id),
        );
  }

  /// Raccourcis clavier agenda (maquette design-v2, pied de grille, #5082) :
  /// ←/→ semaine préc./suiv., ↑/↓ sélection RDV, ⏎ confirme la sélection, T
  /// revient à aujourd'hui, / focus la recherche patient. ⌘N/Ctrl+N est câblé
  /// via [CallbackShortcuts] dans [build] (#6413) ; ⌘K (palette de commandes)
  /// n'est PAS
  /// câblé ici : `ProShell`/`SecretariatShell` l'ouvre déjà globalement
  /// (recherche globale, #5389) et enveloppe cette page, donc le raccourci
  /// fonctionne déjà sur cet écran sans code dédié.
  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final entries = _filteredEntries;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowLeft:
        _loadWeek(widget.state.weekStart.subtract(const Duration(days: 7)));
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
        _loadWeek(widget.state.weekStart.add(const Duration(days: 7)));
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyT:
        _loadWeek(_currentWeekStart());
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowDown:
        _selectDelta(1, entries);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        _selectDelta(-1, entries);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.numpadEnter:
        _confirmSelected(entries);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.slash:
        if (!_searchFocusNode.hasFocus) {
          _searchFocusNode.requestFocus();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      default:
        return KeyEventResult.ignored;
    }
  }

  @override
  Widget build(BuildContext context) {
    final practitioners = _practitioners;
    final filteredEntries = _filteredEntries;

    void newAppointmentShortcut() {
      if (!widget.state.actionInProgress) {
        _showNewAppointmentDialog(context, widget.state, practitioners);
      }
    }

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyN, meta: true):
            newAppointmentShortcut,
        const SingleActivator(LogicalKeyboardKey.keyN, control: true):
            newAppointmentShortcut,
      },
      child: Focus(
        focusNode: _listFocusNode,
        onKeyEvent: _handleKey,
        // Stack (plutôt qu'un Row poussant le contenu principal) : le volet
        // (296px fixe) se superpose au lieu de rétrécir la grille — évite un
        // overflow des Row existants (barre d'outils, nav semaine…) non
        // conçus pour un viewport déjà étroit (mobile, cf. test #3896).
        child: Stack(
          children: [
            _buildBody(context, practitioners, filteredEntries),
            // Volet latéral détail du RDV sélectionné (maquette design-v2,
            // #5079) : seulement pour un RDV réel (pas un créneau libre, qui
            // n'a ni identité ni statut à détailler).
            if (_selectedEntry != null && !_selectedEntry!.isFree)
              Positioned(
                top: 0,
                right: 0,
                bottom: 0,
                child: _AgendaDetailPanel(
                  entry: _selectedEntry!,
                  practitionerNames: practitioners,
                  actionInProgress: widget.state.actionInProgress,
                  onClose: () => setState(() => _selectedEntryId = null),
                  onConfirm: () => context.read<AgendaBloc>().add(
                        AgendaAppointmentConfirmRequested(
                            appointmentId: _selectedEntry!.id),
                      ),
                  onReschedule: (newStartsAt) => context.read<AgendaBloc>().add(
                        AgendaAppointmentRescheduleRequested(
                          appointmentId: _selectedEntry!.id,
                          newStartsAt: newStartsAt,
                        ),
                      ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    Map<String, String> practitioners,
    List<AgendaEntry> filteredEntries,
  ) {
    return Column(
      children: [
        if (widget.state.actionInProgress)
          const LinearProgressIndicator(key: Key('agenda_action_progress')),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Agenda du cabinet',
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                    ),
                    const SizedBox(height: 2),
                    _AgendaStats(
                      rdvCount:
                          widget.state.entries.where((e) => !e.isFree).length,
                      pendingCount:
                          widget.state.entries.where((e) => e.isPending).length,
                      freeSlotsCount: bookableSlots(
                              widget.state.availableSlots, widget.state.entries)
                          .length,
                    ),
                  ],
                ),
              ),
              NubiaButton(
                key: const Key('new_appointment_button'),
                label: 'Nouveau RDV',
                icon: Icons.add,
                onPressed: widget.state.actionInProgress
                    ? null
                    : () => _showNewAppointmentDialog(
                          context,
                          widget.state,
                          practitioners,
                        ),
              ),
              const Padding(
                padding: EdgeInsets.only(left: 8),
                child: NubiaBadge.label(label: '⌘N'),
              ),
            ],
          ),
        ),
        _WeekNavBar(
          weekStart: widget.state.weekStart,
          onPrevWeek: () => _loadWeek(
              widget.state.weekStart.subtract(const Duration(days: 7))),
          onNextWeek: () =>
              _loadWeek(widget.state.weekStart.add(const Duration(days: 7))),
          onToday: () => _loadWeek(_currentWeekStart()),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _PractitionerFilterChips(
                  practitioners: practitioners,
                  entries: widget.state.entries,
                  selected: _practitionerFilter,
                  onToggle: _togglePractitionerFilter,
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 240,
                child: NubiaSearchBar(
                  key: const Key('agenda_patient_search'),
                  focusNode: _searchFocusNode,
                  hint: 'Rechercher un patient',
                  onChanged: (value) => setState(() => _searchQuery = value),
                  locationChip:
                      _searchQuery.isEmpty ? const _SearchShortcutHint() : null,
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: filteredEntries.isEmpty
              ? const NubiaEmptyState(
                  key: Key('agenda_empty'),
                  icon: Icons.calendar_month_outlined,
                  title: 'Aucun rendez-vous cette semaine',
                )
              : RefreshIndicator(
                  key: const Key('agenda_refresh_indicator'),
                  onRefresh: widget.onRefresh,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding:
                        const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                    child: _AgendaWeekGrid(
                      weekStart: widget.state.weekStart,
                      entries: filteredEntries,
                      freeSlots: _filteredFreeSlots,
                      practitionerNames: practitioners,
                      selectedEntryId: _selectedEntryId,
                      onEntryTap: _selectEntry,
                      onSlotTap: (slot) => _showNewAppointmentDialog(
                        context,
                        widget.state,
                        practitioners,
                        initialSlot: slot,
                      ),
                    ),
                  ),
                ),
        ),
        const _AgendaConfidentialityNotice(),
        if (practitioners.isNotEmpty || _filteredFreeSlots.isNotEmpty)
          _AgendaFootLegend(
            practitioners: practitioners,
            showFreeSlotHint: _filteredFreeSlots.isNotEmpty,
          ),
      ],
    );
  }

  void _showNewAppointmentDialog(
    BuildContext context,
    AgendaLoaded state,
    Map<String, String> practitioners, {
    Slot? initialSlot,
  }) {
    final availableSlots = bookableSlots(state.availableSlots, state.entries);
    showDialog<void>(
      context: context,
      builder: (_) => _NewAppointmentDialog(
        availableSlots: availableSlots,
        initialSlot: initialSlot,
        practitioners: practitioners,
        onConfirm: (appointment) => context.read<AgendaBloc>().add(
              AgendaAppointmentCreateRequested(appointment: appointment),
            ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

/// Mention de cloisonnement secrétariat (maquette design-v2, note #8, #5080) :
/// passait jusqu'ici par le seul commentaire de code sur `_EntryCard`
/// (aucune donnée clinique — motif administratif, praticien, uniquement).
/// La mention passe désormais à l'écran plutôt que dans le source.
class _AgendaConfidentialityNotice extends StatelessWidget {
  const _AgendaConfidentialityNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('agenda_confidentiality_notice'),
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: NubiaColors.n50,
        border: Border.all(color: NubiaColors.n200),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.shield, size: 18, color: NubiaColors.n400),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Aucune donnée clinique côté secrétariat — motif administratif '
              'uniquement, cloisonnement conservé.',
              style: TextStyle(fontSize: 11.5, color: NubiaColors.n600),
            ),
          ),
        ],
      ),
    );
  }
}

/// Trois compteurs nommés de la barre d'outils (maquette design-v2, #5081) :
/// RDV, à confirmer (teinté `warning` — c'est la file de travail du
/// secrétariat) et créneaux libres. Remplace l'ancien libellé ambigu
/// « N créneau(x) cette semaine » (mélangeait RDV et créneaux libres) et le
/// second compteur de disponibilités affiché plus bas dans la page.
class _AgendaStats extends StatelessWidget {
  const _AgendaStats({
    required this.rdvCount,
    required this.pendingCount,
    required this.freeSlotsCount,
  });

  final int rdvCount;
  final int pendingCount;
  final int freeSlotsCount;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final neutralStyle =
        textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant);

    return Row(
      children: [
        Flexible(
          child: Text(
            '$rdvCount RDV',
            key: const Key('agenda_stats_rdv'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: neutralStyle,
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            '$pendingCount à confirmer',
            key: const Key('agenda_stats_pending'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: neutralStyle?.copyWith(
              color: tokens.warningFg,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            '$freeSlotsCount créneaux libres',
            key: const Key('agenda_stats_free'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: neutralStyle,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

/// Rangée de puces à bascule du filtre praticien (maquette design-v2,
/// `secretariat-agenda.png`, #5076) — remplace le `DropdownButton` (coûtait
/// deux clics et cachait le roster). Roster complet via `practitioners`
/// (#4666 : un praticien sans RDV cette semaine reste affiché, « · 0 »).
/// Plusieurs puces peuvent être actives simultanément (filtre non exclusif,
/// cf. maquette).
class _PractitionerFilterChips extends StatelessWidget {
  const _PractitionerFilterChips({
    required this.practitioners,
    required this.entries,
    required this.selected,
    required this.onToggle,
  });

  final Map<String, String> practitioners;
  final List<AgendaEntry> entries;
  final Set<String> selected;
  final void Function(String practitionerId) onToggle;

  int _countFor(String practitionerId) => entries
      .where((e) => !e.isFree && e.practitionerId == practitionerId)
      .length;

  @override
  Widget build(BuildContext context) {
    // Défilement horizontal (plutôt qu'un Wrap) : un roster nombreux sur un
    // viewport étroit (mobile, cf. test #3896) ne doit pas comprimer une
    // puce sous sa largeur de contenu — l'ancien Row de compteurs a déjà
    // débordé pour cette raison.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final p in practitioners.entries) ...[
            NubiaChip(
              key: Key('practitioner_chip_${p.key}'),
              label: p.value,
              dotColor: practitionerColor(p.key),
              count: _countFor(p.key),
              selected: selected.contains(p.key),
              onTap: () => onToggle(p.key),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

/// Barre de navigation semaine (maquette design-v2, pied de grille, #5082) :
/// ←/→ (boutons ou raccourcis clavier) changent de semaine, bouton
/// « Aujourd'hui »/raccourci T revient à la semaine courante.
class _WeekNavBar extends StatelessWidget {
  const _WeekNavBar({
    required this.weekStart,
    required this.onPrevWeek,
    required this.onNextWeek,
    required this.onToday,
  });

  final DateTime weekStart;
  final VoidCallback onPrevWeek;
  final VoidCallback onNextWeek;
  final VoidCallback onToday;

  static const _months = [
    'jan.',
    'fév.',
    'mar.',
    'avr.',
    'mai',
    'juin',
    'juil.',
    'août',
    'sep.',
    'oct.',
    'nov.',
    'déc.',
  ];

  String get _label {
    final weekEnd = weekStart.add(const Duration(days: 6));
    final startMonth = _months[weekStart.month - 1];
    final endMonth = _months[weekEnd.month - 1];
    if (weekStart.month == weekEnd.month) {
      return 'Semaine du ${weekStart.day} au ${weekEnd.day} $startMonth '
          '${weekStart.year}';
    }
    return 'Semaine du ${weekStart.day} $startMonth au ${weekEnd.day} '
        '$endMonth ${weekEnd.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          IconButton(
            key: const Key('agenda_prev_week'),
            icon: const Icon(Icons.chevron_left),
            tooltip: 'Semaine précédente',
            onPressed: onPrevWeek,
          ),
          Expanded(
            child: Text(
              _label,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          IconButton(
            key: const Key('agenda_next_week'),
            icon: const Icon(Icons.chevron_right),
            tooltip: 'Semaine suivante',
            onPressed: onNextWeek,
          ),
          const SizedBox(width: 8),
          NubiaButton(
            key: const Key('agenda_today_button'),
            label: "Aujourd'hui",
            size: NubiaButtonSize.sm,
            variant: NubiaButtonVariant.tertiary,
            onPressed: onToday,
          ),
          const SizedBox(width: 6),
          const NubiaBadge.label(label: 'T'),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

/// Indice du raccourci clavier « / » — affiché à droite de la recherche
/// patient tant qu'elle est vide (maquette design-v2, pied de grille).
class _SearchShortcutHint extends StatelessWidget {
  const _SearchShortcutHint();

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: tokens.borderSubtle,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: tokens.borderDefault),
      ),
      child: Text(
        '/',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: tokens.textTertiary,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _NewAppointmentDialog extends StatefulWidget {
  const _NewAppointmentDialog({
    required this.availableSlots,
    required this.practitioners,
    required this.onConfirm,
    this.initialSlot,
  });

  final List<Slot> availableSlots;
  final Map<String, String> practitioners;
  final void Function(CabinetAppointment) onConfirm;

  /// Créneau pré-sélectionné (#5077 : clic sur une pastille de créneau
  /// libre de la grille) — le dialogue s'ouvre alors directement sur le
  /// créneau visé, sans repasser par le picker déroulant.
  final Slot? initialSlot;

  @override
  State<_NewAppointmentDialog> createState() => _NewAppointmentDialogState();
}

class _NewAppointmentDialogState extends State<_NewAppointmentDialog> {
  Slot? _selectedSlot;
  CabinetPatient? _selectedPatient;
  final _motifCtrl = TextEditingController();
  final _patientSearchCtrl = TextEditingController();
  String _patientQuery = '';

  // Le back attend un `patient_id` (UUID d'une fiche patient du cabinet), pas
  // un nom libre. On charge la liste des patients du cabinet pour la
  // recherche (#5078 : champ de recherche, plus un dropdown de toute la
  // patientèle).
  List<CabinetPatient> _patients = const [];
  bool _loadingPatients = true;
  String? _patientsError;

  @override
  void initState() {
    super.initState();
    _selectedSlot = widget.initialSlot;
    _loadPatients();
  }

  List<CabinetPatient> get _filteredPatients {
    final query = _patientQuery.trim().toLowerCase();
    if (query.isEmpty) return const [];
    return _patients
        .where((p) => p.fullName.toLowerCase().contains(query))
        .toList(growable: false);
  }

  Future<void> _loadPatients() async {
    final result = await GetIt.instance<ListCabinetPatientsUseCase>()();
    if (!mounted) return;
    result.fold(
      (failure) => setState(() {
        _loadingPatients = false;
        _patientsError = failure.message;
      }),
      (patients) => setState(() {
        _loadingPatients = false;
        _patients = patients;
      }),
    );
  }

  @override
  void dispose() {
    _motifCtrl.dispose();
    _patientSearchCtrl.dispose();
    super.dispose();
  }

  String _slotLabel(Slot slot) {
    const weekdays = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
    const months = [
      'jan.',
      'fév.',
      'mar.',
      'avr.',
      'mai',
      'juin',
      'juil.',
      'août',
      'sep.',
      'oct.',
      'nov.',
      'déc.',
    ];
    // Conversion via `.toLocal()` avant de lire heure/minute — évite le
    // piège UTC #3856 (les `DateTime` remontés par l'API sont en UTC).
    final d = slot.startsAt.toLocal();
    final h =
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    return '${weekdays[d.weekday - 1]} ${d.day} ${months[d.month - 1]} – $h';
  }

  /// Champ patient (#5078) : recherche par nom filtrant `_patients`, plutôt
  /// qu'un `DropdownButton` listant toute la patientèle. Le back attend un
  /// `patient_id` — la recherche résout donc vers un [CabinetPatient], pas un
  /// nom libre.
  Widget _buildPatientField(BuildContext context) {
    final selected = _selectedPatient;
    if (selected != null) {
      return InputDecorator(
        decoration: const InputDecoration(labelText: 'Patient *'),
        child: Row(
          key: const Key('patient_selected_row'),
          children: [
            Expanded(child: Text(selected.fullName)),
            IconButton(
              key: const Key('patient_selected_clear'),
              icon: const Icon(Icons.close),
              tooltip: 'Changer de patient',
              onPressed: () => setState(() {
                _selectedPatient = null;
                _patientQuery = '';
                _patientSearchCtrl.clear();
              }),
            ),
          ],
        ),
      );
    }

    final results = _filteredPatients;
    final textTheme = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Patient *',
          style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 4),
        NubiaSearchBar(
          key: const Key('patient_search_field'),
          controller: _patientSearchCtrl,
          hint: 'Rechercher un patient par nom',
          onChanged: (value) => setState(() => _patientQuery = value),
        ),
        if (_patientQuery.trim().isNotEmpty) ...[
          const SizedBox(height: 4),
          if (results.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Aucun patient trouvé',
                key: Key('patient_search_empty'),
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 160),
              child: SingleChildScrollView(
                key: const Key('patient_search_results'),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final p in results)
                      ListTile(
                        key: Key('patient_option_${p.id}'),
                        dense: true,
                        title: Text(p.fullName),
                        onTap: () => setState(() {
                          _selectedPatient = p;
                          _patientQuery = '';
                          _patientSearchCtrl.clear();
                        }),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasSlots = widget.availableSlots.isNotEmpty;
    final canCreate =
        hasSlots && _selectedSlot != null && _selectedPatient != null;

    return AlertDialog(
      title: const Text('Nouveau rendez-vous'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!hasSlots)
              const Text('Aucun créneau disponible cette semaine.')
            else ...[
              InputDecorator(
                decoration: const InputDecoration(labelText: 'Créneau'),
                child: DropdownButton<Slot>(
                  key: const Key('slot_picker_dropdown'),
                  isExpanded: true,
                  underline: const SizedBox.shrink(),
                  value: _selectedSlot,
                  hint: const Text('Sélectionner un créneau'),
                  items: widget.availableSlots
                      .map((s) => DropdownMenuItem(
                            value: s,
                            child: Text(_slotLabel(s)),
                          ))
                      .toList(),
                  onChanged: (s) => setState(() => _selectedSlot = s),
                ),
              ),
              const SizedBox(height: 12),
              if (_loadingPatients)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: LinearProgressIndicator(
                    key: Key('patient_picker_loading'),
                  ),
                )
              else if (_patientsError != null)
                Text(
                  _patientsError!,
                  key: const Key('patient_picker_error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                )
              else
                _buildPatientField(context),
              const SizedBox(height: 12),
              TextField(
                key: const Key('motif_field'),
                controller: _motifCtrl,
                decoration:
                    const InputDecoration(labelText: 'Motif (optionnel)'),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('cancel_appointment_button'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        if (hasSlots)
          FilledButton(
            key: const Key('create_appointment_button'),
            onPressed: canCreate
                ? () {
                    final slot = _selectedSlot!;
                    final patient = _selectedPatient!;
                    final motif = _motifCtrl.text.trim();
                    widget.onConfirm(
                      CabinetAppointment(
                        id: '',
                        cabinetId: slot.cabinetId,
                        patientId: patient.id,
                        patientName: patient.fullName,
                        practitionerId: slot.practitionerId,
                        practitionerName:
                            widget.practitioners[slot.practitionerId] ?? '',
                        startsAt: slot.startsAt,
                        duration: slot.duration,
                        motif: motif.isEmpty ? 'Consultation' : motif,
                        status: CabinetAppointmentStatus.requested,
                        // slot_id : champ obligatoire du contrat back.
                        slotId: slot.id,
                      ),
                    );
                    Navigator.of(context).pop();
                  }
                : null,
            child: const Text('Créer'),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

String _initialsFrom(String? name) {
  if (name == null || name.trim().isEmpty) return '–';
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.length == 1) {
    final p = parts.first;
    return (p.length <= 2 ? p : p.substring(0, 2)).toUpperCase();
  }
  return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
      .toUpperCase();
}

/// Libellé de statut d'un RDV — mêmes règles que `app_practicien/.../
/// agenda_page.dart` (`_statusLabel`) pour rester cohérent entre apps, sans
/// dépendance croisée entre packages d'app.
String _statusLabel(AgendaEntry entry) {
  if (entry.isCancelled) return 'Annulé';
  if (entry.isDone) return 'Terminé';
  if (entry.isInProgress) return 'En cours';
  if (entry.isNoShow) return 'Absent';
  if (entry.isCheckedIn) return 'Arrivé';
  if (entry.isConfirmed) return 'Confirmé';
  if (entry.isPending) return 'À confirmer';
  return 'Réservé';
}

/// Variante de couleur associée à [_statusLabel].
StatusPillVariant _statusVariant(AgendaEntry entry) {
  if (entry.isCancelled || entry.isNoShow) return StatusPillVariant.error;
  if (entry.isDone) return StatusPillVariant.info;
  if (entry.isInProgress || entry.isCheckedIn) return StatusPillVariant.warning;
  if (entry.isConfirmed) return StatusPillVariant.success;
  if (entry.isPending) return StatusPillVariant.warning;
  return StatusPillVariant.info;
}

// ---------------------------------------------------------------------------

/// Volet latéral détail du RDV sélectionné (maquette design-v2,
/// `secretariat-agenda.png`, #5079) — remplace la carte qui grossissait :
/// porte l'identité, le statut et les actions (Confirmer / Marquer arrivé /
/// Déplacer / Appeler) du RDV pointé dans la grille.
///
/// « Marquer arrivé » et « Appeler » sont désactivés avec un TODO explicite :
/// `AgendaEntry` n'expose ni téléphone patient, ni date de création, ni
/// couverture, et `AgendaBloc` n'a pas d'event de check-in (seul
/// `isCheckedIn` existe côté lecture) — cf. issue #5079, aucune valeur n'est
/// inventée pour ces champs back manquants.
class _AgendaDetailPanel extends StatelessWidget {
  const _AgendaDetailPanel({
    required this.entry,
    required this.practitionerNames,
    required this.actionInProgress,
    required this.onClose,
    required this.onConfirm,
    required this.onReschedule,
  });

  final AgendaEntry entry;
  final Map<String, String> practitionerNames;
  final bool actionInProgress;
  final VoidCallback onClose;
  final VoidCallback onConfirm;
  final void Function(DateTime newStartsAt) onReschedule;

  static const _weekdays = [
    'Lundi',
    'Mardi',
    'Mercredi',
    'Jeudi',
    'Vendredi',
    'Samedi',
    'Dimanche',
  ];

  static const _months = [
    'janvier',
    'février',
    'mars',
    'avril',
    'mai',
    'juin',
    'juillet',
    'août',
    'septembre',
    'octobre',
    'novembre',
    'décembre',
  ];

  String get _dateRangeLabel {
    // Conversion via `.toLocal()` avant de lire heure/minute — évite le
    // piège UTC #3856 (les `DateTime` remontés par l'API sont en UTC).
    final start = entry.startsAt.toLocal();
    final end = entry.endsAt.toLocal();
    final weekday = _weekdays[start.weekday - 1];
    final month = _months[start.month - 1];
    final startTime =
        '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}';
    final endTime =
        '${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')}';
    return '$weekday ${start.day} $month · $startTime – $endTime';
  }

  Future<void> _pickReschedule(BuildContext context) async {
    final newStartsAt = await showDialog<DateTime>(
      context: context,
      builder: (_) => _RescheduleDialog(initialStart: entry.startsAt),
    );
    if (newStartsAt != null) onReschedule(newStartsAt);
  }

  Widget _kv(BuildContext context, String label, String value) {
    final textTheme = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          Text(value, style: textTheme.bodyMedium),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final tokens = Theme.of(context).extension<NubiaTokens>()!;

    final practitionerName = entry.practitionerName.isNotEmpty
        ? entry.practitionerName
        : (practitionerNames[entry.practitionerId] ?? '—');

    final subtitleParts = <String>[
      if (entry.motif != null && entry.motif!.isNotEmpty) entry.motif!,
      '${entry.duration.inMinutes} min',
    ];

    const missingBackData = 'À créer — donnée back manquante';

    return Container(
      key: Key('agenda_detail_panel_${entry.id}'),
      width: 296,
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(left: BorderSide(color: tokens.borderDefault)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(-2, 0),
          ),
        ],
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.event, size: 18, color: cs.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(_dateRangeLabel, style: textTheme.titleSmall),
                ),
                IconButton(
                  key: const Key('agenda_detail_close'),
                  icon: const Icon(Icons.close),
                  tooltip: 'Fermer',
                  onPressed: onClose,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                NubiaAvatar(
                  initials: _initialsFrom(entry.patientName),
                  radius: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        entry.patientName ?? 'Patient',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.titleMedium?.copyWith(
                          color: cs.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        subtitleParts.join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            StatusPill(
              label: _statusLabel(entry),
              variant: _statusVariant(entry),
            ),
            const SizedBox(height: 16),
            _kv(context, 'Praticien', practitionerName),
            _kv(context, 'Téléphone', missingBackData),
            _kv(context, 'Créé le', missingBackData),
            _kv(context, 'Couverture', missingBackData),
            const SizedBox(height: 8),
            if (entry.isPending)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SizedBox(
                  width: double.infinity,
                  child: NubiaButton(
                    key: Key('confirm_${entry.id}'),
                    label: 'Confirmer',
                    icon: Icons.check,
                    onPressed: actionInProgress ? null : onConfirm,
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Tooltip(
                message: 'Check-in non branché : aucun event/use case '
                    'AgendaBloc pour marquer un RDV arrivé (TODO back, '
                    'issue #5079).',
                child: SizedBox(
                  width: double.infinity,
                  child: NubiaButton(
                    key: Key('checkin_${entry.id}'),
                    label: 'Marquer arrivé',
                    icon: Icons.how_to_reg,
                    // Désactivé : donnée back manquante, cf. commentaire de
                    // classe — ne pas simuler le check-in côté front.
                    onPressed: null,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SizedBox(
                width: double.infinity,
                child: NubiaButton(
                  key: Key('reschedule_${entry.id}'),
                  label: 'Déplacer',
                  icon: Icons.edit_calendar,
                  variant: NubiaButtonVariant.secondary,
                  onPressed:
                      actionInProgress ? null : () => _pickReschedule(context),
                ),
              ),
            ),
            Tooltip(
              message: 'Téléphone patient non disponible (donnée back à '
                  'créer, cf. commentaire de classe).',
              child: SizedBox(
                width: double.infinity,
                child: NubiaButton(
                  key: Key('call_${entry.id}'),
                  label: 'Appeler',
                  icon: Icons.call,
                  variant: NubiaButtonVariant.tertiary,
                  onPressed: null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

/// Dialogue « Déplacer » (maquette design-v2, #5079) : choix d'une nouvelle
/// date/heure puis dispatch de [AgendaAppointmentRescheduleRequested] (event
/// existant, agenda_event.dart) — même pattern date/heure que
/// `bookable_slots/create_slot_dialog.dart`.
class _RescheduleDialog extends StatefulWidget {
  const _RescheduleDialog({required this.initialStart});

  final DateTime initialStart;

  @override
  State<_RescheduleDialog> createState() => _RescheduleDialogState();
}

class _RescheduleDialogState extends State<_RescheduleDialog> {
  late DateTime _date = DateTime(
    widget.initialStart.year,
    widget.initialStart.month,
    widget.initialStart.day,
  );
  late TimeOfDay _time = TimeOfDay(
    hour: widget.initialStart.hour,
    minute: widget.initialStart.minute,
  );

  String _formatDate(DateTime d) => '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/'
      '${d.year}';

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Déplacer le rendez-vous'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            key: const Key('reschedule_date_tile'),
            leading: const Icon(Icons.calendar_today),
            title: Text(_formatDate(_date)),
            subtitle: const Text('Date'),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _date,
                firstDate: DateTime.now().subtract(const Duration(days: 365)),
                lastDate: DateTime.now().add(const Duration(days: 365)),
              );
              if (picked != null) setState(() => _date = picked);
            },
          ),
          ListTile(
            key: const Key('reschedule_time_tile'),
            leading: const Icon(Icons.access_time),
            title: Text(_time.format(context)),
            subtitle: const Text('Heure'),
            onTap: () async {
              final picked =
                  await showTimePicker(context: context, initialTime: _time);
              if (picked != null) setState(() => _time = picked);
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          key: const Key('confirm_reschedule_button'),
          onPressed: () => Navigator.of(context).pop(
            DateTime(
              _date.year,
              _date.month,
              _date.day,
              _time.hour,
              _time.minute,
            ),
          ),
          child: const Text('Déplacer'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

/// Rectangle au bord pointillé (maquette design-v2, créneau libre `.free`,
/// #5077) — Flutter n'a pas de `BorderStyle.dashed` natif, d'où ce
/// `CustomPainter` minimal plutôt qu'une dépendance externe pour un seul
/// usage.
class _DashedRectBox extends StatelessWidget {
  const _DashedRectBox({required this.child, this.borderRadius = 8});

  final Widget child;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedRectPainter(
        color: NubiaColors.n300,
        radius: borderRadius,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Container(color: Colors.white, child: child),
      ),
    );
  }
}

class _DashedRectPainter extends CustomPainter {
  _DashedRectPainter({required this.color, this.radius = 8});

  final Color color;
  final double radius;

  static const _dashWidth = 4.0;
  static const _dashSpace = 3.0;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Radius.circular(radius),
    );
    final outline = Path()..addRRect(rrect);
    final dashPath = Path();
    for (final metric in outline.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        dashPath.addPath(
          metric.extractPath(distance, distance + _dashWidth),
          Offset.zero,
        );
        distance += _dashWidth + _dashSpace;
      }
    }
    canvas.drawPath(dashPath, paint);
  }

  @override
  bool shouldRepaint(covariant _DashedRectPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}

// ---------------------------------------------------------------------------

/// Pastille + libellé d'une entrée de légende (couleur unie, ex. praticien ou
/// « À confirmer » — le créneau libre garde son propre rendu pointillé via
/// [_DashedRectBox], cf. [_AgendaFootLegend]).
class _LegendDot extends StatelessWidget {
  const _LegendDot({super.key, required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: cs.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// Légende de pied de grille (maquette design-v2, #5074/#5077) : associe
/// chaque couleur de bloc RDV (émeraude/sable/neutre, [_practitionerBlockStyle])
/// à un nom de praticien du roster complet (#4666 — un praticien sans RDV
/// cette semaine, ex. Dr Nadeau, reste dans la légende), plus l'état
/// « à confirmer » et le créneau libre pointillé (#5077, affiché seulement si
/// la semaine en contient un).
class _AgendaFootLegend extends StatelessWidget {
  const _AgendaFootLegend({
    required this.practitioners,
    required this.showFreeSlotHint,
  });

  final Map<String, String> practitioners;
  final bool showFreeSlotHint;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final entries = practitioners.entries.toList(growable: false);

    return Padding(
      key: const Key('agenda_foot_legend'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Wrap(
        spacing: 16,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final p in entries)
            _LegendDot(
              key: Key('agenda_legend_practitioner_${p.key}'),
              color: _practitionerBlockStyle(p.key, practitioners).border,
              label: p.value,
            ),
          _LegendDot(
            key: const Key('agenda_legend_pending'),
            color: tokens.warningFg,
            label: 'À confirmer',
          ),
          if (showFreeSlotHint)
            Row(
              key: const Key('agenda_free_slot_legend'),
              mainAxisSize: MainAxisSize.min,
              children: [
                _DashedRectBox(
                  borderRadius: 3,
                  child: const SizedBox(width: 14, height: 14),
                ),
                const SizedBox(width: 8),
                Text(
                  'Créneau libre — cliquer pour réserver',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          const _AgendaKeyboardShortcuts(),
        ],
      ),
    );
  }
}

/// Rappel des raccourcis clavier en pied de grille (maquette design-v2, `.kb`
/// — #6417) : les raccourcis eux-mêmes existent déjà (`_handleKey`), seul
/// leur affichage manquait, laissant un poste de secrétariat sans moyen de
/// les découvrir.
class _AgendaKeyboardShortcuts extends StatelessWidget {
  const _AgendaKeyboardShortcuts();

  static const _entries = [
    ('← →', 'semaine'),
    ('↑ ↓', 'RDV'),
    ('⏎', 'confirmer'),
    ('⌘K', 'commandes'),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Wrap(
      key: const Key('agenda_keyboard_shortcuts'),
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
                    .bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
      ],
    );
  }
}

/// Pastille façon touche clavier (`.kbd` de la maquette).
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

// ---------------------------------------------------------------------------

/// Couleur de bloc RDV par praticien (maquette design-v2, pied de grille,
/// #5074) : fond/bord/texte pour le 1er praticien du roster (émeraude), le
/// 2e (sable), au-delà (neutre) — indépendant de [practitionerColor] (pastille
/// #5168, cyclique par hash) : la maquette fixe explicitement « Dr Rousseau =
/// émeraude, Dr Lefèvre = sable », ce qui exige un rang plutôt qu'un hash.
class _PractitionerBlockStyle {
  const _PractitionerBlockStyle({
    required this.background,
    required this.border,
    required this.text,
  });

  final Color background;
  final Color border;
  final Color text;
}

const _practitionerBlockStyles = [
  _PractitionerBlockStyle(
    background: NubiaColors.brand50,
    border: NubiaColors.brand600,
    text: NubiaColors.brand800,
  ),
  _PractitionerBlockStyle(
    background: NubiaColors.sand50,
    border: NubiaColors.sand500,
    text: NubiaColors.sand700,
  ),
];

const _practitionerNeutralBlockStyle = _PractitionerBlockStyle(
  background: NubiaColors.n50,
  border: NubiaColors.n300,
  text: NubiaColors.n700,
);

/// Style de bloc pour `practitionerId`, dérivé de son rang dans
/// `practitionerNames` (roster, #4666) — même roster/ordre que la légende de
/// pied de grille, pour que couleur de bloc et couleur de légende
/// correspondent toujours. Stable d'une semaine à l'autre tant que l'ordre du
/// roster ne change pas côté back.
_PractitionerBlockStyle _practitionerBlockStyle(
  String practitionerId,
  Map<String, String> practitionerNames,
) {
  final index =
      practitionerNames.keys.toList(growable: false).indexOf(practitionerId);
  if (index < 0 || index >= _practitionerBlockStyles.length) {
    return _practitionerNeutralBlockStyle;
  }
  return _practitionerBlockStyles[index];
}

// ---------------------------------------------------------------------------
// Grille semaine (#5069/#6387) — gouttière d'heures + 6 colonnes de jours,
// avec les RDV rendus en blocs positionnés sur l'échelle horaire et les
// créneaux libres bookables en pastilles cliquables (#5077).
// ---------------------------------------------------------------------------

/// Échelle horaire de la grille (maquette design-v2, `secretariat-agenda.png`,
/// `.gut`/`.dcol`) : 1 heure = 56 px, plage affichée 08:00 → 19:00, gouttière
/// de 52 px, 6 colonnes de jours (Lun→Sam, dimanche non affiché).
const _agendaGutterWidth = 52.0;
const _agendaHourHeight = 56.0;
const _agendaStartHour = 8;
const _agendaEndHour = 19;
const _agendaDayCount = 6;
const _agendaPxPerMinute = _agendaHourHeight / 60;

double get _agendaGridHeight =>
    (_agendaEndHour - _agendaStartHour) * _agendaHourHeight;

/// Position verticale (haut/hauteur en px) d'un bloc sur l'échelle horaire
/// 08:00→19:00, en heure locale (`.toLocal()` — piège UTC #3856, les
/// `DateTime` remontés par l'API sont en UTC). L'intervalle est rogné aux
/// bornes de la grille (ex. un RDV commençant à 07:30 s'affiche depuis
/// 08:00) ; `null` si l'intervalle ne recoupe pas la plage affichée du tout
/// (ex. un RDV à 21:13, hors grille — toujours compté en en-tête, cf.
/// `_countFor`, mais pas dessiné).
class _AgendaBlockGeometry {
  const _AgendaBlockGeometry({required this.top, required this.height});
  final double top;
  final double height;
}

_AgendaBlockGeometry? _agendaBlockGeometry(DateTime startsAt, DateTime endsAt) {
  final start = startsAt.toLocal();
  final end = endsAt.toLocal();
  const gridStartMin = _agendaStartHour * 60;
  const gridEndMin = _agendaEndHour * 60;
  final startMin = start.hour * 60 + start.minute;
  final endMin = end.hour * 60 + end.minute;
  if (endMin <= gridStartMin || startMin >= gridEndMin) return null;
  final clampedStart = startMin < gridStartMin ? gridStartMin : startMin;
  final clampedEnd = endMin > gridEndMin ? gridEndMin : endMin;
  return _AgendaBlockGeometry(
    top: (clampedStart - gridStartMin) * _agendaPxPerMinute,
    height: (clampedEnd - clampedStart) * _agendaPxPerMinute,
  );
}

/// Grille semaine : une colonne par jour (`weekStart` + 0..5), positionnée
/// sur l'échelle horaire ci-dessus. [entries] alimente à la fois le compteur
/// par colonne (`.c` de la maquette) et les blocs RDV ; [freeSlots] les
/// pastilles de créneau libre (#5077).
class _AgendaWeekGrid extends StatelessWidget {
  const _AgendaWeekGrid({
    required this.weekStart,
    required this.entries,
    required this.freeSlots,
    required this.practitionerNames,
    required this.selectedEntryId,
    required this.onEntryTap,
    required this.onSlotTap,
  });

  final DateTime weekStart;
  final List<AgendaEntry> entries;
  final List<Slot> freeSlots;
  final Map<String, String> practitionerNames;
  final String? selectedEntryId;
  final void Function(String entryId) onEntryTap;
  final void Function(Slot slot) onSlotTap;

  List<DateTime> get _days => [
        for (var i = 0; i < _agendaDayCount; i++)
          DateTime(weekStart.year, weekStart.month, weekStart.day + i),
      ];

  bool _isSameDay(DateTime a, DateTime day) {
    final local = a.toLocal();
    return local.year == day.year &&
        local.month == day.month &&
        local.day == day.day;
  }

  int _countFor(DateTime day) =>
      entries.where((e) => _isSameDay(e.startsAt, day)).length;

  List<AgendaEntry> _entriesFor(DateTime day) => entries
      .where((e) => !e.isFree && !e.isCancelled && _isSameDay(e.startsAt, day))
      .toList(growable: false);

  List<Slot> _slotsFor(DateTime day) =>
      freeSlots.where((s) => _isSameDay(s.startsAt, day)).toList(growable: false);

  /// Jour courant (maquette design-v2, `.dh.now`/`.dcol.now` — #6417) :
  /// comparé en date locale, indépendamment de l'heure.
  bool _isToday(DateTime day) {
    final now = DateTime.now();
    return day.year == now.year && day.month == now.month && day.day == now.day;
  }

  @override
  Widget build(BuildContext context) {
    final days = _days;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const SizedBox(width: _agendaGutterWidth),
            for (final day in days)
              Expanded(
                child: _DayColumnHeader(
                  key: Key('agenda_day_header_${_dayKey(day)}'),
                  day: day,
                  count: _countFor(day),
                  isToday: _isToday(day),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _HourGutter(key: Key('agenda_hour_gutter')),
            for (var i = 0; i < days.length; i++)
              Expanded(
                child: _DayColumn(
                  key: Key('agenda_day_column_${_dayKey(days[i])}'),
                  showRightBorder: i < days.length - 1,
                  entries: _entriesFor(days[i]),
                  freeSlots: _slotsFor(days[i]),
                  practitionerNames: practitionerNames,
                  selectedEntryId: selectedEntryId,
                  onEntryTap: onEntryTap,
                  onSlotTap: onSlotTap,
                  isToday: _isToday(days[i]),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// En-tête de colonne jour (`.dhead`/`.dh` de la maquette) : jour abrégé en
/// capitales + numéro du jour (calculés depuis `weekStart` — donc une date
/// réelle, corrigeant le défaut « une semaine sans une seule date »), puis
/// compteur d'entrées du jour aligné à droite (`.c`).
class _DayColumnHeader extends StatelessWidget {
  const _DayColumnHeader({
    super.key,
    required this.day,
    required this.count,
    required this.isToday,
  });

  final DateTime day;
  final int count;
  final bool isToday;

  static const _weekdayAbbrevs = [
    'LUN',
    'MAR',
    'MER',
    'JEU',
    'VEN',
    'SAM',
    'DIM',
  ];

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      color: isToday ? NubiaColors.brand50 : null,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '${_weekdayAbbrevs[day.weekday - 1]} ',
                    style: textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: isToday ? NubiaColors.brand700 : NubiaColors.n700,
                    ),
                  ),
                  TextSpan(
                    text: '${day.day}',
                    style: textTheme.labelSmall?.copyWith(
                      color: isToday ? NubiaColors.brand800 : NubiaColors.n500,
                    ),
                  ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            '$count',
            key: Key('agenda_day_count_${_dayKey(day)}'),
            style: textTheme.labelSmall?.copyWith(
              color: NubiaColors.n400,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Gouttière d'heures (`.gut` de la maquette) : graduations 08:00 → 19:00,
/// une par heure, chiffres tabulaires (`tabular-nums`), fond `--n50`.
class _HourGutter extends StatelessWidget {
  const _HourGutter({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _agendaGutterWidth,
      height: _agendaGridHeight,
      color: NubiaColors.n50,
      child: Stack(
        // `Clip.none` : la dernière graduation (19:00) est ancrée au bord bas
        // de la grille — son texte déborderait légèrement d'un Stack aux
        // bords stricts (Clip.hardEdge, défaut), sans conséquence puisque
        // rien d'interactif ne vit dans ce débord.
        clipBehavior: Clip.none,
        children: [
          for (var h = _agendaStartHour; h <= _agendaEndHour; h++)
            Positioned(
              top: (h - _agendaStartHour) * _agendaHourHeight - 7,
              right: 6,
              child: Text(
                '${h.toString().padLeft(2, '0')}:00',
                style: const TextStyle(
                  fontSize: 11,
                  color: NubiaColors.n400,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Fond d'une colonne jour (`.dcol` de la maquette) : graduations 30 min
/// légères (`--n100`) et 1 h plus marquées (`--n200`), même échelle que
/// [_agendaHourHeight] (maquette : `repeating-linear-gradient … 55px 56px`
/// pour les heures, `27px 28px` pour les demi-heures). Bordure verticale
/// `--n200` entre colonnes.
class _DayColumn extends StatelessWidget {
  const _DayColumn({
    super.key,
    required this.showRightBorder,
    required this.entries,
    required this.freeSlots,
    required this.practitionerNames,
    required this.selectedEntryId,
    required this.onEntryTap,
    required this.onSlotTap,
    required this.isToday,
  });

  final bool showRightBorder;
  final List<AgendaEntry> entries;
  final List<Slot> freeSlots;
  final Map<String, String> practitionerNames;
  final String? selectedEntryId;
  final void Function(String entryId) onEntryTap;
  final void Function(Slot slot) onSlotTap;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final practitionerOrder = practitionerNames.keys.toList(growable: false);
    final items = <_LaneItem>[];
    for (final entry in entries) {
      final geometry = _agendaBlockGeometry(entry.startsAt, entry.endsAt);
      if (geometry == null) continue;
      items.add(_LaneItem(
        top: geometry.top,
        height: geometry.height,
        rank: _practitionerRank(entry.practitionerId, practitionerOrder),
        order: items.length,
        child: _AgendaEntryBlock(
          key: Key('entry_${entry.id}'),
          entry: entry,
          practitionerStyle:
              _practitionerBlockStyle(entry.practitionerId, practitionerNames),
          selected: entry.id == selectedEntryId,
          onTap: () => onEntryTap(entry.id),
        ),
      ));
    }
    for (final slot in freeSlots) {
      final geometry = _agendaBlockGeometry(slot.startsAt, slot.endsAt);
      if (geometry == null) continue;
      items.add(_LaneItem(
        top: geometry.top,
        height: geometry.height,
        rank: _practitionerRank(slot.practitionerId, practitionerOrder),
        order: items.length,
        child: _AgendaFreeSlotPill(
          key: Key('agenda_free_slot_${slot.id}'),
          slot: slot,
          onTap: () => onSlotTap(slot),
        ),
      ));
    }

    // #6395/#6393 : deux blocs qui se recouvrent dans le temps (RDV + pastille
    // de créneau libre d'un autre praticien, ex.) sont désormais répartis en
    // couloirs plutôt qu'empilés en `left: 0, right: 0` (le dernier peint
    // masquait systématiquement les autres). Les blocs qui ne se chevauchent
    // pas gardent la pleine largeur, comme avant.
    final blocks = [
      for (final laid in _layoutLanes(items))
        Positioned(
          top: laid.item.top,
          height: laid.item.height,
          left: 0,
          right: 0,
          child: laid.columns <= 1
              ? laid.item.child
              : Align(
                  alignment: Alignment(
                    laid.columns > 1
                        ? (2 * laid.columnIndex / (laid.columns - 1)) - 1
                        : 0,
                    0,
                  ),
                  child: FractionallySizedBox(
                    widthFactor: 1 / laid.columns,
                    child: laid.item.child,
                  ),
                ),
        ),
    ];

    final nowLineTop = isToday ? _currentTimeGridTop() : null;

    return Container(
      height: _agendaGridHeight,
      decoration: BoxDecoration(
        color: isToday ? NubiaColors.brand50 : null,
        border: showRightBorder
            ? const Border(right: BorderSide(color: NubiaColors.n200))
            : null,
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          const Positioned.fill(
            child: CustomPaint(
              size: Size.infinite,
              painter: _DayColumnGridPainter(),
            ),
          ),
          ...blocks,
          if (nowLineTop != null) _NowLine(top: nowLineTop),
        ],
      ),
    );
  }
}

/// Ligne d'heure courante (`.nowline` de la maquette) : uniquement dans la
/// colonne du jour, positionnée par [_currentTimeGridTop] sur la même échelle
/// que [_agendaBlockGeometry].
class _NowLine extends StatelessWidget {
  const _NowLine({required this.top});

  final double top;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    return Positioned(
      key: const Key('agenda_now_line'),
      top: top - 0.75,
      left: 0,
      right: 0,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(height: 1.5, color: tokens.dangerFg),
          Positioned(
            left: -4,
            top: -3.25,
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: tokens.dangerFg,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Position verticale de l'heure courante sur l'échelle 08:00→19:00
/// (`_agendaStartHour`/`_agendaEndHour`) — `null` hors de cette plage (ex.
/// poste ouvert avant 8 h ou après 19 h), auquel cas aucune ligne n'est
/// dessinée.
double? _currentTimeGridTop() {
  final now = DateTime.now();
  const gridStartMin = _agendaStartHour * 60;
  const gridEndMin = _agendaEndHour * 60;
  final nowMin = now.hour * 60 + now.minute;
  if (nowMin < gridStartMin || nowMin > gridEndMin) return null;
  return (nowMin - gridStartMin) * _agendaPxPerMinute;
}

/// Rang du praticien dans le roster affiché (même ordre que
/// [_practitionerBlockStyle]/légende) — sert à trier les couloirs de
/// [_layoutLanes] pour qu'un même praticien retombe toujours du même côté.
/// Praticien inconnu du roster (ex. #4666 : congé/désactivé) -> relégué en
/// dernier plutôt que planté.
int _practitionerRank(String practitionerId, List<String> practitionerOrder) {
  final index = practitionerOrder.indexOf(practitionerId);
  return index < 0 ? practitionerOrder.length : index;
}

/// Bloc temporel à placer dans un [_DayColumn] : RDV ou pastille de créneau
/// libre, avant répartition en couloirs par [_layoutLanes].
class _LaneItem {
  const _LaneItem({
    required this.top,
    required this.height,
    required this.rank,
    required this.order,
    required this.child,
  });

  final double top;
  final double height;
  final int rank;
  final int order;
  final Widget child;
}

class _LaidOutLaneItem {
  const _LaidOutLaneItem({
    required this.item,
    required this.columnIndex,
    required this.columns,
  });

  final _LaneItem item;
  final int columnIndex;
  final int columns;
}

/// Répartit [items] en couloirs quand ils se chevauchent dans le temps
/// (#6395/#6393) : un RDV et une pastille de créneau libre de deux
/// praticiens différents à la même heure doivent rester tous les deux
/// lisibles ("occupation croisée", maquette v2 point 3), au lieu du dernier
/// peint qui masquait l'autre en `left:0, right:0`. Les blocs isolés dans le
/// temps gardent la pleine largeur (`columns == 1`). Regroupement par
/// balayage trié sur `top` (les intervalles ne se recoupant pas partitionnent
/// exactement en composantes connexes), puis tri par [_practitionerRank]
/// dans chaque groupe pour un couloir stable par praticien.
List<_LaidOutLaneItem> _layoutLanes(List<_LaneItem> items) {
  if (items.isEmpty) return const [];
  final sorted = [...items]
    ..sort((a, b) {
      final byTop = a.top.compareTo(b.top);
      return byTop != 0 ? byTop : a.order.compareTo(b.order);
    });

  final result = <_LaidOutLaneItem>[];
  var clusterStart = 0;
  var clusterEnd = sorted.first.top + sorted.first.height;
  for (var i = 1; i <= sorted.length; i++) {
    if (i == sorted.length || sorted[i].top >= clusterEnd) {
      result.addAll(_assignLanes(sorted.sublist(clusterStart, i)));
      if (i < sorted.length) {
        clusterStart = i;
        clusterEnd = sorted[i].top + sorted[i].height;
      }
    } else {
      final end = sorted[i].top + sorted[i].height;
      if (end > clusterEnd) clusterEnd = end;
    }
  }
  return result;
}

List<_LaidOutLaneItem> _assignLanes(List<_LaneItem> cluster) {
  final ordered = [...cluster]
    ..sort((a, b) {
      final byRank = a.rank.compareTo(b.rank);
      return byRank != 0 ? byRank : a.order.compareTo(b.order);
    });
  final columns = ordered.length;
  return [
    for (var i = 0; i < ordered.length; i++)
      _LaidOutLaneItem(item: ordered[i], columnIndex: i, columns: columns),
  ];
}

/// Bloc RDV positionné (`.ev` de la maquette) — couleur par praticien
/// ([_practitionerBlockStyle]), sauf RDV à confirmer qui prend la teinte
/// `warning` (même code couleur que la pastille de légende
/// `agenda_legend_pending` et le [StatusPill] du volet). Sélectionné =
/// contour foncé (`.ev.sel`), sans changer la couleur de fond.
class _AgendaEntryBlock extends StatelessWidget {
  const _AgendaEntryBlock({
    super.key,
    required this.entry,
    required this.practitionerStyle,
    required this.selected,
    required this.onTap,
  });

  final AgendaEntry entry;
  final _PractitionerBlockStyle practitionerStyle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final style = entry.isPending
        ? _PractitionerBlockStyle(
            background: tokens.warningBg,
            border: tokens.warningFg,
            text: NubiaColors.n900,
          )
        : practitionerStyle;
    final subtitle = [
      if (entry.motif != null && entry.motif!.isNotEmpty) entry.motif!,
      if (entry.isPending) 'à confirmer',
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(7, 3, 5, 3),
            decoration: BoxDecoration(
              color: style.background,
              borderRadius: BorderRadius.circular(6),
              border: Border(left: BorderSide(color: style.border, width: 3)),
            ),
            foregroundDecoration: selected
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: NubiaColors.n900, width: 2),
                  )
                : null,
            // `SingleChildScrollView` (non défilant) plutôt qu'un `Column`
            // nu : un bloc de 30 min (28 px, cf. `_agendaHourHeight`) est
            // plus bas que nom + motif empilés — même rognage que le
            // `overflow:hidden` de la maquette (`.ev`), sans déclencher
            // l'assertion `RenderFlex overflowed` d'un Column trop plein.
            child: SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.patientName ?? 'Patient',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      height: 1.15,
                      color: style.text,
                    ),
                  ),
                  if (subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.15,
                        color: style.text,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Pastille de créneau libre bookable (`.free` de la maquette, #5077) —
/// bordure pointillée via [_DashedRectBox], clic ouvre le dialogue
/// « Nouveau RDV » avec ce créneau déjà choisi.
class _AgendaFreeSlotPill extends StatelessWidget {
  const _AgendaFreeSlotPill({
    super.key,
    required this.slot,
    required this.onTap,
  });

  final Slot slot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final start = slot.startsAt.toLocal();
    final label =
        '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: _DashedRectBox(
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.add, size: 13, color: NubiaColors.n400),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: NubiaColors.n400,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DayColumnGridPainter extends CustomPainter {
  const _DayColumnGridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final halfHourPaint = Paint()
      ..color = NubiaColors.n100
      ..strokeWidth = 1;
    final hourPaint = Paint()
      ..color = NubiaColors.n200
      ..strokeWidth = 1;
    var y = 0.0;
    var halfStep = 0;
    while (y <= size.height + 0.5) {
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        halfStep.isEven ? hourPaint : halfHourPaint,
      );
      y += _agendaHourHeight / 2;
      halfStep++;
    }
  }

  @override
  bool shouldRepaint(covariant _DayColumnGridPainter oldDelegate) => false;
}

// ---------------------------------------------------------------------------

/// Skeleton de chargement de l'agenda (barre d'outils + liste de cartes).
class _AgendaSkeleton extends StatelessWidget {
  const _AgendaSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const Key('agenda_loading'),
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: const [
            Expanded(child: NubiaSkeletonLoader(height: 24)),
            SizedBox(width: 12),
            NubiaSkeletonLoader(width: 132, height: 44, borderRadius: 8),
          ],
        ),
        const SizedBox(height: 16),
        const NubiaSkeletonLoader(height: 48, borderRadius: 8),
        const SizedBox(height: 16),
        for (var i = 0; i < 5; i++) ...[
          const NubiaSkeletonLoader(height: 76, borderRadius: 12),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}
