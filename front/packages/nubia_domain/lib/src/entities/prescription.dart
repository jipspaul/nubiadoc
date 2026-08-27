import 'package:equatable/equatable.dart';

/// A single medication line on a prescription.
class PrescriptionItem extends Equatable {
  final String label;
  final String? form; // e.g. "comprimés", "sirop"
  final String posology;
  final String duration;
  final String quantity;

  /// Mention qui engage le pharmacien : substituable ou non (MTE).
  final bool substitutable;

  /// Motif de la non-substitution, choisi par le praticien (ex. "MTE" —
  /// marge thérapeutique étroite). Pertinent uniquement quand
  /// [substitutable] est `false` ; `null` sinon.
  final String? nonSubstitutionReason;

  /// Mention légale « non renouvelable », choisie par le praticien (pas
  /// déduite d'une règle).
  final bool nonRenouvelable;

  /// Générique effectivement délivré, si substitué (ex. "Amoxicilline
  /// Biogaran").
  final String? dispensedGeneric;

  /// Alerte d'interaction médicamenteuse à afficher sous la ligne (fournie
  /// par le back), ex. "AVK déclaré au dossier patient. Surveillance de
  /// l'INR recommandée ; à signaler au patient." Null/vide : pas d'alerte.
  final String? interactionWarning;

  const PrescriptionItem({
    required this.label,
    this.form,
    required this.posology,
    required this.duration,
    required this.quantity,
    this.substitutable = true,
    this.nonSubstitutionReason,
    this.nonRenouvelable = false,
    this.dispensedGeneric,
    this.interactionWarning,
  });

  @override
  List<Object?> get props => [
        label,
        form,
        posology,
        duration,
        quantity,
        substitutable,
        nonSubstitutionReason,
        nonRenouvelable,
        dispensedGeneric,
        interactionWarning,
      ];
}

enum PrescriptionStatus { draft, signed, sent }

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
