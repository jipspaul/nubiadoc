import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:nubia_patient/domain/entities/appointment.dart';
import 'package:nubia_patient/presentation/features/appointments/bloc/appointment_modify_bloc.dart';
import 'package:nubia_patient/presentation/features/appointments/widgets/slot_grid.dart';

/// Screen to move an existing appointment to a new slot.
///
/// Caller must provide [AppointmentModifyBloc] via [BlocProvider] and
/// dispatch [AppointmentModifyStarted] before navigating here.
class AppointmentModifyScreen extends StatelessWidget {
  const AppointmentModifyScreen({super.key, required this.appointment});

  final Appointment appointment;

  @override
  Widget build(BuildContext context) {
    return BlocListener<AppointmentModifyBloc, AppointmentModifyState>(
      listener: _handleStateChange,
      child: Scaffold(
        appBar: AppBar(title: const Text('Modifier le rendez-vous')),
        body: BlocBuilder<AppointmentModifyBloc, AppointmentModifyState>(
          builder: (context, state) {
            if (state is AppointmentModifyInitial) {
              return const Center(child: CircularProgressIndicator());
            }
            if (state is AppointmentModifyError) {
              return Center(child: Text(state.message));
            }
            if (state is AppointmentModifyReady) {
              return _ModifyBody(state: state);
            }
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }

  void _handleStateChange(
    BuildContext context,
    AppointmentModifyState state,
  ) {
    if (state is AppointmentModifySuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Rendez-vous déplacé avec succès.')),
      );
      Navigator.of(context).pop(state.appointment);
    }
    if (state is AppointmentModifyError) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(state.message)),
      );
    }
  }
}

class _ModifyBody extends StatelessWidget {
  const _ModifyBody({required this.state});

  final AppointmentModifyReady state;

  @override
  Widget build(BuildContext context) {
    final dateLabel = DateFormat('EEE d MMM à HH:mm').format(state.original.startsAt);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CurrentSlotCard(dateLabel: dateLabel, state: state),
          const SizedBox(height: 24),
          Text(
            'Choisir un nouveau créneau',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          SlotGrid(
            slots: state.slots,
            selectedSlot: state.selectedSlot,
            onSlotTap: (slot) => context
                .read<AppointmentModifyBloc>()
                .add(AppointmentModifySlotSelected(slot)),
          ),
          const SizedBox(height: 32),
          _ModifyConfirmButton(state: state),
        ],
      ),
    );
  }
}

class _CurrentSlotCard extends StatelessWidget {
  const _CurrentSlotCard({
    required this.dateLabel,
    required this.state,
  });

  final String dateLabel;
  final AppointmentModifyReady state;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      color: colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Rendez-vous actuel',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 4),
            Text(
              '${state.original.practitionerName} — $dateLabel',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            Text(
              state.original.motif,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModifyConfirmButton extends StatelessWidget {
  const _ModifyConfirmButton({required this.state});

  final AppointmentModifyReady state;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: state.submitting || state.selectedSlot == null
            ? null
            : () => context
                .read<AppointmentModifyBloc>()
                .add(const AppointmentModifySubmitted()),
        child: state.submitting
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('Confirmer le déplacement'),
      ),
    );
  }
}
