import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'modify_rdv_bloc.dart';
import 'modify_rdv_event.dart';
import 'modify_rdv_state.dart';

const _weekdays = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
const _months = [
  'jan',
  'fév',
  'mar',
  'avr',
  'mai',
  'jun',
  'jul',
  'aoû',
  'sep',
  'oct',
  'nov',
  'déc',
];

String _dayHeader(DateTime utc) {
  final dt = utc.toLocal();
  return '${_weekdays[dt.weekday - 1]} ${dt.day} ${_months[dt.month - 1]}';
}

String _hhmm(DateTime utc) {
  final dt = utc.toLocal();
  return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}

/// Écran "Modifier le rendez-vous".
///
/// L'API (`PATCH /v1/appointments/:id`) n'expose aujourd'hui qu'une seule
/// option de modification : proposer une nouvelle date/heure avec le même
/// praticien. La structure de l'écran (options en section) permet d'ajouter
/// d'autres options le jour où l'API les exposera.
class ModifyRdvPage extends StatelessWidget {
  const ModifyRdvPage({required this.appointmentId, super.key});
  final String appointmentId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => GetIt.instance<ModifyRdvBloc>()
        ..add(ModifyRdvLoadRequested(appointmentId)),
      child: _ModifyRdvBody(appointmentId: appointmentId),
    );
  }
}

// ---------------------------------------------------------------------------

class _ModifyRdvBody extends StatelessWidget {
  const _ModifyRdvBody({required this.appointmentId});
  final String appointmentId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Modifier le rendez-vous')),
      body: BlocConsumer<ModifyRdvBloc, ModifyRdvState>(
        listener: (context, state) {
          if (state is ModifyRdvSuccess) {
            Navigator.of(context).pop(true);
          }
          if (state is ModifyRdvLoaded && state.error != null) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(state.error!)));
          }
        },
        builder: (context, state) {
          if (state is ModifyRdvInitial || state is ModifyRdvLoading) {
            return const Center(
              key: Key('modify_rdv_loading'),
              child: CircularProgressIndicator(),
            );
          }
          if (state is ModifyRdvError) {
            return NubiaErrorWidget(
              key: const Key('modify_rdv_error'),
              message: state.message,
              onRetry: () => context.read<ModifyRdvBloc>().add(
                    ModifyRdvLoadRequested(appointmentId),
                  ),
            );
          }
          if (state is ModifyRdvLoaded) {
            return _LoadedView(state: state);
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _LoadedView extends StatelessWidget {
  const _LoadedView({required this.state});
  final ModifyRdvLoaded state;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (state.submitting)
          const LinearProgressIndicator(key: Key('modify_rdv_progress')),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: _CurrentAppointmentCard(appointment: state.appointment),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Text(
            'Nouvelle date/heure',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(
          child: state.slots.isEmpty
              ? const NubiaEmptyState(
                  key: Key('modify_rdv_no_slots'),
                  icon: Icons.event_busy_outlined,
                  title: 'Aucun créneau disponible.',
                  subtitle: 'Revenez plus tard pour ce praticien.',
                )
              : _SlotsByDay(
                  slots: state.slots,
                  selectedSlot: state.selectedSlot,
                ),
        ),
        if (state.selectedSlot != null) _ConfirmPanel(state: state),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _CurrentAppointmentCard extends StatelessWidget {
  const _CurrentAppointmentCard({required this.appointment});
  final Appointment appointment;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return NubiaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Rendez-vous actuel',
            style: textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            // #3825 : pas de « · » pendant quand la spécialité est vide.
            appointment.practitionerSpecialty.isEmpty
                ? appointment.practitionerName
                : '${appointment.practitionerName} · ${appointment.practitionerSpecialty}',
            style: textTheme.titleSmall,
          ),
          const SizedBox(height: 2),
          Text(
            '${_dayHeader(appointment.startsAt)} à ${_hhmm(appointment.startsAt)}',
            style: textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _SlotsByDay extends StatelessWidget {
  const _SlotsByDay({required this.slots, required this.selectedSlot});
  final List<Slot> slots;
  final Slot? selectedSlot;

  @override
  Widget build(BuildContext context) {
    final groups = <DateTime, List<Slot>>{};
    for (final slot in slots) {
      final key = DateTime(
        slot.startsAt.year,
        slot.startsAt.month,
        slot.startsAt.day,
      );
      groups.putIfAbsent(key, () => []).add(slot);
    }

    return ListView(
      key: const Key('modify_rdv_slots_list'),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      children: [
        for (final entry in groups.entries) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              _dayHeader(entry.key),
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final slot in entry.value)
                IntrinsicWidth(
                  child: SlotChip(
                    label: _hhmm(slot.startsAt),
                    state: !slot.isAvailable
                        ? SlotChipState.unavailable
                        : selectedSlot?.id == slot.id
                            ? SlotChipState.selected
                            : SlotChipState.available,
                    onTap: slot.isAvailable
                        ? () => context.read<ModifyRdvBloc>().add(
                              ModifyRdvSlotSelected(slot),
                            )
                        : null,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _ConfirmPanel extends StatelessWidget {
  const _ConfirmPanel({required this.state});
  final ModifyRdvLoaded state;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>();
    final borderColor = tokens?.borderSubtle ?? Theme.of(context).dividerColor;
    final slot = state.selectedSlot!;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(top: BorderSide(color: borderColor)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Nouveau créneau : ${_dayHeader(slot.startsAt)} à ${_hhmm(slot.startsAt)}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: NubiaButton(
              key: const Key('confirm_modify_rdv_button'),
              label: 'Confirmer la modification',
              size: NubiaButtonSize.lg,
              icon: Icons.check_rounded,
              onPressed: state.submitting
                  ? null
                  : () => context.read<ModifyRdvBloc>().add(
                        const ModifyRdvConfirmRequested(),
                      ),
            ),
          ),
        ],
      ),
    );
  }
}
