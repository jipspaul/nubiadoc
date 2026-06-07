import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_patient/domain/entities/appointment.dart';
import 'package:nubia_patient/presentation/features/clinical/bloc/clinical_session_bloc.dart';
import 'package:nubia_patient/presentation/features/clinical/widgets/act_form.dart';
import 'package:nubia_patient/presentation/features/clinical/widgets/act_list_tile.dart';

/// Clinical session screen — consultation au fauteuil.
///
/// Flow:
/// 1. Initial state → "Démarrer la consultation" button.
/// 2. Session loaded (in_progress) → act form + act list + "Terminer & facturer".
/// 3. Completed → summary snackbar + pop back to appointment list.
///
/// Caller must provide [ClinicalSessionBloc] via [BlocProvider].
class ClinicalSessionScreen extends StatelessWidget {
  const ClinicalSessionScreen({
    super.key,
    required this.appointment,
  });

  final Appointment appointment;

  @override
  Widget build(BuildContext context) {
    return BlocListener<ClinicalSessionBloc, ClinicalSessionState>(
      listener: _handleState,
      child: Scaffold(
        appBar: AppBar(title: const Text('Consultation')),
        body: BlocBuilder<ClinicalSessionBloc, ClinicalSessionState>(
          builder: (context, state) {
            if (state is ClinicalSessionLoading) {
              return const Center(child: CircularProgressIndicator());
            }
            if (state is ClinicalSessionError) {
              return _ErrorBody(
                message: state.message,
                appointment: appointment,
              );
            }
            if (state is ClinicalSessionLoaded) {
              return _SessionBody(
                session: state,
                appointment: appointment,
              );
            }
            // Initial: prompt to start session.
            return _StartSessionBody(appointment: appointment);
          },
        ),
      ),
    );
  }

  void _handleState(BuildContext context, ClinicalSessionState state) {
    if (state is ClinicalSessionCompleted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Séance terminée. Facturation en cours.')),
      );
      context.pop();
    }
    if (state is ClinicalSessionError) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(state.message)),
      );
    }
  }
}

// ---------------------------------------------------------------------------

class _StartSessionBody extends StatelessWidget {
  const _StartSessionBody({required this.appointment});

  final Appointment appointment;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(
            Icons.medical_services_outlined,
            size: 64,
            color: colorScheme.primary,
          ),
          const SizedBox(height: 24),
          Text(
            appointment.motif,
            textAlign: TextAlign.center,
            style: textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            appointment.practitionerName,
            textAlign: TextAlign.center,
            style: textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 40),
          FilledButton.icon(
            onPressed: () => context
                .read<ClinicalSessionBloc>()
                .add(SessionStartRequested(appointment.id)),
            icon: const Icon(Icons.play_circle_outline),
            label: const Text('Démarrer la consultation'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _SessionBody extends StatelessWidget {
  const _SessionBody({
    required this.session,
    required this.appointment,
  });

  final ClinicalSessionLoaded session;
  final Appointment appointment;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: _SessionContent(session: session, appointment: appointment),
        ),
        _CompleteButton(session: session),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _SessionContent extends StatelessWidget {
  const _SessionContent({
    required this.session,
    required this.appointment,
  });

  final ClinicalSessionLoaded session;
  final Appointment appointment;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final acts = session.session.acts;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ActForm(
          loading: session.actLoading,
          onSubmit: ({
            required ccamCode,
            required label,
            tooth,
            amountCents,
          }) {
            context.read<ClinicalSessionBloc>().add(
                  SessionActAdded(
                    consultationId: session.session.id,
                    ccamCode: ccamCode,
                    label: label,
                    tooth: tooth,
                    amountCents: amountCents,
                  ),
                );
          },
        ),
        const SizedBox(height: 20),
        if (acts.isNotEmpty) ...[
          Text('Actes réalisés', style: textTheme.titleSmall),
          const SizedBox(height: 8),
          ...acts.map(
            (act) => ActListTile(
              act: act,
              onRemove: () => context.read<ClinicalSessionBloc>().add(
                    SessionActRemoved(
                      consultationId: session.session.id,
                      actId: act.id,
                    ),
                  ),
            ),
          ),
        ] else ...[
          Center(
            child: Text(
              'Aucun acte ajouté pour l\'instant.',
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _CompleteButton extends StatelessWidget {
  const _CompleteButton({required this.session});

  final ClinicalSessionLoaded session;

  @override
  Widget build(BuildContext context) {
    final submitting = session.actLoading;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: FilledButton.icon(
          onPressed: submitting
              ? null
              : () => context.read<ClinicalSessionBloc>().add(
                    SessionCompleteRequested(session.session.id),
                  ),
          icon: submitting
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check_circle_outline),
          label: const Text('Terminer & facturer'),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.message, required this.appointment});

  final String message;
  final Appointment appointment;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () => context
                  .read<ClinicalSessionBloc>()
                  .add(SessionStartRequested(appointment.id)),
              child: const Text('Réessayer'),
            ),
          ],
        ),
      ),
    );
  }
}
