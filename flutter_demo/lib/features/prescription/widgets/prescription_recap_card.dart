import 'package:flutter/material.dart';

import '../../models/prescription.dart';

/// Carte récapitulative d'une ordonnance (brouillon ou signée).
///
/// Affiche le statut, le patient, les lignes médicament et les actions
/// disponibles ("Signer" si brouillon, "Nouvelle ordonnance" toujours).
class PrescriptionRecapCard extends StatelessWidget {
  const PrescriptionRecapCard({
    super.key,
    required this.prescription,
    required this.patients,
    required this.onSign,
    required this.onNew,
  });

  final Prescription prescription;
  final List<PatientSummary> patients;

  /// Null quand l'ordonnance est déjà signée.
  final VoidCallback? onSign;
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _PrescriptionStatusBadge(status: prescription.status),
        const SizedBox(height: 16),
        Text(
          prescription.patientName,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(
          'Réf : ${prescription.id}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        ...prescription.items.map(
          (item) => _MedicationItemTile(item: item),
        ),
        const SizedBox(height: 24),
        if (onSign != null)
          FilledButton.icon(
            key: const Key('btn_sign'),
            onPressed: onSign,
            icon: const Icon(Icons.draw_outlined),
            label: const Text('Signer (eIDAS)'),
          ),
        if (onSign != null) const SizedBox(height: 8),
        OutlinedButton(
          key: const Key('btn_new_prescription'),
          onPressed: onNew,
          child: const Text('Nouvelle ordonnance'),
        ),
      ],
    );
  }
}

class _PrescriptionStatusBadge extends StatelessWidget {
  const _PrescriptionStatusBadge({required this.status});

  final PrescriptionStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (label, bg, fg) = switch (status) {
      PrescriptionStatus.draft => (
          'Brouillon',
          scheme.secondaryContainer,
          scheme.onSecondaryContainer,
        ),
      PrescriptionStatus.signed => (
          'Signée',
          scheme.primaryContainer,
          scheme.onPrimaryContainer,
        ),
    };
    return Align(
      alignment: Alignment.centerLeft,
      child: Chip(
        key: const Key('prescription_status_chip'),
        label: Text(label),
        backgroundColor: bg,
        labelStyle:
            Theme.of(context).textTheme.labelSmall?.copyWith(color: fg),
        side: BorderSide.none,
      ),
    );
  }
}

class _MedicationItemTile extends StatelessWidget {
  const _MedicationItemTile({required this.item});

  final PrescriptionItem item;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item.label, style: textTheme.titleSmall),
            if (item.form != null) ...[
              const SizedBox(height: 2),
              Text(item.form!, style: textTheme.bodySmall),
            ],
            const SizedBox(height: 4),
            Text('Posologie : ${item.posology}', style: textTheme.bodySmall),
            Text('Durée : ${item.duration}', style: textTheme.bodySmall),
            Text('Quantité : ${item.quantity}', style: textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
