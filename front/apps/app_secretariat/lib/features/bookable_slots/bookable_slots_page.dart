import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'bookable_slots_bloc.dart';
import 'bookable_slots_event.dart';
import 'bookable_slots_state.dart';
import 'create_slot_dialog.dart';

/// Body-only content for bookable slots. Can be embedded in any layout that
/// provides [BookableSlotsBloc] via [BlocProvider] (e.g. [ProShell]
/// bodyBuilder or the full-page [BookableSlotsPage]).
class BookableSlotsBody extends StatefulWidget {
  const BookableSlotsBody({super.key});

  @override
  State<BookableSlotsBody> createState() => _BookableSlotsBodyState();
}

class _BookableSlotsBodyState extends State<BookableSlotsBody> {
  // Filtres (#3467) : le cabinet gère 16 médecins × 3 semaines ≈ 4000 créneaux.
  // Sans filtre ni regroupement, l'écran est inexploitable.
  String? _practitionerId;
  DateTime? _day;

  // Pagination : on ne rend qu'un lot de créneaux à la fois.
  static const int _pageSize = 50;
  int _visible = _pageSize;

  @override
  void initState() {
    super.initState();
    context.read<BookableSlotsBloc>().add(const BookableSlotsLoadRequested());
  }

  void _resetPagination() => _visible = _pageSize;

  @override
  Widget build(BuildContext context) {
    return BlocListener<BookableSlotsBloc, BookableSlotsState>(
      listenWhen: (_, state) => state is BookableSlotsSlotCreatedSuccess,
      listener: (context, _) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Créneau ajouté')),
        );
      },
      child: BlocBuilder<BookableSlotsBloc, BookableSlotsState>(
        // SlotCreatedSuccess est transitoire : on garde l'affichage précédent
        // pendant le rechargement pour éviter un flash de spinner.
        buildWhen: (_, state) => state is! BookableSlotsSlotCreatedSuccess,
        builder: (context, state) {
          if (state is BookableSlotsLoaded) {
            return _LoadedView(
              state: state,
              practitionerId: _practitionerId,
              day: _day,
              visible: _visible,
              onPractitionerChanged: (v) => setState(() {
                _practitionerId = v;
                _resetPagination();
              }),
              onDayChanged: (v) => setState(() {
                _day = v;
                _resetPagination();
              }),
              onShowMore: () => setState(() => _visible += _pageSize),
            );
          }
          if (state is BookableSlotsError) {
            return NubiaErrorWidget(
              message: state.message,
              onRetry: () => context
                  .read<BookableSlotsBloc>()
                  .add(const BookableSlotsLoadRequested()),
            );
          }
          // BookableSlotsInitial, BookableSlotsLoading
          return const _BookableSlotsSkeleton();
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Modèle de lignes aplaties (en-tête praticien / en-tête jour / créneau).
// ---------------------------------------------------------------------------

abstract class _Row {
  const _Row();
}

class _PractitionerHeaderRow extends _Row {
  const _PractitionerHeaderRow(this.name, this.count);
  final String name;
  final int count;
}

class _DayHeaderRow extends _Row {
  const _DayHeaderRow(this.label);
  final String label;
}

class _SlotItemRow extends _Row {
  const _SlotItemRow(this.slot, this.practitionerName);
  final Slot slot;
  final String practitionerName;
}

class _LoadedView extends StatelessWidget {
  const _LoadedView({
    required this.state,
    required this.practitionerId,
    required this.day,
    required this.visible,
    required this.onPractitionerChanged,
    required this.onDayChanged,
    required this.onShowMore,
  });

  final BookableSlotsLoaded state;
  final String? practitionerId;
  final DateTime? day;
  final int visible;
  final ValueChanged<String?> onPractitionerChanged;
  final ValueChanged<DateTime?> onDayChanged;
  final VoidCallback onShowMore;

  static const List<String> _months = [
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
  static const List<String> _weekdays = [
    'lundi',
    'mardi',
    'mercredi',
    'jeudi',
    'vendredi',
    'samedi',
    'dimanche',
  ];

  String _dayLabel(DateTime d) =>
      '${_weekdays[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}';

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final names = <String, String>{
      for (final p in state.practitioners) p.id: p.displayName,
    };
    String nameOf(String id) => names[id] ?? 'Praticien';

    // 1) Filtres praticien + jour.
    final filtered = state.slots.where((s) {
      if (practitionerId != null && s.practitionerId != practitionerId) {
        return false;
      }
      if (day != null && !_sameDay(s.startsAt, day!)) return false;
      return true;
    }).toList();

    // 2) Tri praticien (nom) puis date de début.
    filtered.sort((a, b) {
      final byName = nameOf(a.practitionerId)
          .toLowerCase()
          .compareTo(nameOf(b.practitionerId).toLowerCase());
      if (byName != 0) return byName;
      return a.startsAt.compareTo(b.startsAt);
    });

    // 3) Comptage par praticien (pour l'en-tête).
    final countByPract = <String, int>{};
    for (final s in filtered) {
      countByPract[s.practitionerId] =
          (countByPract[s.practitionerId] ?? 0) + 1;
    }

    // 4) Aplatissement en lignes, avec pagination sur le nombre de créneaux.
    final rows = <_Row>[];
    String? curPract;
    DateTime? curDay;
    var shown = 0;
    var hasMore = false;
    for (final s in filtered) {
      if (shown >= visible) {
        hasMore = true;
        break;
      }
      if (curPract != s.practitionerId) {
        curPract = s.practitionerId;
        curDay = null;
        rows.add(_PractitionerHeaderRow(
          nameOf(s.practitionerId),
          countByPract[s.practitionerId] ?? 0,
        ));
      }
      if (curDay == null || !_sameDay(curDay, s.startsAt)) {
        curDay = s.startsAt;
        rows.add(_DayHeaderRow(_dayLabel(s.startsAt)));
      }
      rows.add(_SlotItemRow(s, nameOf(s.practitionerId)));
      shown++;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FilterBar(
          practitioners: state.practitioners,
          practitionerId: practitionerId,
          day: day,
          totalShown: filtered.length,
          onPractitionerChanged: onPractitionerChanged,
          onDayChanged: onDayChanged,
        ),
        const Divider(height: 1),
        Expanded(
          child: filtered.isEmpty
              ? const NubiaEmptyState(
                  icon: Icons.event_available_outlined,
                  title: 'Aucun créneau',
                  subtitle: 'Aucun créneau pour ce filtre.',
                )
              : ListView.builder(
                  key: const Key('bookable_slots_list'),
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                  itemCount: rows.length + (hasMore ? 1 : 0),
                  itemBuilder: (context, i) {
                    if (i >= rows.length) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Center(
                          child: OutlinedButton.icon(
                            key: const Key('show_more_slots_button'),
                            onPressed: onShowMore,
                            icon: const Icon(Icons.expand_more),
                            label: const Text('Voir plus de créneaux'),
                          ),
                        ),
                      );
                    }
                    final row = rows[i];
                    if (row is _PractitionerHeaderRow) {
                      return _PractitionerHeader(
                        name: row.name,
                        count: row.count,
                      );
                    }
                    if (row is _DayHeaderRow) {
                      return _DayHeader(label: row.label);
                    }
                    row as _SlotItemRow;
                    return _SlotCard(
                      slot: row.slot,
                      practitionerName: row.practitionerName,
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.practitioners,
    required this.practitionerId,
    required this.day,
    required this.totalShown,
    required this.onPractitionerChanged,
    required this.onDayChanged,
  });

  final List<CabinetPractitioner> practitioners;
  final String? practitionerId;
  final DateTime? day;
  final int totalShown;
  final ValueChanged<String?> onPractitionerChanged;
  final ValueChanged<DateTime?> onDayChanged;

  String _dateChipLabel(DateTime d) => '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (practitioners.isNotEmpty)
            InputDecorator(
              decoration: InputDecoration(
                isDense: true,
                labelText: 'Praticien',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String?>(
                  key: const Key('slots_practitioner_filter'),
                  isExpanded: true,
                  value: practitionerId,
                  onChanged: onPractitionerChanged,
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Tous les praticiens'),
                    ),
                    for (final p in practitioners)
                      DropdownMenuItem<String?>(
                        value: p.id,
                        child: Text(p.displayName),
                      ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('slots_date_filter'),
                  icon: const Icon(Icons.calendar_today, size: 18),
                  label: Text(
                    day == null ? 'Toutes les dates' : _dateChipLabel(day!),
                  ),
                  onPressed: () async {
                    final now = DateTime.now();
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: day ?? now,
                      firstDate: DateTime(now.year, now.month, now.day),
                      lastDate: now.add(const Duration(days: 365)),
                    );
                    if (picked != null) onDayChanged(picked);
                  },
                ),
              ),
              if (day != null) ...[
                const SizedBox(width: 8),
                IconButton(
                  key: const Key('slots_date_clear'),
                  tooltip: 'Effacer la date',
                  icon: const Icon(Icons.clear),
                  onPressed: () => onDayChanged(null),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '$totalShown créneau(x)',
            style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _PractitionerHeader extends StatelessWidget {
  const _PractitionerHeader({required this.name, required this.count});
  final String name;
  final int count;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
      child: Row(
        children: [
          Icon(Icons.person_outline, size: 18, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              name,
              style: textTheme.titleMedium?.copyWith(
                color: cs.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            '$count',
            style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 0, 6),
      child: Text(
        label,
        style: textTheme.labelLarge?.copyWith(
          color: cs.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class BookableSlotsPage extends StatefulWidget {
  const BookableSlotsPage({super.key});

  @override
  State<BookableSlotsPage> createState() => _BookableSlotsPageState();
}

class _BookableSlotsPageState extends State<BookableSlotsPage> {
  Future<void> _openCreateSlotDialog() async {
    final bloc = context.read<BookableSlotsBloc>();
    final state = bloc.state;
    final practitioners = state is BookableSlotsLoaded
        ? state.practitioners
        : const <CabinetPractitioner>[];
    final result = await showDialog<CreateSlotResult>(
      context: context,
      builder: (_) => CreateSlotDialog(practitioners: practitioners),
    );
    if (result == null || !mounted) return;
    bloc.add(
      CreateSlotRequested(
        practitionerId: result.practitionerId,
        startsAt: result.startsAt,
        endsAt: result.endsAt,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Créneaux disponibles'),
        actions: [
          IconButton(
            tooltip: 'Actualiser',
            icon: const Icon(Icons.refresh),
            onPressed: () => context
                .read<BookableSlotsBloc>()
                .add(const BookableSlotsLoadRequested()),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('create_slot_fab'),
        onPressed: _openCreateSlotDialog,
        icon: const Icon(Icons.add),
        label: const Text('Créer un créneau'),
      ),
      body: const BookableSlotsBody(),
    );
  }
}

class _SlotCard extends StatelessWidget {
  const _SlotCard({required this.slot, required this.practitionerName});

  final Slot slot;
  final String practitionerName;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final tokens = Theme.of(context).extension<NubiaTokens>()!;

    final start = TimeOfDay.fromDateTime(slot.startsAt);
    final end = TimeOfDay.fromDateTime(slot.endsAt);
    final timeLabel = '${start.format(context)} – ${end.format(context)}';

    final Color accentFg = slot.isAvailable ? cs.primary : tokens.textTertiary;
    final Color accentBg =
        slot.isAvailable ? tokens.primarySubtleBg : cs.surfaceContainerHighest;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: NubiaCard(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: accentBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                slot.isAvailable
                    ? Icons.event_available_outlined
                    : Icons.event_busy_outlined,
                size: 22,
                color: accentFg,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    timeLabel,
                    style: textTheme.titleMedium?.copyWith(
                      color: cs.onSurface,
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    practitionerName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            slot.isAvailable
                ? const StatusPill(
                    label: 'Disponible',
                    variant: StatusPillVariant.success,
                  )
                : const StatusPill(
                    label: 'Indisponible',
                    variant: StatusPillVariant.warning,
                  ),
          ],
        ),
      ),
    );
  }
}

/// Skeleton de chargement des créneaux réservables (liste de cartes).
class _BookableSlotsSkeleton extends StatelessWidget {
  const _BookableSlotsSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      children: [
        for (var i = 0; i < 6; i++) ...[
          const NubiaSkeletonLoader(height: 72, borderRadius: 12),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}
