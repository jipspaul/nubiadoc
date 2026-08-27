import 'package:equatable/equatable.dart';

import 'medication_reference.dart';

/// Posologie décomposée : dose unitaire, fréquence quotidienne et durée en
/// jours. Permet de calculer la quantité totale plutôt que de la saisir en
/// texte libre (design-v2, écran « Composition d'ordonnance »).
class StructuredPosology extends Equatable {
  /// Dose prise à chaque fréquence (ex. 1 comprimé).
  final double dose;

  /// Nombre de prises par jour (ex. 3 pour "3 fois par jour").
  final double frequencyPerDay;

  /// Durée du traitement en jours.
  final int durationInDays;

  const StructuredPosology({
    required this.dose,
    required this.frequencyPerDay,
    required this.durationInDays,
  });

  /// Quantité totale nécessaire = dose × fréquence × durée.
  double get computedQuantity => dose * frequencyPerDay * durationInDays;

  @override
  List<Object?> get props => [dose, frequencyPerDay, durationInDays];
}

/// A single medication line on a prescription.
class PrescriptionItem extends Equatable {
  final String label;
  final String? form; // e.g. "comprimés", "sirop"

  /// Référence produit issue du référentiel médicament (DCI, forme
  /// galénique, classe thérapeutique), quand le praticien a sélectionné un
  /// résultat de recherche référentiel plutôt que du texte libre. `null`
  /// pour les lignes historiques (rétro-compatibilité DTO) ou les produits
  /// hors référentiel.
  final MedicationReference? productReference;

  final String posology;
  final String duration;
  final String quantity;

  /// Posologie décomposée (dose, fréquence, durée), quand le praticien l'a
  /// saisie sous cette forme plutôt qu'en texte libre. `null` pour les
  /// lignes historiques (rétro-compatibilité DTO) : dans ce cas [posology],
  /// [duration] et [quantity] restent les seules sources de vérité.
  final StructuredPosology? structuredPosology;

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
    this.productReference,
    required this.posology,
    required this.duration,
    required this.quantity,
    this.structuredPosology,
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
        productReference,
        posology,
        duration,
        quantity,
        structuredPosology,
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
