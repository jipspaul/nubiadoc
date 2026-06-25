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

class _AgendaBody extends StatelessWidget {
  const _AgendaBody();

  @override
  Widget build(BuildContext context) {
    return BlocListener<AgendaBloc, AgendaState>(
      listenWhen: (_, current) =>
          current is AgendaLoaded && current.actionError != null,
      listener: (context, state) {
        if (state is AgendaLoaded && state.actionError != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.actionError!)),
          );
        }
      },
      child: BlocBuilder<AgendaBloc, AgendaState>(
        builder: (context, state) {
          if (state is AgendaInitial || state is AgendaLoading) {
            return const Center(
              key: Key('agenda_loading'),
              child: CircularProgressIndicator(),
            );
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
            return _LoadedView(state: state);
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _LoadedView extends StatefulWidget {
  const _LoadedView({required this.state});
  final AgendaLoaded state;

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
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${widget.state.entries.length} créneau(x) cette semaine',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              FilledButton.icon(
                key: const Key('new_appointment_button'),
                onPressed: widget.state.actionInProgress
                    ? null
                    : () => _showNewAppointmentDialog(
                          context,
                          widget.state,
                          practitioners,
                        ),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Nouveau RDV'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
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
        const Divider(height: 1),
        if (widget.state.availableSlots.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              '${widget.state.availableSlots.length} créneau(x) disponible(s)',
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
                  onRefresh: () async => context.read<AgendaBloc>().add(
                        AgendaLoadRequested(weekStart: _currentWeekStart()),
                      ),
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
    final availableSlots =
        state.availableSlots.where((s) => s.isAvailable).toList();
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
  final _patientNameCtrl = TextEditingController();
  final _motifCtrl = TextEditingController();

  @override
  void dispose() {
    _patientNameCtrl.dispose();
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
    final canCreate = hasSlots &&
        _selectedSlot != null &&
        _patientNameCtrl.text.trim().isNotEmpty;

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
              TextField(
                key: const Key('patient_name_field'),
                controller: _patientNameCtrl,
                decoration:
                    const InputDecoration(labelText: 'Nom du patient *'),
                textCapitalization: TextCapitalization.words,
                onChanged: (_) => setState(() {}),
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
                    final patientName = _patientNameCtrl.text.trim();
                    final motif = _motifCtrl.text.trim();
                    widget.onConfirm(
                      CabinetAppointment(
                        id: '',
                        cabinetId: slot.cabinetId,
                        patientId:
                            patientName.toLowerCase().replaceAll(' ', '-'),
                        patientName: patientName,
                        practitionerId: slot.practitionerId,
                        practitionerName:
                            widget.practitioners[slot.practitionerId] ?? '',
                        startsAt: slot.startsAt,
                        duration: slot.duration,
                        motif: motif.isEmpty ? 'Consultation' : motif,
                        status: CabinetAppointmentStatus.requested,
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

class _EntryCard extends StatelessWidget {
  const _EntryCard({required this.entry});
  final AgendaEntry entry;

  @override
  Widget build(BuildContext context) {
    final time =
        '${entry.startsAt.hour.toString().padLeft(2, '0')}:${entry.startsAt.minute.toString().padLeft(2, '0')}';

    return Card(
      key: Key('entry_${entry.id}'),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: ListTile(
        leading: CircleAvatar(
          child: Text(time, style: const TextStyle(fontSize: 11)),
        ),
        title: Text(entry.patientName ?? 'Créneau libre'),
        subtitle: entry.motif != null ? Text(entry.motif!) : null,
        trailing: entry.isFree
            ? null
            : FilledButton.tonal(
                key: Key('confirm_${entry.id}'),
                onPressed: () => context.read<AgendaBloc>().add(
                      AgendaAppointmentConfirmRequested(
                          appointmentId: entry.id),
                    ),
                child: const Text('Confirmer'),
              ),
      ),
    );
  }
}
