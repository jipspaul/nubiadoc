import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_patient/domain/entities/prescription.dart';
import 'package:nubia_patient/presentation/features/prescription/bloc/prescription_bloc.dart';
import 'package:nubia_patient/presentation/features/prescription/bloc/prescription_event.dart';
import 'package:nubia_patient/presentation/features/prescription/bloc/prescription_state.dart';
import 'package:nubia_patient/presentation/features/prescription/widgets/prescription_item_form.dart';
import 'package:nubia_patient/presentation/features/prescription/widgets/prescription_item_tile.dart';

/// Écran de création et de signature d'ordonnance (praticien uniquement).
///
/// Flow :
/// 1. [PrescriptionInitial] — sélecteur patient + formulaire médicament.
/// 2. Tap "Créer l'ordonnance" → POST /v1/cabinet/prescriptions.
/// 3. [PrescriptionLoaded] (draft) — récap + bouton "Signer".
/// 4. Tap "Signer" → POST /v1/cabinet/prescriptions/{id}/sign.
/// 5. [PrescriptionLoaded] (signed) — statut signé.
///
/// Le [PrescriptionBloc] doit être injecté par l'appelant via [BlocProvider].
/// L'appelant doit émettre [PrescriptionPatientSelected] avant d'afficher
/// cet écran si un patient est déjà connu (ex. navigation depuis un RDV).
class PrescriptionScreen extends StatelessWidget {
  const PrescriptionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocListener<PrescriptionBloc, PrescriptionState>(
      listener: _handleState,
      child: Scaffold(
        appBar: AppBar(title: const Text('Ordonnance')),
        body: BlocBuilder<PrescriptionBloc, PrescriptionState>(
          builder: (context, state) {
            if (state is PrescriptionLoading) {
              return const Center(child: CircularProgressIndicator());
            }
            if (state is PrescriptionError) {
              return _ErrorBody(
                message: state.message,
                prescription: state.current,
              );
            }
            if (state is PrescriptionLoaded) {
              return _RecapBody(prescription: state.prescription);
            }
            // PrescriptionInitial
            return _DraftBody(draft: state as PrescriptionInitial);
          },
        ),
      ),
    );
  }

  void _handleState(BuildContext context, PrescriptionState state) {
    if (state is PrescriptionError) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(state.message)));
    }
  }
}

// ---------------------------------------------------------------------------

class _DraftBody extends StatelessWidget {
  const _DraftBody({required this.draft});

  final PrescriptionInitial draft;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(child: _DraftContent(draft: draft)),
        _CreateButton(draft: draft),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _DraftContent extends StatelessWidget {
  const _DraftContent({required this.draft});

  final PrescriptionInitial draft;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _PatientHeader(patientName: draft.patientName),
        const SizedBox(height: 16),
        PrescriptionItemForm(
          onSubmit: (item) => context
              .read<PrescriptionBloc>()
              .add(PrescriptionItemAdded(item)),
        ),
        const SizedBox(height: 16),
        if (draft.items.isNotEmpty) ...[
          Text('Médicaments prescrits', style: textTheme.titleSmall),
          const SizedBox(height: 8),
          ...draft.items.asMap().entries.map(
                (entry) => PrescriptionItemTile(
                  item: entry.value,
                  onRemove: () => context.read<PrescriptionBloc>().add(
                        PrescriptionItemRemoved(entry.key),
                      ),
                ),
              ),
        ] else
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Aucun médicament ajouté.',
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _PatientHeader extends StatelessWidget {
  const _PatientHeader({required this.patientName});

  final String? patientName;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      color: colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.person_outline, size: 20),
            const SizedBox(width: 8),
            Text(
              patientName ?? 'Patient non sélectionné',
              style: patientName != null
                  ? textTheme.bodyMedium
                  : textTheme.bodySmall
                      ?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _CreateButton extends StatelessWidget {
  const _CreateButton({required this.draft});

  final PrescriptionInitial draft;

  @override
  Widget build(BuildContext context) {
    final canCreate = draft.patientId != null && draft.items.isNotEmpty;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: FilledButton.icon(
          key: const Key('create_prescription_button'),
          onPressed: canCreate
              ? () => context
                  .read<PrescriptionBloc>()
                  .add(const PrescriptionCreateRequested())
              : null,
          icon: const Icon(Icons.receipt_long_outlined),
          label: const Text("Créer l'ordonnance"),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _RecapBody extends StatelessWidget {
  const _RecapBody({required this.prescription});

  final Prescription prescription;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(child: _RecapContent(prescription: prescription)),
        if (prescription.isDraft) const _SignButton(),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _RecapContent extends StatelessWidget {
  const _RecapContent({required this.prescription});

  final Prescription prescription;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    final statusLabel = prescription.isSigned ? 'Signée' : 'Brouillon';
    final statusColor = prescription.isSigned
        ? colorScheme.primary
        : colorScheme.onSurfaceVariant;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Icon(
              prescription.isSigned
                  ? Icons.verified_outlined
                  : Icons.edit_note_outlined,
              color: statusColor,
            ),
            const SizedBox(width: 8),
            Text(
              'Statut : $statusLabel',
              style: textTheme.titleSmall?.copyWith(color: statusColor),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text('Médicaments prescrits', style: textTheme.titleSmall),
        const SizedBox(height: 8),
        // Lecture seule après création : onRemove est un no-op.
        ...prescription.items.map(
          (item) => PrescriptionItemTile(
            item: item,
            onRemove: () {},
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _SignButton extends StatelessWidget {
  const _SignButton();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: FilledButton.icon(
          key: const Key('sign_prescription_button'),
          onPressed: () => context
              .read<PrescriptionBloc>()
              .add(const PrescriptionSignRequested()),
          icon: const Icon(Icons.draw_outlined),
          label: const Text('Signer'),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.message, this.prescription});

  final String message;
  final Prescription? prescription;

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
            if (prescription != null)
              FilledButton.icon(
                onPressed: () => context
                    .read<PrescriptionBloc>()
                    .add(const PrescriptionSignRequested()),
                icon: const Icon(Icons.refresh),
                label: const Text('Réessayer la signature'),
              )
            else
              OutlinedButton(
                onPressed: () => context.pop(),
                child: const Text('Retour'),
              ),
          ],
        ),
      ),
    );
  }
}
