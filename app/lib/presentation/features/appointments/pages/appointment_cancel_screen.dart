import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:nubia_patient/domain/entities/appointment.dart';
import 'package:nubia_patient/presentation/features/appointments/bloc/appointment_cancel_bloc.dart';
import 'package:nubia_patient/presentation/theme/nubia_tokens.dart';

/// Screen to cancel an existing appointment.
///
/// Shows the appointment info, a reason field, and the 24-hour deadline
/// warning. Caller must provide [AppointmentCancelBloc] via [BlocProvider].
class AppointmentCancelScreen extends StatelessWidget {
  const AppointmentCancelScreen({super.key, required this.appointment});

  final Appointment appointment;

  @override
  Widget build(BuildContext context) {
    return BlocListener<AppointmentCancelBloc, AppointmentCancelState>(
      listener: _handleStateChange,
      child: Scaffold(
        appBar: AppBar(title: const Text('Annuler le rendez-vous')),
        body: _CancelBody(appointment: appointment),
      ),
    );
  }

  void _handleStateChange(
    BuildContext context,
    AppointmentCancelState state,
  ) {
    if (state is AppointmentCancelSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Rendez-vous annulé.')),
      );
      Navigator.of(context).pop(true);
    }
    if (state is AppointmentCancelFailure) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(state.message)),
      );
    }
  }
}

class _CancelBody extends StatefulWidget {
  const _CancelBody({required this.appointment});

  final Appointment appointment;

  @override
  State<_CancelBody> createState() => _CancelBodyState();
}

class _CancelBodyState extends State<_CancelBody> {
  final _reasonController = TextEditingController();

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AppointmentSummaryCard(appointment: widget.appointment),
          const SizedBox(height: 16),
          _DeadlineWarning(appointment: widget.appointment),
          const SizedBox(height: 24),
          Text(
            'Motif d\'annulation',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _reasonController,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'Précisez la raison de votre annulation (optionnel)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 32),
          _CancelConfirmButton(
            appointment: widget.appointment,
            reasonController: _reasonController,
          ),
        ],
      ),
    );
  }
}

class _AppointmentSummaryCard extends StatelessWidget {
  const _AppointmentSummaryCard({required this.appointment});

  final Appointment appointment;

  @override
  Widget build(BuildContext context) {
    final dateLabel = DateFormat('EEE d MMM à HH:mm').format(appointment.startsAt);
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      color: colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              appointment.practitionerName,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              '$dateLabel — ${appointment.motif}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _DeadlineWarning extends StatelessWidget {
  const _DeadlineWarning({required this.appointment});

  final Appointment appointment;

  @override
  Widget build(BuildContext context) {
    final hoursLeft =
        appointment.startsAt.difference(DateTime.now()).inHours;
    final tokens = Theme.of(context).extension<NubiaTokens>();

    if (hoursLeft >= 24) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tokens?.warningBg ?? Theme.of(context).colorScheme.errorContainer,
        borderRadius: const BorderRadius.all(Radius.circular(8)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            color: tokens?.warningFg ??
                Theme.of(context).colorScheme.onErrorContainer,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Ce rendez-vous commence dans moins de 24 h. '
              'L\'annulation pourrait entraîner des frais.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: tokens?.warningFg ??
                        Theme.of(context).colorScheme.onErrorContainer,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CancelConfirmButton extends StatelessWidget {
  const _CancelConfirmButton({
    required this.appointment,
    required this.reasonController,
  });

  final Appointment appointment;
  final TextEditingController reasonController;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AppointmentCancelBloc, AppointmentCancelState>(
      builder: (context, state) {
        final submitting = state is AppointmentCancelInProgress;
        return SizedBox(
          width: double.infinity,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: submitting
                ? null
                : () => context
                    .read<AppointmentCancelBloc>()
                    .add(AppointmentCancelRequested(
                      appointment: appointment,
                      reason: reasonController.text.trim(),
                    )),
            child: submitting
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Confirmer l\'annulation'),
          ),
        );
      },
    );
  }
}
