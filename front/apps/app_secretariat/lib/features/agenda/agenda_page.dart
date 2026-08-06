import 'dart:async';

import 'package:flutter/material.dart';
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
                    AgendaLoadRequested(weekStart: _currentWeekStart()),
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
  String? _practitionerFilter;

  @override
  Widget build(BuildContext context) {
    final practitioners = <String, String>{};
    for (final e in widget.state.entries) {
      practitioners[e.practitionerId] = e.practitionerName;
    }

    final filteredEntries = _practitionerFilter == null
        ? widget.state.entries
        : widget.state.entries
            .where((e) => e.practitionerId == _practitionerFilter)
            .toList();

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
                    Text(
                      '${widget.state.entries.length} créneau(x) cette semaine',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
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
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: InputDecorator(
            decoration: InputDecoration(
              isDense: true,
              labelText: 'Praticien',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                key: const Key('practitioner_filter_dropdown'),
                isExpanded: true,
                value: _practitionerFilter,
                onChanged: (v) => setState(() => _practitionerFilter = v),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Tous les praticiens'),
                  ),
                  for (final p in practitioners.entries)
                    DropdownMenuItem<String?>(
                      value: p.key,
                      child: Text(p.value),
                    ),
                ],
              ),
            ),
          ),
        ),
        const Divider(height: 1),
        if (widget.state.availableSlots.any((s) => s.isAvailable))
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              '${widget.state.availableSlots.where((s) => s.isAvailable).length} créneau(x) disponible(s)',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
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
                    itemCount: filteredEntries.length,
                    itemBuilder: (context, i) =>
                        _EntryCard(entry: filteredEntries[i]),
                  ),
                ),
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
}

// ---------------------------------------------------------------------------

class _NewAppointmentDialog extends StatefulWidget {
  const _NewAppointmentDialog({
    required this.availableSlots,
    required this.practitioners,
    required this.onConfirm,
  });

  final List<Slot> availableSlots;
  final Map<String, String> practitioners;
  final void Function(CabinetAppointment) onConfirm;

  @override
  State<_NewAppointmentDialog> createState() => _NewAppointmentDialogState();
}

class _NewAppointmentDialogState extends State<_NewAppointmentDialog> {
  Slot? _selectedSlot;
  CabinetPatient? _selectedPatient;
  final _motifCtrl = TextEditingController();

  // Le back attend un `patient_id` (UUID d'une fiche patient du cabinet), pas
  // un nom libre. On charge la liste des patients du cabinet pour la sélection.
  List<CabinetPatient> _patients = const [];
  bool _loadingPatients = true;
  String? _patientsError;

  @override
  void initState() {
    super.initState();
    _loadPatients();
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
                InputDecorator(
                  decoration: const InputDecoration(labelText: 'Patient *'),
                  child: DropdownButton<CabinetPatient>(
                    key: const Key('patient_picker_dropdown'),
                    isExpanded: true,
                    underline: const SizedBox.shrink(),
                    value: _selectedPatient,
                    hint: const Text('Sélectionner un patient'),
                    items: _patients
                        .map((p) => DropdownMenuItem(
                              value: p,
                              child: Text(p.fullName),
                            ))
                        .toList(),
                    onChanged: (p) => setState(() => _selectedPatient = p),
                  ),
                ),
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

class _EntryCard extends StatelessWidget {
  const _EntryCard({required this.entry});
  final AgendaEntry entry;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    final time =
        '${entry.startsAt.hour.toString().padLeft(2, '0')}:${entry.startsAt.minute.toString().padLeft(2, '0')}';
    final endTime =
        '${entry.endsAt.hour.toString().padLeft(2, '0')}:${entry.endsAt.minute.toString().padLeft(2, '0')}';

    // Sous-titre : motif administratif du RDV + praticien (aucune donnée
    // clinique — cloisonnement secrétariat).
    final subtitleParts = <String>[
      if (entry.motif != null && entry.motif!.isNotEmpty) entry.motif!,
      // #4608 : ne pas ajouter un nom de praticien vide (sinon un
      // séparateur ' · ' pendant apparaissait sur cette ligne).
      if (entry.practitionerName.isNotEmpty) entry.practitionerName,
    ];

    // Bloc statut (+ action Confirmer) séparé de la ligne nom/motif (#3896) :
    // avant ce fix, pastille + bouton partageaient le même Row que la colonne
    // nom (Expanded) — sur un viewport étroit (mobile 390px), leur largeur
    // intrinsèque non-flex ne laissait plus de place à l'Expanded, qui
    // retombait à ~0px et clippait le nom/motif à vide malgré une donnée
    // bien présente (confirmation « à l'aveugle » au comptoir).
    final Widget statusRow = entry.isFree
        ? const StatusPill(label: 'Libre', variant: StatusPillVariant.info)
        : entry.isConfirmed
            // RDV confirmé : plus d'action (un re-clic donnerait 409).
            ? const StatusPill(
                label: 'Confirmé',
                variant: StatusPillVariant.success,
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const StatusPill(
                    label: 'À confirmer',
                    variant: StatusPillVariant.warning,
                  ),
                  const SizedBox(width: 12),
                  NubiaButton(
                    key: Key('confirm_${entry.id}'),
                    label: 'Confirmer',
                    size: NubiaButtonSize.sm,
                    variant: NubiaButtonVariant.secondary,
                    onPressed: () => context.read<AgendaBloc>().add(
                          AgendaAppointmentConfirmRequested(
                              appointmentId: entry.id),
                        ),
                  ),
                ],
              );

    return Padding(
      key: Key('entry_${entry.id}'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: NubiaCard(
        padding: const EdgeInsets.all(16),
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
                          color: cs.onSurface,
                          fontWeight: FontWeight.w600,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      Text(
                        endTime,
                        style: textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                NubiaAvatar(
                  initials:
                      entry.isFree ? '+' : _initialsFrom(entry.patientName),
                  radius: 18,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.isFree
                            ? 'Créneau libre'
                            : (entry.patientName ?? 'Patient'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.titleMedium?.copyWith(
                          color: cs.onSurface,
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
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Align(alignment: Alignment.centerRight, child: statusRow),
          ],
        ),
      ),
    );
  }
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
