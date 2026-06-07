import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'bloc/clinical_session_bloc.dart';
import 'bloc/clinical_session_event.dart';
import 'bloc/clinical_session_state.dart';
import 'models/clinical_session.dart';
import 'widgets/ccam_act_form.dart';
import 'widgets/ccam_act_list.dart';

/// Écran de consultation au fauteuil — séance clinique praticien.
///
/// Flow :
///   1. "Démarrer la consultation" → POST …/start
///   2. Formulaire CCAM + liste des actes
///   3. "Terminer & facturer" → POST …/complete
///
/// Refs : docs/12-api-reference.md §15.
class ClinicalSessionScreen extends StatelessWidget {
  const ClinicalSessionScreen({super.key, required this.appointmentId});

  final String appointmentId;

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ClinicalSessionBloc, ClinicalSessionState>(
      listener: (context, state) {
        if (state is ClinicalSessionCompleted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Séance terminée — facturation déclenchée')),
          );
          Navigator.of(context).pop();
        } else if (state is ClinicalSessionError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.message)),
          );
        }
      },
      builder: (context, state) {
        return Scaffold(
          appBar: AppBar(title: const Text('Consultation au fauteuil')),
          body: switch (state) {
            ClinicalSessionInitial() => _StartView(appointmentId: appointmentId),
            ClinicalSessionLoading() => const Center(
                child: CircularProgressIndicator(),
              ),
            ClinicalSessionActive(:final session) => _SessionBody(
                session: session,
                busy: false,
              ),
            ClinicalSessionActBusy(:final session) => _SessionBody(
                session: session,
                busy: true,
              ),
            ClinicalSessionCompleted() => const Center(
                child: CircularProgressIndicator(),
              ),
            ClinicalSessionError() => const Center(
                child: CircularProgressIndicator(),
              ),
          },
        );
      },
    );
  }
}

class _StartView extends StatelessWidget {
  const _StartView({required this.appointmentId});

  final String appointmentId;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.medical_services_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 24),
            Text(
              'Prêt à démarrer la consultation ?',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              key: const Key('btn_start_session'),
              onPressed: () => context.read<ClinicalSessionBloc>().add(
                    SessionStartRequested(appointmentId: appointmentId),
                  ),
              icon: const Icon(Icons.play_arrow),
              label: const Text('Démarrer la consultation'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionBody extends StatelessWidget {
  const _SessionBody({required this.session, required this.busy});

  final ClinicalSession session;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SessionHeader(patientName: session.patientName),
              const SizedBox(height: 24),
              Text(
                'Actes CCAM',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              CcamActList(
                acts: session.acts,
                enabled: !busy,
                onRemove: (actId) =>
                    context.read<ClinicalSessionBloc>().add(
                          SessionActRemoved(
                            consultationId: session.id,
                            actId: actId,
                          ),
                        ),
              ),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 16),
              Text(
                'Ajouter un acte',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              CcamActForm(
                onSubmit: ({
                  required ccamCode,
                  required label,
                  tooth,
                  amountCents,
                }) =>
                    context.read<ClinicalSessionBloc>().add(
                          SessionActAdded(
                            consultationId: session.id,
                            ccamCode: ccamCode,
                            label: label,
                            tooth: tooth,
                            amountCents: amountCents,
                          ),
                        ),
              ),
            ],
          ),
        ),
        if (busy)
          const Positioned.fill(
            child: ColoredBox(
              color: Color(0x33000000),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 16,
          child: FilledButton.icon(
            key: const Key('btn_complete_session'),
            onPressed: busy
                ? null
                : () => context.read<ClinicalSessionBloc>().add(
                      SessionCompleteRequested(consultationId: session.id),
                    ),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.secondary,
            ),
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('Terminer & facturer'),
          ),
        ),
      ],
    );
  }
}

class _SessionHeader extends StatelessWidget {
  const _SessionHeader({required this.patientName});

  final String patientName;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          Icons.person_outline,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(width: 8),
        Text(patientName, style: Theme.of(context).textTheme.titleLarge),
        const Spacer(),
        Chip(
          label: const Text('En cours'),
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          labelStyle: TextStyle(
            color: Theme.of(context).colorScheme.onPrimaryContainer,
          ),
        ),
      ],
    );
  }
}
