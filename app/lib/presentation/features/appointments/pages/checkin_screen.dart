import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:nubia_patient/domain/entities/appointment.dart';
import 'package:nubia_patient/presentation/features/appointments/bloc/checkin_bloc.dart';
import 'package:nubia_patient/presentation/theme/nubia_tokens.dart';

/// Dedicated check-in screen.
///
/// Shows appointment summary and a prominent "Je suis arrivé(e)" button.
/// Caller must provide [CheckinBloc] via [BlocProvider].
class CheckinScreen extends StatelessWidget {
  const CheckinScreen({super.key, required this.appointment});

  final Appointment appointment;

  @override
  Widget build(BuildContext context) {
    return BlocListener<CheckinBloc, CheckinState>(
      listener: _handleState,
      child: Scaffold(
        appBar: AppBar(title: const Text('Check-in')),
        body: _CheckinBody(appointment: appointment),
      ),
    );
  }

  void _handleState(BuildContext context, CheckinState state) {
    if (state is CheckinSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Check-in effectué !')),
      );
      Navigator.of(context).pop(state.appointment);
    }
    if (state is CheckinFailure) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(state.message)),
      );
    }
  }
}

// ---------------------------------------------------------------------------

class _CheckinBody extends StatelessWidget {
  const _CheckinBody({required this.appointment});

  final Appointment appointment;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CheckinSummaryCard(appointment: appointment),
          const Spacer(),
          _CheckinConfirmButton(appointment: appointment),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _CheckinSummaryCard extends StatelessWidget {
  const _CheckinSummaryCard({required this.appointment});

  final Appointment appointment;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final tokens = Theme.of(context).extension<NubiaTokens>();
    final dateLabel = DateFormat("EEE d MMM yyyy 'à' HH'h'mm", 'fr')
        .format(appointment.startsAt);

    return Card(
      color: colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Votre rendez-vous',
              style: textTheme.labelLarge?.copyWith(
                color: tokens?.textTertiary ?? colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Text(appointment.motif, style: textTheme.titleMedium),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.person_outline,
                  size: 16,
                  color: tokens?.textTertiary ?? colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${appointment.practitionerName} · ${appointment.practitionerSpecialty}',
                    style: textTheme.bodySmall?.copyWith(
                      color: tokens?.textTertiary ?? colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  Icons.calendar_today_outlined,
                  size: 16,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  dateLabel,
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _CheckinConfirmButton extends StatelessWidget {
  const _CheckinConfirmButton({required this.appointment});

  final Appointment appointment;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CheckinBloc, CheckinState>(
      builder: (context, state) {
        final submitting = state is CheckinInProgress;
        return FilledButton(
          onPressed: submitting
              ? null
              : () => context
                  .read<CheckinBloc>()
                  .add(CheckinRequested(appointment.id)),
          child: submitting
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text("Je suis arrivé(e)"),
        );
      },
    );
  }
}
