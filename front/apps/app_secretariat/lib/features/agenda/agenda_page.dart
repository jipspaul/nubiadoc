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
  const AgendaPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => GetIt.instance<AgendaBloc>()
        ..add(AgendaLoadRequested(weekStart: _currentWeekStart())),
      child: const _AgendaBody(),
    );
  }
}

// ---------------------------------------------------------------------------

class _AgendaBody extends StatefulWidget {
  const _AgendaBody();

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
          );
        }
        return const SizedBox.shrink();
      },
    );
  }
}

// ---------------------------------------------------------------------------

class _LoadedView extends StatefulWidget {
  const _LoadedView({required this.state, required this.onRefresh});
  final AgendaLoaded state;
  final Future<void> Function() onRefresh;

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
  /// revient à aujourd'hui, / focus la recherche patient. ⌘N est câblé via
  /// [CallbackShortcuts] dans [build] ; ⌘K (palette de commandes) n'est PAS
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

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyN, meta: true): () {
          if (!widget.state.actionInProgress) {
            _showNewAppointmentDialog(context, widget.state, practitioners);
          }
        },
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
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    // +1 : la note de cloisonnement (#5080) est le
                    // dernier item de la liste plutôt qu'un bandeau fixe
                    // sous l'Expanded — elle ne doit pas rogner la
                    // hauteur visible des cartes RDV.
                    itemCount: filteredEntries.length + 1,
                    itemBuilder: (context, i) {
                      if (i == filteredEntries.length) {
                        return const _AgendaConfidentialityNotice();
                      }
                      final entry = filteredEntries[i];
                      return _EntryCard(
                        entry: entry,
                        practitionerNames: practitioners,
                        selected: entry.id == _selectedEntryId,
                        onSelect: widget.state.actionInProgress
                            ? null
                            : () => entry.isFree
                                ? _openNewAppointmentForSlot(context, entry,
                                    widget.state, practitioners)
                                : setState(() => _selectedEntryId = entry.id),
                      );
                    },
                  ),
                ),
        ),
        if (practitioners.isNotEmpty || filteredEntries.any((e) => e.isFree))
          _AgendaFootLegend(
            practitioners: practitioners,
            showFreeSlotHint: filteredEntries.any((e) => e.isFree),
          ),
      ],
    );
  }

  void _showNewAppointmentDialog(
    BuildContext context,
    AgendaLoaded state,
    Map<String, String> practitioners,
  ) {
    final availableSlots = bookableSlots(state.availableSlots, state.entries);
    showDialog<void>(
      context: context,
      builder: (_) => _NewAppointmentDialog(
        availableSlots: availableSlots,
        practitioners: practitioners,
        onConfirm: (appointment) => context.read<AgendaBloc>().add(
              AgendaAppointmentCreateRequested(appointment: appointment),
            ),
      ),
    );
  }

  /// Ouvre le dialogue « Nouveau RDV » depuis un créneau libre de la grille
  /// (#5078) — le créneau est déjà choisi, le dialogue ne demande donc plus
  /// que le patient (recherche) + le motif.
  void _openNewAppointmentForSlot(
    BuildContext context,
    AgendaEntry freeEntry,
    AgendaLoaded state,
    Map<String, String> practitioners,
  ) {
    final slots = bookableSlots(state.availableSlots, state.entries);
    Slot? slot;
    for (final s in slots) {
      if (s.id == freeEntry.id) {
        slot = s;
        break;
      }
    }
    showDialog<void>(
      context: context,
      builder: (_) => _NewAppointmentDialog(
        availableSlots: slots,
        initialSlot: slot,
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
      return '${weekStart.day}–${weekEnd.day} $startMonth ${weekStart.year}';
    }
    return '${weekStart.day} $startMonth – ${weekEnd.day} $endMonth ${weekEnd.year}';
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

  /// Créneau déjà choisi dans la grille (#5078) — quand non nul, le
  /// dialogue masque le picker de créneau et l'affiche en lecture seule.
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
    final d = slot.startsAt;
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
    final hasSlots =
        widget.initialSlot != null || widget.availableSlots.isNotEmpty;
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
              if (widget.initialSlot != null)
                InputDecorator(
                  decoration: const InputDecoration(labelText: 'Créneau'),
                  child: Text(
                    _slotLabel(widget.initialSlot!),
                    key: const Key('slot_readonly_label'),
                  ),
                )
              else
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
    final start = entry.startsAt;
    final end = entry.endsAt;
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
        ],
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

class _EntryCard extends StatelessWidget {
  const _EntryCard({
    required this.entry,
    this.practitionerNames = const {},
    this.selected = false,
    this.onSelect,
  });
  final AgendaEntry entry;

  /// Roster practitioner_id -> nom (#4666), utilisé en repli quand
  /// `entry.practitionerName` est vide (ex : agenda enrichi par un slot
  /// dont le nom n'aurait pas été résolu côté DTO).
  final Map<String, String> practitionerNames;

  /// RDV actuellement sélectionné via navigation clavier ↑/↓ (#5082) —
  /// pilote le style `NubiaCard.selected` et affiche le badge ⏎ à côté du
  /// bouton Confirmer.
  final bool selected;
  final VoidCallback? onSelect;

  /// Créneau libre `.free` de la maquette design-v2 (#5077) : rectangle au
  /// bord pointillé `--n300`, fond blanc, contenu centré « + HH:MM » —
  /// rendu distinct de la carte RDV (pas d'avatar/praticien/statut, un
  /// créneau libre n'a pas d'identité patient).
  Widget _buildFreeSlot(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final time = '${entry.startsAt.hour.toString().padLeft(2, '0')}:'
        '${entry.startsAt.minute.toString().padLeft(2, '0')}';

    return Padding(
      key: Key('entry_${entry.id}'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: _DashedRectBox(
        borderRadius: 10,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            key: Key('free_slot_${entry.id}'),
            borderRadius: BorderRadius.circular(10),
            onTap: onSelect,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.add, size: 16, color: NubiaColors.n400),
                  const SizedBox(width: 4),
                  Text(
                    time,
                    style: textTheme.titleSmall?.copyWith(
                      color: NubiaColors.n400,
                      fontWeight: FontWeight.w600,
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

  /// Texte `#78350F` (amber-900) du bloc `.ev.tc` « à confirmer » (maquette
  /// design-v2, #5075) — même valeur que les autres surfaces `warning` à
  /// fond clair de l'app (ex. `treatment_plans/pending_quote_card.dart`).
  static const _pendingTextColor = Color(0xFF78350F);

  @override
  Widget build(BuildContext context) {
    if (entry.isFree) return _buildFreeSlot(context);

    final textTheme = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final isPending = entry.isPending;

    final time =
        '${entry.startsAt.hour.toString().padLeft(2, '0')}:${entry.startsAt.minute.toString().padLeft(2, '0')}';
    final endTime =
        '${entry.endsAt.hour.toString().padLeft(2, '0')}:${entry.endsAt.minute.toString().padLeft(2, '0')}';

    final practitionerName = entry.practitionerName.isNotEmpty
        ? entry.practitionerName
        : (practitionerNames[entry.practitionerId] ?? '');

    // Sous-titre : motif administratif du RDV + praticien (aucune donnée
    // clinique — cloisonnement secrétariat).
    final subtitleParts = <String>[
      if (entry.motif != null && entry.motif!.isNotEmpty) entry.motif!,
      // #4608 : ne pas ajouter un nom de praticien vide (sinon un
      // séparateur ' · ' pendant apparaissait sur cette ligne).
      if (practitionerName.isNotEmpty) practitionerName,
    ];

    // Couleur de bloc par praticien (maquette design-v2, #5074) : le fond
    // `warnBg` de l'état « à confirmer » (#5075) reste prioritaire — les deux
    // classes `.ev.tc` et `.ev.r`/`.ev.l` de la maquette sont mutuellement
    // exclusives, l'état d'action prime sur l'identité du praticien.
    final blockStyle = isPending || entry.practitionerId.isEmpty
        ? null
        : _practitionerBlockStyle(entry.practitionerId, practitionerNames);

    final primaryTextColor = isPending
        ? _pendingTextColor
        : (blockStyle?.text ?? cs.onSurface);
    final secondaryTextColor = isPending
        ? _pendingTextColor
        : (blockStyle?.text ?? cs.onSurfaceVariant);

    // Bloc `.ev.tc` (maquette design-v2, #5075) : l'état « à confirmer »
    // n'est plus signalé par une pastille + un bouton inline (déplacés dans
    // le volet de détail, #5079) mais directement par la couleur du bloc —
    // fond `warnBg`, bord gauche `warnFg`, texte `#78350F` — et un coin
    // cranté en haut à droite (triangle `warnFg` opacité .6).
    Widget card = NubiaCard(
      padding: const EdgeInsets.all(16),
      state: selected ? NubiaCardState.selected : NubiaCardState.interactive,
      backgroundColor: isPending ? tokens.warningBg : blockStyle?.background,
      borderColor: isPending ? null : blockStyle?.border,
      onTap: onSelect,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 56,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      time,
                      style: textTheme.titleMedium?.copyWith(
                        color: primaryTextColor,
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    Text(
                      endTime,
                      style: textTheme.bodySmall?.copyWith(
                        color: secondaryTextColor,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Pastille praticien (#5168) : même couleur, dérivée de
              // practitionerId via practitionerColor, que la colonne
              // Praticien de la salle d'attente.
              Container(
                key: Key('entry_practitioner_dot_${entry.id}'),
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: practitionerColor(entry.practitionerId),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              NubiaAvatar(
                initials: _initialsFrom(entry.patientName),
                radius: 18,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.patientName ?? 'Patient',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleMedium?.copyWith(
                        color: primaryTextColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (subtitleParts.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitleParts.join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodySmall?.copyWith(
                          color: secondaryTextColor,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );

    if (isPending) {
      card = ClipRRect(
        key: Key('entry_pending_${entry.id}'),
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            card,
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: Container(width: 3, color: tokens.warningFg),
            ),
            Positioned(
              top: 0,
              right: 0,
              child: CustomPaint(
                size: const Size(18, 18),
                painter: _NotchPainter(
                  color: tokens.warningFg.withValues(alpha: 0.6),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      key: Key('entry_${entry.id}'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: card,
    );
  }
}

/// Coin cranté du bloc `.ev.tc` (maquette design-v2, #5075) : triangle plein
/// posé dans le coin haut-droit, seul signal visuel (avec le fond `warnBg` et
/// le bord gauche `warnFg`) de l'état « à confirmer » dans la grille — les
/// actions (dont « Confirmer ») vivent désormais dans le volet de détail.
class _NotchPainter extends CustomPainter {
  _NotchPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width - size.height, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _NotchPainter oldDelegate) =>
      oldDelegate.color != color;
}

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
