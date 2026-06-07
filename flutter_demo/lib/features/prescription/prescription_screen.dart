import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'bloc/prescription_bloc.dart';
import 'bloc/prescription_event.dart';
import 'bloc/prescription_state.dart';
import 'widgets/prescription_recap_card.dart';
import 'widgets/prescription_form.dart';

/// Écran principal ordonnance — création et signature.
///
/// Practitioner only. Gère les transitions :
/// [PrescriptionInitial] → form → [PrescriptionCreated] → récap → [PrescriptionSigned].
class PrescriptionScreen extends StatelessWidget {
  const PrescriptionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<PrescriptionBloc, PrescriptionState>(
      listener: _onStateChange,
      builder: (context, state) {
        return Scaffold(
          appBar: AppBar(title: const Text('Ordonnance')),
          body: switch (state) {
            PrescriptionInitial() => const _LoadTrigger(),
            PrescriptionLoading() => const Center(
                child: CircularProgressIndicator(),
              ),
            PrescriptionListLoaded(:final patients) => PrescriptionForm(
                patients: patients,
                onSubmit: (patientId, items) =>
                    context.read<PrescriptionBloc>().add(
                          PrescriptionCreateRequested(
                            patientId: patientId,
                            items: items,
                          ),
                        ),
              ),
            PrescriptionCreated(:final prescription, :final patients) =>
              PrescriptionRecapCard(
                prescription: prescription,
                patients: patients,
                onSign: () => context.read<PrescriptionBloc>().add(
                      PrescriptionSignRequested(id: prescription.id),
                    ),
                onNew: () => context.read<PrescriptionBloc>().add(
                      const PrescriptionLoadRequested(),
                    ),
              ),
            PrescriptionSigned(:final prescription, :final patients) =>
              PrescriptionRecapCard(
                prescription: prescription,
                patients: patients,
                onSign: null,
                onNew: () => context.read<PrescriptionBloc>().add(
                      const PrescriptionLoadRequested(),
                    ),
              ),
            PrescriptionError(:final message) => _ErrorView(
                message: message,
                onRetry: () => context
                    .read<PrescriptionBloc>()
                    .add(const PrescriptionLoadRequested()),
              ),
          },
        );
      },
    );
  }

  void _onStateChange(BuildContext context, PrescriptionState state) {
    if (state is PrescriptionCreated) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ordonnance créée')),
      );
    }
    if (state is PrescriptionSigned) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ordonnance signée (eIDAS)')),
      );
    }
  }
}

class _LoadTrigger extends StatefulWidget {
  const _LoadTrigger();

  @override
  State<_LoadTrigger> createState() => _LoadTriggerState();
}

class _LoadTriggerState extends State<_LoadTrigger> {
  @override
  void initState() {
    super.initState();
    context.read<PrescriptionBloc>().add(const PrescriptionLoadRequested());
  }

  @override
  Widget build(BuildContext context) =>
      const Center(child: CircularProgressIndicator());
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: onRetry,
            child: const Text('Réessayer'),
          ),
        ],
      ),
    );
  }
}
