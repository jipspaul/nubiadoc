import 'package:equatable/equatable.dart';

/// A single medication line on a prescription.
class PrescriptionItem extends Equatable {
  final String label;
  final String? form; // e.g. "comprimés", "sirop"
  final String posology;
  final String duration;
  final String quantity;

  const PrescriptionItem({
    required this.label,
    this.form,
    required this.posology,
    required this.duration,
    required this.quantity,
  });

  @override
  List<Object?> get props => [label, form, posology, duration, quantity];
}

enum PrescriptionStatus { draft, signed }

/// An ordonnance created by a practitioner.
class Prescription extends Equatable {
  final String id;
  final String patientId;
  final List<PrescriptionItem> items;
  final PrescriptionStatus status;
  final DateTime createdAt;

  const Prescription({
    required this.id,
    required this.patientId,
    required this.items,
    required this.status,
    required this.createdAt,
  });

  bool get isDraft => status == PrescriptionStatus.draft;
  bool get isSigned => status == PrescriptionStatus.signed;

  @override
  List<Object?> get props => [id, patientId, items, status, createdAt];
}
