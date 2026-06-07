import 'package:equatable/equatable.dart';

/// Statut d'une ordonnance (POST /v1/cabinet/prescriptions + /sign).
enum PrescriptionStatus { draft, signed }

/// Ligne médicament d'une ordonnance.
class PrescriptionItem extends Equatable {
  const PrescriptionItem({
    required this.label,
    required this.posology,
    required this.duration,
    required this.quantity,
    this.form,
  });

  final String label;
  final String posology;
  final String duration;
  final String quantity;

  /// Forme galénique (comprimé, sirop, …) — optionnel.
  final String? form;

  @override
  List<Object?> get props => [label, posology, duration, quantity, form];
}

/// Ordonnance praticien — contrat POST /v1/cabinet/prescriptions.
class Prescription extends Equatable {
  const Prescription({
    required this.id,
    required this.patientId,
    required this.patientName,
    required this.items,
    required this.status,
  });

  final String id;
  final String patientId;
  final String patientName;
  final List<PrescriptionItem> items;
  final PrescriptionStatus status;

  @override
  List<Object?> get props => [id, patientId, patientName, items, status];
}

/// Patient minimal pour le sélecteur patient.
class PatientSummary extends Equatable {
  const PatientSummary({required this.id, required this.name});

  final String id;
  final String name;

  @override
  List<Object?> get props => [id, name];
}
